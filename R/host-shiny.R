# Hosting MCP Apps in Shiny
#
# A Shiny app can host MCP Apps the way a chat client does: the app's page
# runs in a sandboxed iframe, and a small host script in the Shiny page
# speaks the MCP Apps protocol to it. The page's requests (tools/call,
# resources/read) travel over the Shiny session to R, which passes them to
# the app's source: apps in this process, or a remote server through
# mcp_client(). See design/hosting.md.
#
# Each card or pane carries a descriptor (instance, source, tool, arguments,
# result) rather than the page. When it starts, the host script asks R to
# attach it, and R answers with the page. A card restored with a saved
# conversation attaches the same way: R recreates its instance from the
# descriptor if the session hosts its source.

#' Methods the host passes on for an app's page
#' @noRd
HOST_PAGE_METHODS <- c(
  "tools/call",
  "resources/read",
  "resources/list",
  "resources/templates/list",
  "ping"
)

#' @noRd
shinymcp_host_dependency <- function() {
  htmltools::htmlDependency(
    name = "shinymcp-host",
    version = as.character(utils::packageVersion("shinymcp")),
    src = system_file("js"),
    script = "shinymcp-host.js",
    stylesheet = "shinymcp-host.css",
    all_files = FALSE
  )
}

#' @noRd
sanitize_dom_id <- function(x) {
  x <- gsub("[^A-Za-z0-9_-]", "-", x)
  if (grepl("^[0-9]", x)) {
    x <- paste0("shinymcp-", x)
  }
  x
}

#' @noRd
root_shiny_session <- function(session) {
  if (is.null(session)) {
    return(NULL)
  }
  root <- tryCatch(session$rootScope(), error = function(e) NULL)
  root %||% session
}

#' @noRd
active_shiny_session <- function() {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    return(NULL)
  }
  session <- root_shiny_session(shiny::getDefaultReactiveDomain())
  if (
    inherits(session, c("ShinySession", "MockShinySession", "session_proxy"))
  ) {
    session
  } else {
    NULL
  }
}

#' Host markup: a toolbar, an error area, and the iframe
#' @noRd
mcp_host_markup <- function(
  id,
  config = NULL,
  height = "auto",
  toolbar = TRUE,
  title = NULL,
  fallback = NULL
) {
  root <- htmltools::tags$div(
    id = id,
    class = "shinymcp-host",
    `data-shinymcp-host` = "",
    `data-shinymcp-height` = height,
    if (toolbar) {
      htmltools::tags$div(
        class = "shinymcp-host-toolbar",
        htmltools::tags$span(
          class = "shinymcp-host-title",
          title %||% config$title
        ),
        htmltools::tags$span(
          class = "shinymcp-host-busy",
          `data-shinymcp-host-busy` = "",
          hidden = NA,
          role = "status",
          "Working"
        ),
        htmltools::tags$span(
          class = "shinymcp-host-actions",
          htmltools::tags$button(
            type = "button",
            class = "shinymcp-host-button",
            `data-shinymcp-action` = "execute",
            hidden = NA,
            "Run"
          ),
          htmltools::tags$button(
            type = "button",
            class = "shinymcp-host-button",
            `data-shinymcp-action` = "fullscreen",
            `aria-pressed` = "false",
            "Full screen"
          )
        )
      )
    },
    htmltools::tags$div(
      class = "shinymcp-host-error",
      `data-shinymcp-host-error` = "",
      role = "alert",
      hidden = NA
    ),
    if (!is.null(fallback)) {
      htmltools::tags$div(
        class = "shinymcp-host-fallback",
        `data-shinymcp-host-fallback` = "",
        hidden = NA,
        fallback
      )
    },
    htmltools::tags$iframe(
      class = "shinymcp-host-frame",
      `data-shinymcp-host-frame` = "",
      title = title %||% config$title %||% "MCP App"
    ),
    if (!is.null(config)) {
      htmltools::tags$script(
        type = "application/json",
        class = "shinymcp-host-config",
        htmltools::HTML(json_for_script(config))
      )
    }
  )
  htmltools::attachDependencies(root, shinymcp_host_dependency())
}

# ---- The session's registry ----

#' The per-session registry of sources and hosted instances, and the
#' observer that serves them
#' @noRd
ensure_shiny_host_registry <- function(session) {
  session <- root_shiny_session(session)
  if (is.null(session)) {
    shinymcp_abort("A running Shiny session is required to host an MCP App.")
  }
  registry <- session$userData$.shinymcp_hosts
  if (!is.null(registry)) {
    return(registry)
  }

  registry <- new_host_registry()

  shiny::observeEvent(
    session$input$shinymcp_host_event,
    {
      event <- session$input$shinymcp_host_event
      handle_host_event(session, registry, event)
    },
    ignoreNULL = TRUE
  )

  session$onSessionEnded(function() {
    for (id in ls(registry$instances)) {
      mcp_host_dispose(registry$instances[[id]])
    }
  })

  session$userData$.shinymcp_hosts <- registry
  registry
}

#' @noRd
new_host_registry <- function() {
  registry <- new.env(parent = emptyenv())
  registry$instances <- new.env(parent = emptyenv())
  registry$sources <- new.env(parent = emptyenv())
  registry$pages <- new.env(parent = emptyenv())
  # Set by a chat host: called with the state and the params.
  registry$on_card_message <- NULL
  registry
}

#' Make a source known to the session, so restored cards can attach to it
#' @noRd
register_host_source <- function(registry, source) {
  source <- as_host_source(source)
  registry$sources[[source$key]] <- source
  source
}

#' The instance with an id, or NULL
#' @noRd
host_instance <- function(registry, id) {
  if (!is_string(id) || !nzchar(id)) {
    return(NULL)
  }
  registry$instances[[id]]
}

#' The instances a registry hosts, optionally of one kind
#' @noRd
host_instances <- function(registry, kind = NULL) {
  states <- mget(ls(registry$instances), envir = registry$instances)
  Filter(
    function(s) !isTRUE(s$disposed) && (is.null(kind) || s$kind %in% kind),
    unname(states)
  )
}

#' The tool that opens a source's app by default
#'
#' The first tool the model may call that declares a page, else the first
#' tool the model may call.
#' @noRd
default_source_tool <- function(source) {
  tools <- Filter(
    function(t) tool_wire_visible_to(t, "model"),
    source$tools()
  )
  with_page <- Filter(function(t) !is.null(tool_resource_uri(t)), tools)
  pick <- c(with_page, tools)
  if (length(pick)) pick[[1]]$name
}

#' Register an app instance with a Shiny session
#'
#' @return A list with the host `state` (an environment) and the `config`
#'   (descriptor) the host script reads.
#' @noRd
register_shiny_host_instance <- function(
  session,
  source,
  instance_id = unique_id("host"),
  tool = NULL,
  arguments = NULL,
  result = NULL,
  kind = "pane",
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto",
  title = NULL
) {
  registry <- ensure_shiny_host_registry(session)
  source <- register_host_source(registry, source)
  entry <- tool %||% default_source_tool(source)
  definition <- if (!is.null(entry)) source_tool(source, entry)
  if (is.null(definition)) {
    if (is.null(entry)) {
      shinymcp_abort(
        "{.val {source$key}} has no tool to open.",
        class = "shinymcp_error_validation"
      )
    }
    shinymcp_abort(
      "{.val {source$key}} has no tool called {.val {entry}}.",
      class = "shinymcp_error_validation"
    )
  }
  if (is.null(tool_resource_uri(definition))) {
    shinymcp_abort(
      "{.val {entry}} doesn't declare an app to show.",
      class = "shinymcp_error_validation"
    )
  }
  interaction <- source$interaction(entry, trigger, debounce_ms)
  config <- if (!is.null(interaction)) {
    compact_list(list(
      trigger = interaction$trigger,
      debounceMs = interaction$debounce_ms
    ))
  }
  state <- new_mcp_host_state(
    source,
    instance_id = instance_id,
    tool = entry,
    arguments = arguments,
    result = result,
    kind = kind,
    title = title %||% definition$title %||% definition$annotations$title,
    config = config
  )
  registry$instances[[instance_id]] <- state
  list(
    state = state,
    config = host_descriptor(
      state,
      height = height,
      trigger = interaction$trigger
    )
  )
}

#' A pane's trigger and debounce: the host's settings, else the app's
#' @noRd
resolve_host_interaction <- function(app, trigger = NULL, debounce_ms = NULL) {
  defaults <- app$interaction_defaults()
  trigger <- if (is.null(trigger)) {
    defaults$trigger %||% "debounce"
  } else {
    rlang::arg_match0(trigger, c("debounce", "change", "submit", "manual"))
  }
  list(
    trigger = trigger,
    debounce_ms = debounce_ms %||% defaults$debounce_ms %||% 250
  )
}

#' What a card or pane carries: enough to attach, or to be recreated
#' @noRd
host_descriptor <- function(state, height = "auto", trigger = NULL) {
  compact_list(list(
    instanceId = state$instance_id,
    source = state$source$key,
    tool = state$tool,
    arguments = state$arguments %||% json_object(),
    result = state$result,
    title = state$title,
    height = height,
    trigger = trigger,
    version = as.character(utils::packageVersion("shinymcp"))
  ))
}

#' Recreate an instance from a descriptor the page sent back
#'
#' For cards restored with a saved conversation. The descriptor is trusted
#' only to name a source this session hosts and one of its tools; nothing
#' is called.
#' @noRd
restore_host_instance <- function(registry, descriptor) {
  id <- descriptor$instanceId
  key <- descriptor$source
  tool <- descriptor$tool
  if (!is_string(id) || !is_string(key) || !is_string(tool)) {
    return(NULL)
  }
  source <- if (nzchar(key)) registry$sources[[key]]
  if (is.null(source) || !nzchar(id)) {
    return(NULL)
  }
  definition <- tryCatch(source_tool(source, tool), error = function(e) NULL)
  if (is.null(definition) || is.null(tool_resource_uri(definition))) {
    return(NULL)
  }
  state <- new_mcp_host_state(
    source,
    instance_id = id,
    tool = tool,
    arguments = if (is_json_object(descriptor$arguments)) descriptor$arguments,
    result = if (is_json_object(descriptor$result)) descriptor$result,
    kind = "card",
    title = definition$title %||% definition$annotations$title
  )
  registry$instances[[id]] <- state
  state
}

# ---- Opening an app ----

#' Call an instance's tool, for a pane or a card without a result
#'
#' The result is kept on the state and, once the page is attached, sent to
#' it; if the call fails the page is told it was cancelled.
#' @noRd
start_host_call <- function(session, state) {
  if (!is.null(state$result)) {
    return(invisible())
  }
  # A newer call (open() with other arguments) replaces an older one.
  seq <- (state$call_seq %||% 0L) + 1L
  state$call_seq <- seq
  state$call_error <- NULL
  current <- function() {
    identical(state$call_seq, seq) && !isTRUE(state$disposed)
  }
  promises::then(
    state$source$call_async(
      state$tool,
      state$arguments,
      host_call_context(session)
    ),
    onFulfilled = function(call) {
      if (!current()) {
        return(invisible())
      }
      state$result <- call$result
      mcp_host_record_call(state, state$tool, state$arguments, call$result)
      if (isTRUE(state$attached)) {
        send_host_command(session, state, "tool-result", result = call$result)
      }
    },
    onRejected = function(e) {
      if (!current()) {
        return(invisible())
      }
      state$call_error <- conditionMessage(e)
      if (isTRUE(state$attached)) {
        send_host_command(
          session,
          state,
          "tool-cancelled",
          reason = conditionMessage(e)
        )
      }
    }
  )
  invisible()
}

#' @noRd
host_call_context <- function(session) {
  compact_list(list(
    transport = "in-process",
    user = tryCatch(session$user, error = function(e) NULL),
    groups = tryCatch(session$groups, error = function(e) NULL)
  ))
}

#' @noRd
send_host_command <- function(session, state, command, ...) {
  session$sendCustomMessage(
    "shinymcp-host-command",
    compact_list(list(instanceId = state$instance_id, command = command, ...))
  )
}

#' The page for an instance: its HTML and `_meta.ui`, kept for the session
#' @noRd
host_page_async <- function(registry, state, uri) {
  key <- paste(
    state$source$key,
    uri,
    as.character(to_json(state$config %||% list())),
    sep = "\r"
  )
  cached <- registry$pages[[key]]
  if (!is.null(cached)) {
    return(cached)
  }
  page <- promises::then(
    state$source$page_async(uri, state$config),
    onRejected = function(e) {
      if (exists(key, envir = registry$pages, inherits = FALSE)) {
        rm(list = key, envir = registry$pages)
      }
      stop(e)
    }
  )
  registry$pages[[key]] <- page
  page
}

#' Answer a card or pane that asks to attach
#' @noRd
host_attach <- function(session, registry, event) {
  descriptor <- event$descriptor %||% list()
  instance_id <- event$instanceId %||% descriptor$instanceId %||% ""
  reply <- function(message) {
    session$sendCustomMessage(
      "shinymcp-host-attached",
      c(list(instanceId = instance_id, requestId = event$requestId), message)
    )
  }
  fail <- function(text) reply(list(ok = FALSE, error = text))

  state <- host_instance(registry, instance_id)
  if (is.null(state)) {
    state <- restore_host_instance(registry, descriptor)
  }
  if (is.null(state) || isTRUE(state$disposed)) {
    fail("This app isn't available any more.")
    return(invisible())
  }

  tools <- state$source$tools_async()
  promises::then(
    tools,
    onFulfilled = function(tools) {
      definition <- NULL
      for (tool in tools) {
        if (identical(tool$name, state$tool)) {
          definition <- tool
        }
      }
      uri <- if (!is.null(definition)) tool_resource_uri(definition)
      if (is.null(uri)) {
        fail(paste0("The tool ", state$tool, " doesn't show an app."))
        return(invisible())
      }
      app_tools <- vapply(
        Filter(function(t) tool_wire_visible_to(t, "app"), tools),
        function(t) t$name,
        character(1)
      )
      promises::then(
        host_page_async(registry, state, uri),
        onFulfilled = function(page) {
          ui <- page$meta$ui %||% list()
          if (isTRUE(state$default_title)) {
            state$title <- html_page_title(page$html) %||% state$title
          }
          state$attached <- TRUE
          reply(compact_list(list(
            ok = TRUE,
            title = state$title,
            page = compact_list(list(
              html = page$html,
              csp = ui$csp,
              permissions = ui$permissions,
              prefersBorder = ui$prefersBorder
            )),
            tool = definition,
            toolInput = state$arguments %||% json_object(),
            toolResult = state$result,
            cancelled = if (is.null(state$result)) state$call_error,
            appTools = I(app_tools)
          )))
        },
        onRejected = function(e) {
          fail(paste("Couldn't load the app:", conditionMessage(e)))
        }
      )
    },
    onRejected = function(e) {
      fail(paste("Couldn't reach the app's server:", conditionMessage(e)))
    }
  )
  invisible()
}

# ---- Requests from the page ----

#' Answer one message from a hosted app's page
#' @noRd
handle_host_event <- function(session, registry, event) {
  type <- event$type %||% "request"
  if (identical(type, "attach")) {
    return(host_attach(session, registry, event))
  }
  instance_id <- event$instanceId %||% ""
  state <- host_instance(registry, instance_id)

  if (identical(type, "notification")) {
    if (!is.null(state)) {
      mcp_host_notification(state, event$method, event$params %||% list())
      if (
        identical(event$method, "ui/message") &&
          identical(state$kind, "card") &&
          is.function(registry$on_card_message)
      ) {
        registry$on_card_message(state, event$params %||% list())
      }
    }
    return(invisible())
  }
  if (identical(type, "dispose")) {
    if (!is.null(state)) {
      mcp_host_dispose(state)
      rm(list = instance_id, envir = registry$instances)
    }
    return(invisible())
  }

  message <- event$message
  id <- request_id(message)
  reply <- function(response) {
    session$sendCustomMessage(
      "shinymcp-host-response",
      list(
        instanceId = instance_id,
        requestId = event$requestId,
        response = strip_http_status(response)
      )
    )
  }
  if (is.null(state)) {
    reply(jsonrpc_error(
      id,
      RPC_INVALID_REQUEST,
      "This app is no longer running."
    ))
    return(invisible())
  }
  method <- message$method
  if (!is_string(method) || !method %in% HOST_PAGE_METHODS) {
    reply(jsonrpc_error(
      id,
      RPC_METHOD_NOT_FOUND,
      paste0("The host doesn't pass on ", method %||% "that request", ".")
    ))
    return(invisible())
  }

  allowed <- if (identical(method, "tools/call")) {
    promises::then(state$source$tools_async(), function(tools) {
      name <- message$params$name
      for (tool in tools) {
        if (identical(tool$name, name)) {
          return(tool_wire_visible_to(tool, "app"))
        }
      }
      FALSE
    })
  } else {
    promises::promise_resolve(TRUE)
  }

  promises::then(
    allowed,
    onFulfilled = function(ok) {
      if (!isTRUE(ok)) {
        reply(jsonrpc_error(
          id,
          RPC_INVALID_PARAMS,
          paste0(
            "The app can't call the tool ",
            as.character(to_json(message$params$name %||% "")),
            "."
          )
        ))
        return(invisible())
      }
      promises::then(
        state$source$send_async(message, host_call_context(session)),
        onFulfilled = function(response) {
          # Answers that arrive after the app closed (a long poll) go
          # nowhere.
          if (isTRUE(state$disposed)) {
            return(invisible())
          }
          if (identical(method, "tools/call") && !is.null(response$result)) {
            mcp_host_record_call(
              state,
              message$params$name,
              message$params$arguments,
              response$result
            )
          }
          reply(response)
        },
        onRejected = function(e) {
          reply(jsonrpc_error(id, RPC_INTERNAL_ERROR, conditionMessage(e)))
        }
      )
    },
    onRejected = function(e) {
      reply(jsonrpc_error(id, RPC_INTERNAL_ERROR, conditionMessage(e)))
    }
  )
  invisible()
}

# ---- Panes ----

#' Host an MCP App in a Shiny app
#'
#' @description
#' `mcp_host_ui()` and `mcp_host_server()` show an MCP App in a pane of a
#' Shiny app, as a chat client would: the app's page runs in a sandboxed
#' frame, and its tool calls go through R to the app's server. Use it to
#' reuse an app built for chat clients as part of a dashboard, to react in
#' Shiny to what someone does in it, or to see what an app tells the model
#' before you give it to one.
#'
#' The app can come from anywhere: an [McpApp] in the same R process, or
#' any MCP server through [mcp_client()], including Shiny apps served with
#' Shiny's own MCP support.
#'
#' `mcp_embed()` does both halves at once, for UI created on the server,
#' such as inside [shiny::renderUI()].
#'
#' When the pane opens, R calls the app's tool with `arguments`, as a model
#' would, and passes the result to the app.
#'
#' @param id Module id.
#' @param source Where the app comes from: an [McpApp] (or a list of
#'   them), or an [McpClient] from [mcp_client()].
#' @param tool The tool that opens the app. Defaults to the first tool the
#'   model may call that shows an app.
#' @param arguments Named list of arguments for that call.
#' @param trigger,debounce_ms For apps made with shinymcp in this process:
#'   override the app's own `trigger` and `debounce_ms`. `trigger =
#'   "manual"` shows a Run button and calls tools only when it's pressed or
#'   when `execute()` is called.
#' @param height `"auto"` to follow the app's size, or a CSS height.
#' @return `mcp_host_ui()` and `mcp_embed()` return UI. `mcp_host_server()`
#'   returns a list of reactives and functions:
#'
#'   * `model_context()`: the latest context the app published for the
#'     model.
#'   * `last_tool_call()`: the latest tool call, a list with `name`,
#'     `arguments`, and `result` (the MCP result).
#'   * `last_result()`: the MCP result of the latest tool call.
#'   * `messages()`: messages the app asked to post to the chat.
#'   * `open(arguments = NULL, tool = NULL)`: open the app again, calling
#'     the tool with new arguments.
#'   * `execute(inputs = NULL)`: for apps made with shinymcp, call the
#'     app's tools now, optionally setting inputs first.
#'   * `dispose()`: shut the app down.
#' @family hosting
#' @export
#' @examples
#' \dontrun{
#' library(shiny)
#' ui <- bslib::page_fillable(mcp_host_ui("explorer"))
#' server <- function(input, output, session) {
#'   host <- mcp_host_server("explorer", app, arguments = list(species = "Gentoo"))
#'   observe(print(host$model_context()))
#' }
#' shinyApp(ui, server)
#'
#' # An app on a remote server
#' server <- function(input, output, session) {
#'   sales <- mcp_client("https://connect.example.com/sales/mcp")
#'   mcp_host_server("explorer", sales, arguments = list(region = "West"))
#' }
#' }
mcp_host_ui <- function(id, height = "auto") {
  rlang::check_installed("shiny", reason = "for `mcp_host_ui()`.")
  mcp_host_markup(shiny::NS(id)("host"), height = height)
}

#' @rdname mcp_host_ui
#' @export
mcp_host_server <- function(
  id,
  source,
  tool = NULL,
  arguments = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto"
) {
  rlang::check_installed(
    c("shiny", "promises", "later"),
    reason = "for `mcp_host_server()`."
  )
  source <- as_host_source(source)
  shiny::moduleServer(id, function(input, output, session) {
    root <- root_shiny_session(session)
    registered <- register_shiny_host_instance(
      session = root,
      source = source,
      instance_id = unique_id(paste0("host-", sanitize_name(source$key))),
      tool = tool,
      arguments = arguments,
      trigger = trigger,
      debounce_ms = debounce_ms,
      height = height
    )
    state <- registered$state
    reactive_state <- host_reactives(state)
    start_host_call(root, state)

    session$onFlushed(
      function() {
        session$sendCustomMessage(
          "shinymcp-host-init",
          list(id = session$ns("host"), config = registered$config)
        )
      },
      once = TRUE
    )

    c(
      reactive_state,
      list(
        instance_id = shiny::reactive(state$instance_id),
        open = function(arguments = NULL, tool = NULL) {
          if (!is.null(tool)) {
            definition <- source_tool(state$source, tool)
            if (is.null(definition) || is.null(tool_resource_uri(definition))) {
              shinymcp_abort(
                "{.val {state$source$key}} has no tool called {.val {tool}} that shows an app.",
                class = "shinymcp_error_validation"
              )
            }
            state$tool <- tool
          }
          state$arguments <- arguments %||% json_object()
          state$result <- NULL
          state$attached <- FALSE
          send_host_command(root, state, "reopen")
          start_host_call(root, state)
          invisible()
        },
        execute = function(inputs = NULL) {
          send_host_command(root, state, "execute", inputs = inputs)
        },
        reset = function() {
          send_host_command(root, state, "reset")
        },
        dispose = function() {
          send_host_command(root, state, "dispose")
          mcp_host_dispose(state)
        }
      )
    )
  })
}

#' @rdname mcp_host_ui
#' @export
mcp_embed <- function(
  source,
  id = NULL,
  tool = NULL,
  arguments = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto"
) {
  rlang::check_installed(
    c("shiny", "promises", "later"),
    reason = "for `mcp_embed()`."
  )
  session <- active_shiny_session()
  if (is.null(session)) {
    if (is.null(id)) {
      shinymcp_abort(
        "Call {.fn mcp_embed} inside a running Shiny session, or use {.fn mcp_host_ui} and {.fn mcp_host_server}.",
        class = "shinymcp_error_validation"
      )
    }
    return(mcp_host_ui(id, height = height))
  }
  source <- as_host_source(source)
  registered <- register_shiny_host_instance(
    session = session,
    source = source,
    instance_id = unique_id(paste0("host-", sanitize_name(source$key))),
    tool = tool,
    arguments = arguments,
    trigger = trigger,
    debounce_ms = debounce_ms,
    height = height
  )
  start_host_call(session, registered$state)
  dom_id <- sanitize_dom_id(id %||% registered$state$instance_id)
  mcp_host_markup(dom_id, config = registered$config, height = height)
}

#' Reactive views of a host instance's state
#' @noRd
host_reactives <- function(state) {
  model_context <- shiny::reactiveVal(NULL)
  last_tool_call <- shiny::reactiveVal(NULL)
  messages <- shiny::reactiveVal(list())
  state$on_model_context <- function(value) model_context(value)
  state$on_tool_call <- function(value) last_tool_call(value)
  state$on_message <- function(value) {
    messages(c(shiny::isolate(messages()), list(value)))
  }
  list(
    model_context = shiny::reactive(model_context()),
    last_tool_call = shiny::reactive(last_tool_call()),
    last_result = shiny::reactive(last_tool_call()$result),
    messages = shiny::reactive(messages())
  )
}
