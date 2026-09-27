# Embedding MCP Apps in Shiny
#
# A Shiny app can host MCP Apps the way a chat client does: the app's page
# runs in a sandboxed iframe, and a small host script in the Shiny page
# speaks the MCP Apps protocol to it. Requests the page sends to its server
# (tools/call, resources/read) travel over the Shiny session to R, where an
# in-process MCP server answers them, so the app behaves exactly as it does
# in Claude or ChatGPT.

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
  if (inherits(session, c("ShinySession", "session_proxy"))) session else NULL
}

#' Host markup: a toolbar, an error area, and the iframe
#' @noRd
mcp_host_markup <- function(id, config = NULL, height = "auto", toolbar = TRUE, title = NULL) {
  root <- htmltools::tags$div(
    id = id,
    class = "shinymcp-host",
    `data-shinymcp-host` = "",
    `data-shinymcp-height` = height,
    `data-shinymcp-border` = if (isFALSE(config$prefersBorder)) "false",
    if (toolbar) {
      htmltools::tags$div(
        class = "shinymcp-host-toolbar",
        htmltools::tags$span(class = "shinymcp-host-title", title %||% config$title),
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

#' Register a live app instance with a Shiny session
#'
#' @return A list with the host `state` (an environment) and the `config`
#'   the host script reads.
#' @noRd
register_shiny_host_instance <- function(
  session,
  app,
  instance_id = unique_id("host"),
  tool = NULL,
  arguments = NULL,
  result = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto"
) {
  app <- as_mcp_app(app)
  registry <- ensure_shiny_host_registry(session)
  interaction <- resolve_host_interaction(app, trigger, debounce_ms)

  state <- new_mcp_host_state(app, instance_id)
  registry$instances[[instance_id]] <- state

  entry <- tool %||% default_entry_tool(app)
  if (!is.null(entry) && !app$has_tool(entry)) {
    shinymcp_abort(
      "App {.val {app$name}} has no tool called {.val {entry}}.",
      class = "shinymcp_error_validation"
    )
  }
  ui_meta <- app$resource_meta()$ui
  config <- compact_list(list(
    instanceId = instance_id,
    title = app$title %||% app$name,
    version = as.character(utils::packageVersion("shinymcp")),
    html = app$html_resource(config = compact_list(list(
      trigger = interaction$trigger,
      debounceMs = interaction$debounce_ms
    ))),
    csp = ui_meta$csp,
    permissions = ui_meta$permissions,
    prefersBorder = ui_meta$prefersBorder,
    height = height,
    trigger = interaction$trigger,
    entryTool = entry,
    tool = if (!is.null(entry)) tool_definition_for(app, entry),
    appTools = I(names(app$tools("app"))),
    initialArguments = arguments %||% json_object(),
    initialResult = result
  ))
  list(state = state, config = config)
}

#' The wire definition of one of an app's tools
#' @noRd
tool_definition_for <- function(app, name) {
  for (def in app$tool_definitions()) {
    if (identical(def$name, name)) {
      return(def)
    }
  }
  NULL
}

#' @noRd
default_entry_tool <- function(app) {
  tools <- app$tools("model")
  if (length(tools)) tools[[1]]$name
}

#' @noRd
resolve_host_interaction <- function(app, trigger = NULL, debounce_ms = NULL) {
  defaults <- app$interaction_defaults()
  trigger <- if (is.null(trigger)) {
    defaults$trigger %||% "debounce"
  } else {
    rlang::arg_match0(trigger, c("debounce", "change", "submit", "manual"))
  }
  list(trigger = trigger, debounce_ms = debounce_ms %||% defaults$debounce_ms %||% 250)
}

#' The per-session registry of hosted apps, and the observer that serves them
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

  registry <- new.env(parent = emptyenv())
  registry$instances <- new.env(parent = emptyenv())

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

#' Answer one message from a hosted app
#'
#' Requests run in a later() callback, outside Shiny's reactive flush: apps
#' served from Shiny run their own reactive sessions, which can't flush in
#' the middle of another flush.
#' @noRd
handle_host_event <- function(session, registry, event) {
  instance_id <- event$instanceId %||% ""
  state <- registry$instances[[instance_id]]
  type <- event$type %||% "request"

  if (identical(type, "notification")) {
    if (!is.null(state)) {
      mcp_host_notification(state, event$method, event$params %||% list())
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
  reply <- function(response) {
    session$sendCustomMessage(
      "shinymcp-host-response",
      list(instanceId = instance_id, requestId = event$requestId, response = strip_http_status(response))
    )
  }
  if (is.null(state)) {
    reply(jsonrpc_error(message$id %||% NULL, RPC_INVALID_REQUEST, "This app is no longer running."))
    return(invisible())
  }

  user <- tryCatch(session$user, error = function(e) NULL)
  groups <- tryCatch(session$groups, error = function(e) NULL)
  later::later(function() {
    response <- tryCatch(
      state$server$handle(
        message,
        list(transport = "in-process", session = state$session, user = user, groups = groups)
      ),
      error = function(e) {
        jsonrpc_error(message$id %||% NULL, RPC_INTERNAL_ERROR, conditionMessage(e))
      }
    )
    if (identical(message$method, "tools/call") && !is.null(response$result)) {
      mcp_host_record_call(state, message$params$name, message$params$arguments, response$result)
    }
    reply(response)
  })
  invisible()
}

#' Host shell for an MCP App in a Shiny app
#'
#' @description
#' `mcp_host_ui()` and `mcp_host_server()` show an [McpApp] inside a Shiny
#' app, exactly as a chat client would: the app runs in a sandboxed iframe
#' and its tool calls are answered in R. Use it to review an app, to build a
#' dashboard around one, or to react in Shiny to what the user does in it.
#'
#' `mcp_embed()` does both halves at once for UI created on the server, such
#' as inside [shiny::renderUI()].
#'
#' When the app opens, the host calls its first tool (or `tool`) with
#' `arguments`, as if the model had, and passes the result to the app.
#'
#' @param id Module id.
#' @param app An [McpApp], or anything [as_mcp_app()] accepts.
#' @param tool The tool to call when the app opens. Defaults to the app's
#'   first tool the model can call.
#' @param arguments Named list of arguments for that call.
#' @param trigger,debounce_ms Override the app's own `trigger` and
#'   `debounce_ms`. `trigger = "manual"` shows a Run button and calls tools
#'   only when it's pressed or when `execute()` is called.
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
#'   * `execute(arguments = NULL)`: call the app's tools now, optionally
#'     with new input values.
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
#' }
mcp_host_ui <- function(id, height = "auto") {
  rlang::check_installed("shiny", reason = "for `mcp_host_ui()`.")
  mcp_host_markup(shiny::NS(id)("host"), height = height)
}

#' @rdname mcp_host_ui
#' @export
mcp_host_server <- function(
  id,
  app,
  tool = NULL,
  arguments = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto"
) {
  rlang::check_installed("shiny", reason = "for `mcp_host_server()`.")
  shiny::moduleServer(id, function(input, output, session) {
    app <- as_mcp_app(app)
    registered <- register_shiny_host_instance(
      session = session,
      app = app,
      instance_id = unique_id(paste0("host-", sanitize_name(app$name))),
      tool = tool,
      arguments = arguments,
      trigger = trigger,
      debounce_ms = debounce_ms,
      height = height
    )
    state <- registered$state
    reactive_state <- host_reactives(state)

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
        execute = function(arguments = NULL) {
          session$sendCustomMessage(
            "shinymcp-host-command",
            compact_list(list(instanceId = state$instance_id, command = "execute", arguments = arguments))
          )
        },
        reset = function() {
          session$sendCustomMessage(
            "shinymcp-host-command",
            list(instanceId = state$instance_id, command = "reset")
          )
        },
        dispose = function() {
          session$sendCustomMessage(
            "shinymcp-host-command",
            list(instanceId = state$instance_id, command = "dispose")
          )
          mcp_host_dispose(state)
        }
      )
    )
  })
}

#' @rdname mcp_host_ui
#' @export
mcp_embed <- function(
  app,
  id = NULL,
  tool = NULL,
  arguments = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto"
) {
  rlang::check_installed("shiny", reason = "for `mcp_embed()`.")
  app <- as_mcp_app(app)
  session <- active_shiny_session()
  if (is.null(session)) {
    if (is.null(id)) {
      shinymcp_abort(
        "Call {.fn mcp_embed} inside a running Shiny session, or use {.fn mcp_host_ui} and {.fn mcp_host_server}."
      )
    }
    return(mcp_host_ui(id, height = height))
  }
  registered <- register_shiny_host_instance(
    session = session,
    app = app,
    instance_id = unique_id(paste0("host-", sanitize_name(app$name))),
    tool = tool,
    arguments = arguments,
    trigger = trigger,
    debounce_ms = debounce_ms,
    height = height
  )
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
  state$on_message <- function(value) messages(c(shiny::isolate(messages()), list(value)))
  list(
    model_context = shiny::reactive(model_context()),
    last_tool_call = shiny::reactive(last_tool_call()),
    last_result = shiny::reactive(last_tool_call()$result),
    messages = shiny::reactive(messages())
  )
}
