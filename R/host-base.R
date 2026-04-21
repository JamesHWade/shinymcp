# Shared host helpers for preview, Shiny embedding, and chat adapters.

#' Create host state for a live McpApp instance
#'
#' @param app An McpApp object.
#' @param instance_id Unique live instance identifier.
#' @param initial_arguments Optional named list of initial tool arguments.
#' @param trigger Trigger mode for the bridge.
#' @param debounce_ms Debounce interval in milliseconds.
#' @param height Preferred host height.
#' @param debug Whether to enable verbose debugging features.
#' @return A mutable environment.
#' @noRd
new_mcp_host_state <- function(
  app,
  instance_id = unique_id(paste0("mcp-", app$name)),
  initial_arguments = NULL,
  trigger = "debounce",
  debounce_ms = 250,
  height = "auto",
  debug = FALSE
) {
  state <- new.env(parent = emptyenv())
  state$app <- as_mcp_app(app)
  state$instance_id <- instance_id
  state$initial_arguments <- initial_arguments
  state$trigger <- trigger
  state$debounce_ms <- debounce_ms
  state$height <- height
  state$debug <- debug
  state$model_context <- NULL
  state$last_size <- NULL
  state$disposed <- FALSE
  state
}

#' Build bridge config for a live host state
#'
#' @param state A host state environment.
#' @return A named list.
#' @noRd
mcp_host_bridge_config <- function(state) {
  compact_list(list(
    instanceId = state$instance_id,
    trigger = state$trigger,
    debounceMs = state$debounce_ms
  ))
}

#' Initialize a host connection for a live app instance
#'
#' @param state A host state environment.
#' @return A list suitable for the MCP Apps `ui/initialize` response.
#' @noRd
mcp_host_initialize <- function(state) {
  compact_list(list(
    protocolVersion = SHINYMCP_PROTOCOL_VERSION,
    hostInfo = list(
      name = "shinymcp-host",
      version = as.character(utils::packageVersion("shinymcp"))
    ),
    hostCapabilities = list(),
    hostContext = compact_list(list(
      instanceId = state$instance_id,
      initialArguments = state$initial_arguments
    ))
  ))
}

#' Call a tool through a host state
#'
#' @param state A host state environment.
#' @param tool_name Tool name.
#' @param arguments Named list of arguments.
#' @return A formatted MCP tool result.
#' @noRd
mcp_host_call_tool <- function(state, tool_name, arguments = list()) {
  format_tool_result(state$app$call_tool(tool_name, arguments))
}

#' Read a resource through a host state
#'
#' @param state A host state environment.
#' @param uri Resource URI.
#' @return The resource payload.
#' @noRd
mcp_host_read_resource <- function(state, uri) {
  if (!identical(uri, state$app$resource_uri())) {
    shinymcp_error_resource("Unknown resource URI", uri = uri)
  }
  state$app$html_resource(bridge_config = mcp_host_bridge_config(state))
}

#' Update the most recent model context seen by a host instance
#'
#' @param state A host state environment.
#' @param context Structured context object from the bridge.
#' @return Invisibly, `state`.
#' @noRd
mcp_host_update_model_context <- function(state, context) {
  state$model_context <- context
  invisible(state)
}

#' Record the most recent rendered size for a host instance
#'
#' @param state A host state environment.
#' @param width Reported width.
#' @param height Reported height.
#' @return Invisibly, `state`.
#' @noRd
mcp_host_notify_size <- function(state, width = NULL, height = NULL) {
  state$last_size <- compact_list(list(width = width, height = height))
  invisible(state)
}

#' Dispose a host instance
#'
#' @param state A host state environment.
#' @return Invisibly, `state`.
#' @noRd
mcp_host_dispose <- function(state) {
  state$disposed <- TRUE
  invisible(state)
}
