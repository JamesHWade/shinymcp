# State shared by shinymcp's hosts (Shiny embedding, shinychat cards).

#' State for one hosted app instance
#' @noRd
new_mcp_host_state <- function(app, instance_id = unique_id("host")) {
  state <- new.env(parent = emptyenv())
  state$app <- as_mcp_app(app)
  state$server <- McpServer$new(state$app)
  # The embedded page is a UI-capable client that never sends initialize.
  state$session <- new_mcp_session()
  state$instance_id <- instance_id
  state$model_context <- NULL
  state$last_tool_call <- NULL
  state$last_size <- NULL
  state$messages <- list()
  state$disposed <- FALSE
  state$on_model_context <- NULL
  state$on_tool_call <- NULL
  state$on_message <- NULL
  state$on_size <- NULL
  state
}

#' @noRd
mcp_host_callback <- function(state, name, value) {
  callback <- state[[name]]
  if (is.function(callback)) {
    tryCatch(
      callback(value),
      error = function(e) {
        cli::cli_warn(
          "Host callback {.field {name}} failed: {conditionMessage(e)}"
        )
      }
    )
  }
  invisible(value)
}

#' Record a tool call made by a hosted app
#' @noRd
mcp_host_record_call <- function(state, name, arguments, result) {
  view <- result[["_meta"]][["shinymcp/view"]]$instance
  if (is_string(view)) {
    state$views <- unique(c(state$views, view))
  }
  call <- list(name = name, arguments = arguments %||% list(), result = result)
  state$last_tool_call <- call
  mcp_host_callback(state, "on_tool_call", call)
  invisible(state)
}

#' Handle a notification or event from a hosted app
#' @noRd
mcp_host_notification <- function(state, method, params) {
  switch(
    method %||% "",
    "ui/update-model-context" = {
      state$model_context <- params
      mcp_host_callback(state, "on_model_context", params)
    },
    "ui/message" = {
      state$messages <- c(state$messages, list(params))
      mcp_host_callback(state, "on_message", params)
    },
    "ui/notifications/size-changed" = {
      state$last_size <- compact_list(list(
        width = params$width,
        height = params$height
      ))
      mcp_host_callback(state, "on_size", state$last_size)
    },
    "ui/resource-teardown" = mcp_host_dispose(state),
    NULL
  )
  invisible(state)
}

#' @noRd
mcp_host_dispose <- function(state) {
  if (!isTRUE(state$disposed)) {
    state$disposed <- TRUE
    runtime <- state$app$runtime()
    # Views opened by this host die with it.
    if (!is.null(runtime) && !is.null(state$views)) {
      for (id in state$views) {
        try(runtime$view(list(action = "close", instance = id)), silent = TRUE)
      }
    }
  }
  invisible(state)
}
