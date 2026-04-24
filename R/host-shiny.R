# Shiny host integration for live embedded McpApp instances.

#' @noRd
shinymcp_host_dependency <- function() {
  htmltools::htmlDependency(
    name = "shinymcp-host",
    version = as.character(utils::packageVersion("shinymcp")),
    src = system_file("js"),
    script = "shinymcp-host.js",
    stylesheet = "shinymcp-host.css"
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
active_shiny_session <- function() {
  session <- tryCatch(
    shiny::getDefaultReactiveDomain(),
    error = function(...) NULL
  )
  if (inherits(session, "ShinySession")) session else NULL
}

#' @noRd
mcp_host_markup <- function(id, config = NULL, height = "auto") {
  toolbar <- htmltools::tags$div(
    class = "shinymcp-host-toolbar",
    `data-shinymcp-host-toolbar` = "",
    htmltools::tags$div(
      class = "shinymcp-host-status",
      `data-shinymcp-host-status` = "",
      "connecting..."
    ),
    htmltools::tags$div(
      class = "shinymcp-host-actions",
      htmltools::tags$button(
        type = "button",
        class = "shinymcp-host-button",
        `data-shinymcp-action` = "execute",
        "Apply"
      ),
      htmltools::tags$button(
        type = "button",
        class = "shinymcp-host-button shinymcp-host-button-secondary",
        `data-shinymcp-action` = "reset",
        "Reset"
      )
    )
  )

  root <- htmltools::tags$div(
    id = id,
    class = "shinymcp-host",
    `data-shinymcp-host` = "",
    `data-shinymcp-height` = height,
    toolbar,
    htmltools::tags$div(
      class = "shinymcp-host-error",
      `data-shinymcp-host-error` = ""
    ),
    htmltools::tags$iframe(
      class = "shinymcp-host-frame",
      `data-shinymcp-host-frame` = "",
      sandbox = "allow-scripts allow-same-origin",
      loading = "lazy",
      title = "shinymcp embedded app"
    ),
    if (!is.null(config)) {
      htmltools::tags$script(
        type = "application/json",
        class = "shinymcp-host-config",
        htmltools::HTML(to_json(config))
      )
    }
  )

  htmltools::attachDependencies(root, shinymcp_host_dependency())
}

#' @noRd
register_shiny_host_instance <- function(
  session,
  app,
  instance_id = unique_id("shinymcp-instance"),
  trigger = "debounce",
  debounce_ms = 250,
  height = "auto",
  initial_arguments = NULL,
  debug = FALSE
) {
  registry <- ensure_shiny_host_registry(session)
  state <- new_mcp_host_state(
    app = app,
    instance_id = instance_id,
    initial_arguments = initial_arguments,
    trigger = trigger,
    debounce_ms = debounce_ms,
    height = height,
    debug = debug
  )
  registry$instances[[instance_id]] <- state

  list(
    state = state,
    config = compact_list(list(
      instanceId = instance_id,
      trigger = trigger,
      debounceMs = debounce_ms,
      height = height,
      debug = debug,
      appHtml = state$app$html_resource(
        bridge_config = mcp_host_bridge_config(state)
      )
    ))
  )
}

#' @noRd
ensure_shiny_host_registry <- function(session = active_shiny_session()) {
  if (!inherits(session, "ShinySession")) {
    cli::cli_abort("An active Shiny session is required for live host state.")
  }

  registry <- session$userData$shinymcp_host_registry
  if (!is.null(registry)) {
    return(registry)
  }

  registry <- new.env(parent = emptyenv())
  registry$instances <- new.env(parent = emptyenv())

  registry$observer <- shiny::observeEvent(
    session$input$shinymcp_host_event,
    {
      event <- session$input$shinymcp_host_event
      instance_id <- event$instanceId %||% ""

      state <- registry$instances[[instance_id]]
      if (is.null(state)) {
        if (identical(event$method, "tools/call")) {
          session$sendCustomMessage(
            "shinymcp-host-response",
            list(
              instanceId = instance_id,
              requestId = event$requestId,
              result = list(
                content = list(
                  list(
                    type = "text",
                    text = paste(
                      "Error: no active shinymcp host instance found for",
                      instance_id
                    )
                  )
                ),
                isError = TRUE
              )
            )
          )
        }
        return()
      }

      method <- event$method %||% ""
      params <- event$params %||% list()

      if (identical(method, "tools/call")) {
        tool_name <- params$name
        arguments <- params$arguments %||% list()

        result <- tryCatch(
          mcp_host_call_tool(state, tool_name, arguments),
          error = function(e) {
            list(
              content = list(
                list(type = "text", text = paste("Error:", e$message))
              ),
              isError = TRUE
            )
          }
        )

        session$sendCustomMessage(
          "shinymcp-host-response",
          list(
            instanceId = instance_id,
            requestId = event$requestId,
            result = result
          )
        )
        return()
      }

      if (identical(method, "ui/update-model-context")) {
        mcp_host_update_model_context(
          state,
          params$structuredContent %||% params
        )
        return()
      }

      if (identical(method, "ui/notifications/size-changed")) {
        mcp_host_notify_size(
          state,
          width = params$width,
          height = params$height
        )
        return()
      }

      if (identical(method, "ui/resource-teardown")) {
        mcp_host_dispose(state)
        rm(list = instance_id, envir = registry$instances)
      }
    },
    ignoreNULL = TRUE
  )

  session$onSessionEnded(function() {
    ids <- ls(registry$instances)
    for (instance_id in ids) {
      mcp_host_dispose(registry$instances[[instance_id]])
    }
  })

  session$userData$shinymcp_host_registry <- registry
  registry
}

#' Host shell UI for an embedded MCP app
#'
#' Use `mcp_host_server()` on the server side to attach a live [McpApp]
#' instance to this UI shell.
#'
#' @param id Shiny module id.
#' @export
mcp_host_ui <- function(id) {
  ns <- shiny::NS(id)
  mcp_host_markup(ns("host"))
}

#' Host shell server for an embedded MCP app
#'
#' @param id Shiny module id.
#' @param app An [McpApp] object.
#' @param trigger Interaction mode: `"change"`, `"debounce"`, `"submit"`, or
#'   `"manual"`.
#' @param debounce_ms Debounce interval in milliseconds.
#' @param height Preferred initial height for the host shell.
#' @param initial_arguments Optional named list of initial tool arguments.
#' @param debug Whether to enable debug affordances in the host shell.
#' @return A small control API with `instance_id`, `execute()`, `reset()`,
#'   `dispose()`, and read-only reactives for `model_context`, `last_result`,
#'   `last_raw_result`, `last_tool_call`, and `last_size`.
#' @export
mcp_host_server <- function(
  id,
  app,
  trigger = c("debounce", "change", "submit", "manual"),
  debounce_ms = 250,
  height = "auto",
  initial_arguments = NULL,
  debug = FALSE
) {
  trigger <- match.arg(trigger)

  shiny::moduleServer(id, function(input, output, session) {
    app <- as_mcp_app(app)
    registered <- register_shiny_host_instance(
      session = session,
      app = app,
      instance_id = unique_id(paste0("mcp-", app$name)),
      trigger = trigger,
      debounce_ms = debounce_ms,
      height = height,
      initial_arguments = initial_arguments,
      debug = debug
    )

    model_context <- shiny::reactiveVal(registered$state$model_context)
    last_result <- shiny::reactiveVal(registered$state$last_result)
    last_raw_result <- shiny::reactiveVal(registered$state$last_raw_result)
    last_tool_call <- shiny::reactiveVal(registered$state$last_tool_call)
    last_size <- shiny::reactiveVal(registered$state$last_size)

    registered$state$on_model_context <- function(value, state) {
      model_context(value)
    }
    registered$state$on_tool_call <- function(value, state) {
      last_tool_call(value)
      last_raw_result(value$raw_result)
      last_result(value$result)
    }
    registered$state$on_size <- function(value, state) {
      last_size(value)
    }

    session$onFlushed(
      function() {
        session$sendCustomMessage(
          "shinymcp-host-init",
          list(id = session$ns("host"), config = registered$config)
        )
      },
      once = TRUE
    )

    list(
      instance_id = shiny::reactive(registered$state$instance_id),
      model_context = shiny::reactive(model_context()),
      last_result = shiny::reactive(last_result()),
      last_raw_result = shiny::reactive(last_raw_result()),
      last_tool_call = shiny::reactive(last_tool_call()),
      last_size = shiny::reactive(last_size()),
      execute = function(arguments = NULL) {
        session$sendCustomMessage(
          "shinymcp-host-command",
          compact_list(list(
            instanceId = registered$state$instance_id,
            command = "execute",
            arguments = arguments
          ))
        )
      },
      reset = function() {
        session$sendCustomMessage(
          "shinymcp-host-command",
          list(
            instanceId = registered$state$instance_id,
            command = "reset"
          )
        )
      },
      dispose = function() {
        session$sendCustomMessage(
          "shinymcp-host-command",
          list(
            instanceId = registered$state$instance_id,
            command = "dispose"
          )
        )
        mcp_host_dispose(registered$state)
      }
    )
  })
}

#' Embed an MCP app inside a live Shiny session
#'
#' When called inside a Shiny server context, this helper auto-registers a live
#' host instance and returns ready-to-render UI. Outside a live session, provide
#' an `id` and pair the result with `mcp_host_server()`.
#'
#' @param app An [McpApp] object.
#' @param id Optional DOM or module id.
#' @param trigger Interaction mode: `"debounce"`, `"change"`, `"submit"`, or
#'   `"manual"`.
#' @param debounce_ms Debounce interval in milliseconds.
#' @param height Preferred initial height.
#' @export
mcp_embed <- function(
  app,
  id = NULL,
  trigger = c("debounce", "change", "submit", "manual"),
  debounce_ms = 250,
  height = "auto"
) {
  trigger <- match.arg(trigger)
  app <- as_mcp_app(app)
  session <- active_shiny_session()

  if (!is.null(session)) {
    dom_id <- sanitize_dom_id(id %||% unique_id(paste0("mcp-host-", app$name)))
    registered <- register_shiny_host_instance(
      session = session,
      app = app,
      instance_id = unique_id(paste0("mcp-", app$name)),
      trigger = trigger,
      debounce_ms = debounce_ms,
      height = height
    )
    return(mcp_host_markup(dom_id, config = registered$config, height = height))
  }

  if (is.null(id)) {
    cli::cli_abort(
      "Provide {.arg id} when calling {.fn mcp_embed} outside a live Shiny session, or use {.fn mcp_host_ui} / {.fn mcp_host_server}."
    )
  }

  mcp_host_ui(id)
}
