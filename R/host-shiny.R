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
  # Set by chat hosts, by key: what each does with its cards' messages, and
  # its check of their pages' calls.
  registry$chat_hosts <- list()
  # By source key, every `on_app_call` the session's hosts gave for that
  # source: the checks a restored card's calls go through.
  registry$app_call_hooks <- new.env(parent = emptyenv())
  registry
}

#' Make a source known to the session, so restored cards can attach to it
#'
#' `on_app_call` is the check the host registering it gives the calls its
#' pages make; the session keeps each one given for the source.
#' @noRd
register_host_source <- function(registry, source, on_app_call = NULL) {
  source <- as_host_source(source)
  registry$sources[[source$key]] <- source
  if (is.function(on_app_call)) {
    registry$app_call_hooks[[source$key]] <- unique_functions(c(
      registry$app_call_hooks[[source$key]],
      list(on_app_call)
    ))
  }
  source
}

#' The key of the chat host a card belongs to, or NULL
#'
#' The one whose tool made it, or, for a card built by hand, the session's
#' only chat host.
#' @noRd
card_chat_key <- function(registry, state) {
  if (is_string(state$owner)) {
    return(state$owner)
  }
  keys <- names(registry$chat_hosts)
  if (length(keys) == 1) keys
}

#' @noRd
card_chat_host <- function(registry, state) {
  key <- card_chat_key(registry, state)
  if (!is.null(key)) registry$chat_hosts[[key]]
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
  default_tool_name(source$tools())
}

#' @noRd
default_tool_name <- function(tools) {
  tools <- Filter(function(t) tool_wire_visible_to(t, "model"), tools)
  with_page <- Filter(function(t) !is.null(tool_resource_uri(t)), tools)
  pick <- c(with_page, tools)
  if (length(pick)) pick[[1]]$name
}

#' The tool an instance opens, from a source's tools
#'
#' The one named, or the source's default. An error if there's no such
#' tool, or it doesn't show an app.
#' @noRd
host_tool <- function(source, tools, name = NULL) {
  name <- name %||% default_tool_name(tools)
  if (is.null(name)) {
    shinymcp_abort(
      "{.val {source$key}} has no tool to open.",
      class = "shinymcp_error_validation"
    )
  }
  for (tool in tools) {
    if (identical(tool$name, name)) {
      if (is.null(tool_resource_uri(tool))) {
        shinymcp_abort(
          "The tool {.val {name}} doesn't show an app.",
          class = "shinymcp_error_validation"
        )
      }
      return(tool)
    }
  }
  shinymcp_abort(
    "{.val {source$key}} has no tool called {.val {name}}.",
    class = "shinymcp_error_validation"
  )
}

#' Settle an instance's tool and title from the tool's definition
#' @noRd
settle_host_tool <- function(state, definition) {
  state$tool <- definition$name
  title <- definition$title %||% definition$annotations$title
  if (isTRUE(state$default_title) && !is.null(title)) {
    state$title <- title
    state$default_title <- FALSE
  }
  definition
}

#' A promise of the tool an instance opens, checked against its source
#'
#' A remote server's tools are listed without blocking the session. The
#' promise is made when first needed and kept; if it fails (the server
#' couldn't be reached), the next attach or call tries again.
#' @noRd
host_ready <- function(state) {
  if (!is.null(state$ready)) {
    return(state$ready)
  }
  name <- state$tool
  tools <- tryCatch(
    state$source$tools_async(),
    error = function(e) promises::promise_reject(e)
  )
  ready <- promises::then(tools, function(tools) {
    definition <- host_tool(state$source, tools, name)
    # open() with another tool may have replaced this promise.
    if (identical(state$ready, ready)) {
      settle_host_tool(state, definition)
    }
    definition
  })
  state$ready <- ready
  promises::catch(ready, function(e) {
    if (identical(state$ready, ready)) {
      state$ready <- NULL
    }
  })
  ready
}

#' Is a source apps in this R process? Their tools are listed at once.
#' @noRd
in_process_source <- function(source) {
  inherits(source, "shinymcp_host_source_in_process")
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
  title = NULL,
  owner = NULL,
  on_app_call = NULL
) {
  rlang::check_installed("promises", reason = "to host MCP Apps in Shiny.")
  registry <- ensure_shiny_host_registry(session)
  source <- register_host_source(registry, source, on_app_call)
  # Apps in this process are checked now, so a mistake is an error here. A
  # remote server's tools are listed without blocking the session, and a
  # problem shows where the app would be.
  definition <- if (in_process_source(source)) {
    host_tool(source, source$tools(), tool)
  }
  tool <- definition$name %||% tool
  interaction <- if (!is.null(tool)) {
    source$interaction(tool, trigger, debounce_ms)
  }
  config <- interaction_config(interaction)
  state <- new_mcp_host_state(
    source,
    instance_id = instance_id,
    tool = tool,
    arguments = arguments,
    result = result,
    kind = kind,
    title = title,
    config = config
  )
  # The chat host whose tool made the card.
  state$owner <- owner
  state$on_app_call <- on_app_call
  # Its page's calls are checked by its own on_app_call or, for a card, its
  # chat host's; a restored card must find a check again.
  state$checked <- length(host_app_call_hooks(registry, state)) > 0
  if (!is.null(definition)) {
    state$ready <- promises::promise_resolve(settle_host_tool(
      state,
      definition
    ))
  } else {
    host_ready(state)
  }
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

#' The part of a page's configuration a host sets: trigger and debounce
#' @noRd
interaction_config <- function(interaction) {
  if (!is.null(interaction)) {
    compact_list(list(
      trigger = interaction$trigger,
      debounceMs = interaction$debounce_ms
    ))
  }
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
    owner = state$owner,
    # The checks on a card's calls can't be saved; this marks that its
    # page's calls were checked, so a restored card refuses them until the
    # new session gives a check for its source.
    checked = if (isTRUE(state$checked) || is.function(state$on_app_call)) TRUE,
    height = height,
    trigger = trigger,
    version = as.character(utils::packageVersion("shinymcp"))
  ))
}

#' Recreate an instance from a descriptor the page sent back
#'
#' For cards restored with a saved conversation. The descriptor is trusted
#' only to name a source this session hosts and one of its tools; nothing
#' is called. An app in this process is checked now; a remote server's
#' tool is checked when the card attaches, without blocking the session.
#' @noRd
restore_host_instance <- function(registry, descriptor) {
  id <- json_field(descriptor, "instanceId")
  key <- json_field(descriptor, "source")
  tool <- json_field(descriptor, "tool")
  if (!is_string(id) || !is_string(key) || !is_string(tool)) {
    return(NULL)
  }
  source <- if (nzchar(key)) registry$sources[[key]]
  if (is.null(source) || !nzchar(id)) {
    return(NULL)
  }
  definition <- NULL
  if (in_process_source(source)) {
    definition <- tryCatch(
      host_tool(source, source$tools(), tool),
      error = function(e) NULL
    )
    if (is.null(definition)) {
      return(NULL)
    }
  }
  state <- new_mcp_host_state(
    source,
    instance_id = id,
    tool = tool,
    arguments = if (is_json_object(descriptor[["arguments"]])) {
      descriptor[["arguments"]]
    },
    result = if (is_json_object(descriptor[["result"]])) descriptor[["result"]],
    kind = "card"
  )
  state$restored <- TRUE
  state$checked <- isTRUE(descriptor[["checked"]])
  owner <- descriptor[["owner"]]
  state$owner <- if (is_string(owner)) owner
  if (!is.null(definition)) {
    state$ready <- promises::promise_resolve(settle_host_tool(
      state,
      definition
    ))
  }
  registry$instances[[id]] <- state
  state
}

#' Forget an instance, if the registry still holds it
#' @noRd
forget_host_instance <- function(registry, state) {
  id <- state$instance_id
  if (identical(host_instance(registry, id), state)) {
    rm(list = id, envir = registry$instances)
  }
  invisible()
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
  # The tool is called once it's known to be there (for a remote server, its
  # tools are listed first), unless a newer call has taken over.
  call <- promises::then(host_ready(state), function(definition) {
    if (current()) {
      state$source$call_async(
        state$tool,
        state$arguments,
        host_call_context(session)
      )
    }
  })
  promises::then(
    call,
    onFulfilled = function(call) {
      if (!current() || is.null(call)) {
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
  descriptor <- json_field(event, "descriptor") %||% list()
  instance_id <- json_field(event, "instanceId") %||%
    json_field(descriptor, "instanceId") %||%
    ""
  reply <- function(message) {
    session$sendCustomMessage(
      "shinymcp-host-attached",
      c(
        list(
          instanceId = instance_id,
          requestId = json_field(event, "requestId")
        ),
        message
      )
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
  generation <- state$page_generation

  # The tool is checked before the page is read; the tools the page may
  # call come from the same list.
  checked <- promises::then(host_ready(state), function(definition) {
    promises::then(state$source$tools_async(), function(tools) {
      list(definition = definition, tools = tools)
    })
  })
  promises::then(
    checked,
    onFulfilled = function(checked) {
      definition <- checked$definition
      app_tools <- vapply(
        Filter(function(t) tool_wire_visible_to(t, "app"), checked$tools),
        function(t) t$name,
        character(1)
      )
      promises::then(
        host_page_async(registry, state, tool_resource_uri(definition)),
        onFulfilled = function(page) {
          # open() loaded the app again while this page was read: the page
          # of the newer attach is the one shown.
          if (!identical(state$page_generation, generation)) {
            fail("The app is opening again.")
            return(invisible())
          }
          ui <- tool_ui_meta(list(`_meta` = page$meta))
          if (isTRUE(state$default_title)) {
            state$title <- html_page_title(page$html) %||% state$title
          }
          state$attached <- TRUE
          state$attached_generation <- generation
          reply(compact_list(list(
            ok = TRUE,
            title = state$title,
            page = compact_list(list(
              html = page$html,
              csp = ui[["csp"]],
              permissions = ui[["permissions"]],
              prefersBorder = ui[["prefersBorder"]]
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
      if (!inherits(e, "shinymcp_error_validation")) {
        fail(paste("Couldn't reach the app's server:", conditionMessage(e)))
      } else if (isTRUE(state$restored)) {
        # A saved card whose tool the server no longer has.
        forget_host_instance(registry, state)
        fail("This app isn't available any more.")
      } else {
        fail(conditionMessage(e))
      }
    }
  )
  invisible()
}

# ---- Requests from the page ----

#' Answer one message from a hosted app's page
#' @noRd
handle_host_event <- function(session, registry, event) {
  type <- json_field(event, "type") %||% "request"
  if (identical(type, "attach")) {
    return(host_attach(session, registry, event))
  }
  instance_id <- json_field(event, "instanceId") %||% ""
  state <- host_instance(registry, instance_id)

  if (identical(type, "notification")) {
    # Until the page a pane's open() loads has attached, notifications come
    # from the page before it (its context, a message, its size) and are
    # no longer the pane's.
    current <- !is.null(state) &&
      identical(state$attached_generation, state$page_generation)
    if (current) {
      mcp_host_notification(
        state,
        json_field(event, "method"),
        json_field(event, "params") %||% list()
      )
      host <- card_chat_host(registry, state)
      if (
        identical(json_field(event, "method"), "ui/message") &&
          identical(state$kind, "card") &&
          is.function(host$on_message)
      ) {
        host$on_message(state, json_field(event, "params") %||% list())
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

  message <- json_field(event, "message")
  id <- request_id(message)
  reply <- function(response) {
    session$sendCustomMessage(
      "shinymcp-host-response",
      list(
        instanceId = instance_id,
        requestId = json_field(event, "requestId"),
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
  # A request is the instance's own while the page that sent it is the
  # latest. Once a pane's open() loads the app again, the old page's
  # requests (one still running, or the call a live view makes to close
  # itself as its page goes) are answered, but not recorded as its calls.
  generation <- state$attached_generation
  own <- function() identical(state$page_generation, generation)
  method <- json_field(message, "method")
  params <- json_field(message, "params")
  if (!is_string(method) || !method %in% HOST_PAGE_METHODS) {
    reply(jsonrpc_error(
      id,
      RPC_METHOD_NOT_FOUND,
      paste0("The host doesn't pass on ", method %||% "that request", ".")
    ))
    return(invisible())
  }

  name <- json_field(params, "name")
  # For a tool call, the tool's definition if the page may call it, else
  # FALSE. Other requests are passed on.
  allowed <- if (identical(method, "tools/call")) {
    promises::then(state$source$tools_async(), function(tools) {
      for (tool in tools) {
        if (identical(tool$name, name)) {
          return(if (tool_wire_visible_to(tool, "app")) tool else FALSE)
        }
      }
      FALSE
    })
  } else {
    promises::promise_resolve(TRUE)
  }

  forward <- function() {
    promises::then(
      state$source$send_async(message, host_call_context(session)),
      onFulfilled = function(response) {
        # Answers that arrive after the app closed (a long poll) go
        # nowhere.
        if (isTRUE(state$disposed)) {
          return(invisible())
        }
        if (identical(method, "tools/call") && !is.null(response$result)) {
          if (own()) {
            mcp_host_record_call(
              state,
              name,
              json_field(params, "arguments"),
              response$result
            )
          } else {
            mcp_host_track_views(state, response$result)
          }
        }
        reply(response)
      },
      onRejected = function(e) {
        reply(jsonrpc_error(id, RPC_INTERNAL_ERROR, conditionMessage(e)))
      }
    )
  }

  promises::then(
    allowed,
    onFulfilled = function(tool) {
      if (isFALSE(tool)) {
        reply(jsonrpc_error(
          id,
          RPC_INVALID_PARAMS,
          paste0(
            "The app can't call the tool ",
            as.character(to_json(name %||% "")),
            "."
          )
        ))
        return(invisible())
      }
      # The host's own check of the tool calls the page makes.
      hooks <- if (identical(method, "tools/call")) {
        host_app_call_hooks(registry, state)
      }
      if (length(hooks) == 0) {
        return(forward())
      }
      call <- host_app_call(
        session,
        registry,
        state,
        name,
        json_field(params, "arguments"),
        tool
      )
      promises::then(check_app_call(hooks, call), function(verdict) {
        if (isTRUE(verdict$ok)) {
          return(forward())
        }
        # Refused: answered as the host's refusal, never sent to the
        # source, and not recorded as the instance's call.
        reply(jsonrpc_error(
          id,
          RPC_INVALID_PARAMS,
          verdict$reason %||%
            paste0(
              "The host refused the call to ",
              as.character(to_json(name)),
              "."
            )
        ))
      })
    },
    onRejected = function(e) {
      reply(jsonrpc_error(id, RPC_INTERNAL_ERROR, conditionMessage(e)))
    }
  )
  invisible()
}

# ---- Checking the page's calls ----

#' Check an `on_app_call` argument
#' @noRd
check_app_call_hook <- function(on_app_call, call = rlang::caller_env()) {
  if (!is.null(on_app_call) && !is.function(on_app_call)) {
    shinymcp_abort(
      "{.arg on_app_call} must be a function or `NULL`.",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  invisible(on_app_call)
}

#' The `on_app_call` functions a page's tool calls go through
#'
#' The one the host that made the instance gave, and, for a card, the one
#' of the chat host it belongs to. A card restored from a descriptor also
#' goes through every one the session was given for its source: the
#' descriptor comes from the browser, which could name any owner, so it
#' can't say which host made the card. A restored card that had its own
#' check, which can't be saved, is refused when no check applies.
#' @noRd
host_app_call_hooks <- function(registry, state) {
  hooks <- list(state$on_app_call)
  if (identical(state$kind, "card")) {
    hooks <- c(hooks, list(card_chat_host(registry, state)$on_app_call))
  }
  if (isTRUE(state$restored)) {
    hooks <- c(hooks, registry$app_call_hooks[[state$source$key]])
  }
  hooks <- unique_functions(Filter(is.function, hooks))
  # A card whose own check didn't survive the save refuses its page's calls
  # rather than letting them through unchecked.
  if (isTRUE(state$checked) && length(hooks) == 0) {
    hooks <- list(refuse_unchecked_restored_card)
  }
  hooks
}

refuse_unchecked_restored_card <- function(call) {
  paste(
    "This app's calls were checked when it was opened, and this session has",
    "no check for them. Pass `on_app_call` to the chat host or tool that",
    "shows it."
  )
}

#' Functions, each kept once
#' @noRd
unique_functions <- function(fns) {
  kept <- list()
  for (fn in fns) {
    if (!any(vapply(kept, identical, logical(1), fn))) {
      kept <- c(kept, list(fn))
    }
  }
  kept
}

#' What `on_app_call` is told about a call the page makes
#' @noRd
host_app_call <- function(session, registry, state, name, arguments, tool) {
  chat <- if (identical(state$kind, "card")) card_chat_key(registry, state)
  if (!is.null(chat) && !chat %in% names(registry$chat_hosts)) {
    chat <- NULL
  }
  list(
    name = name,
    arguments = arguments %||% list(),
    tool = tool,
    instance_id = state$instance_id,
    kind = state$kind,
    source = state$source$key,
    chat = chat,
    title = state$title,
    session = session
  )
}

#' Ask each `on_app_call` function in turn whether the page may make a call
#'
#' @return A promise of `list(ok = TRUE)`, or of a refusal,
#'   `list(ok = FALSE, reason = )` with the reason the function gave, if
#'   any. It never rejects: an error, a rejected promise, or anything that
#'   isn't an answer refuses the call.
#' @noRd
check_app_call <- function(hooks, call) {
  if (length(hooks) == 0) {
    return(promises::promise_resolve(list(ok = TRUE)))
  }
  verdict <- promises::then(ask_app_call_hook(hooks[[1]], call), function(v) {
    if (isTRUE(v$ok)) check_app_call(hooks[-1], call) else v
  })
  promises::catch(verdict, function(e) list(ok = FALSE))
}

#' @noRd
ask_app_call_hook <- function(hook, call) {
  value <- tryCatch(
    # A function may read reactive values; the page's calls are answered
    # outside any reactive context.
    if (requireNamespace("shiny", quietly = TRUE)) {
      shiny::isolate(hook(call))
    } else {
      hook(call)
    },
    error = function(e) e
  )
  if (inherits(value, "error")) {
    return(promises::promise_resolve(
      app_call_hook_failed(call, value, "failed")
    ))
  }
  if (promises::is.promising(value)) {
    return(promises::then(
      value,
      onFulfilled = function(value) app_call_verdict(call, value),
      onRejected = function(e) {
        app_call_hook_failed(call, e, "returned a promise that was rejected")
      }
    ))
  }
  promises::promise_resolve(app_call_verdict(call, value))
}

#' Read what `on_app_call` returned: `TRUE`, `FALSE`, or a reason
#' @noRd
app_call_verdict <- function(call, value) {
  if (isTRUE(value)) {
    return(list(ok = TRUE))
  }
  if (isFALSE(value)) {
    return(list(ok = FALSE))
  }
  if (is.character(value) && length(value) == 1 && !is.na(value)) {
    return(list(ok = FALSE, reason = if (nzchar(value)) value))
  }
  cli::cli_warn(c(
    "The app's call to {.val {call$name}} was refused.",
    "x" = "{.arg on_app_call} must return {.code TRUE}, {.code FALSE}, or a string, not {.obj_type_friendly {value}}."
  ))
  list(ok = FALSE)
}

#' A function that failed refuses the call; its author is told why
#' @noRd
app_call_hook_failed <- function(call, error, what) {
  problem <- conditionMessage(error)
  cli::cli_warn(c(
    "The app's call to {.val {call$name}} was refused.",
    "x" = "{.arg on_app_call} {what}: {problem}"
  ))
  list(ok = FALSE)
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
#' @section Checking the app's calls:
#' The app's page calls its tools as the person uses it: to fill its
#' outputs when an input changes, or when they press a button such as
#' "Save". `on_app_call` sees each of these calls before it's sent to the
#' app's server, to let it through, refuse it, or keep a record of who did
#' what. It's called with a list describing the call:
#'
#' * `name`: the tool's name.
#' * `arguments`: its arguments, as the page sent them (parsed JSON: arrays
#'   are lists).
#' * `tool`: the tool's definition from the app's server, with its
#'   `annotations`, such as `destructiveHint`.
#' * `instance_id`: the id of the pane or card.
#' * `kind`: `"pane"` or `"card"`.
#' * `source`: the name of where the app comes from: the [McpApp]'s name,
#'   or the [mcp_client()]'s `name`.
#' * `chat`: for a card, the [mcp_chat_host()] it belongs to: its
#'   `chat_id`, else `"chat-1"`, `"chat-2"`, and so on, by its place among
#'   the session's chat hosts. Otherwise `NULL`.
#' * `title`: the app's title.
#' * `session`: the Shiny session. On Posit Connect, `session$user` is the
#'   signed-in user.
#'
#' Return `TRUE` to let the call through, and `FALSE` or a string to refuse
#' it. The app's page is given the string as the call's error, so write it
#' for the person using the app. To ask someone first, return a promise
#' that resolves to one of these: the app waits for the answer, and the
#' rest of the session carries on. Anything else, an error, or a rejected
#' promise refuses the call, with a warning. A refused call never reaches
#' the app's server.
#'
#' A page can call a tool each time an input changes, so keep the function
#' quick, and ask a person only about the tools that need it.
#'
#' Only the tool calls the app's page makes are checked. Reading the app's
#' resources isn't, and neither is the call that opens the app. The
#' model's calls are the chat's to check, with ellmer's `on_tool_request()`
#' callback (see [ellmer::tool_reject()]).
#'
#' A function can't be saved with a conversation. A card restored in a new
#' session goes through the checks that session gives for the card's app,
#' through [mcp_chat_host()] or [as_shinychat_tool()]. If the card had a
#' check of its own and the new session gives none, its page's calls are
#' refused. That mark is saved in the browser with the conversation, so it
#' guards against a missing check, not against the person who edits their
#' saved conversation: to check every call, give the check to
#' [mcp_chat_host()] or [as_shinychat_tool()].
#'
#' @param id Module id.
#' @param source Where the app comes from: an [McpApp] (or a list of
#'   them), or an [McpClient] from [mcp_client()].
#' @param tool The tool that opens the app. Defaults to the first tool the
#'   model may call that shows an app. A remote server's tools are listed
#'   without holding up the session, so a tool it doesn't have is reported
#'   in the pane rather than as an error.
#' @param arguments Named list of arguments for that call, as a client
#'   would send them. A vector of one value is one value; write an array of
#'   one as `list(x)`.
#' @param trigger,debounce_ms For apps made with shinymcp in this process:
#'   override the app's own `trigger` and `debounce_ms`. `trigger =
#'   "manual"` shows a Run button and calls tools only when it's pressed or
#'   when `execute()` is called.
#' @param height `"auto"` to follow the app's size, or a CSS height.
#' @param on_app_call A function that checks each tool call the app's page
#'   makes before it's sent, to let it through, refuse it, or record it.
#'   See "Checking the app's calls" below. `NULL`, the default, lets
#'   through every call the app may make.
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
#'
#' # Record each call the app's page makes, and refuse one tool
#' server <- function(input, output, session) {
#'   mcp_host_server("explorer", app, on_app_call = function(call) {
#'     message(call$session$user, " called ", call$name)
#'     if (call$name == "delete_notes") "Notes can't be deleted here." else TRUE
#'   })
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
  height = "auto",
  on_app_call = NULL
) {
  rlang::check_installed(
    c("shiny", "promises", "later"),
    reason = "for `mcp_host_server()`."
  )
  check_app_call_hook(on_app_call)
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
      height = height,
      on_app_call = on_app_call
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
          switched <- NULL
          if (!is.null(tool)) {
            # Checked now for an app in this process, else when it opens.
            definition <- if (in_process_source(state$source)) {
              host_tool(state$source, state$source$tools(), tool)
            }
            state$tool <- tool
            # The title follows the tool, unless the host gave one.
            if (!isTRUE(state$title_given)) {
              state$title <- state$source$title
              state$default_title <- TRUE
            }
            state$ready <- if (!is.null(definition)) {
              promises::promise_resolve(settle_host_tool(state, definition))
            }
            # The tool may be another app's, with a trigger and debounce of
            # its own; the pane's settings still come first.
            switched <- state$source$interaction(tool, trigger, debounce_ms)
            state$config <- interaction_config(switched)
          }
          state$arguments <- arguments %||% json_object()
          state$result <- NULL
          state$attached <- FALSE
          state$page_generation <- state$page_generation + 1L
          send_host_command(root, state, "reopen", trigger = switched$trigger)
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
  height = "auto",
  on_app_call = NULL
) {
  rlang::check_installed(
    c("shiny", "promises", "later"),
    reason = "for `mcp_embed()`."
  )
  check_app_call_hook(on_app_call)
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
    height = height,
    on_app_call = on_app_call
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
