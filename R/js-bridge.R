# Internal: generate bridge configuration
#
# Creates the config object that gets embedded in the HTML page
# for the JavaScript bridge to read on initialization.
#
# @param tools A list of tool definitions (or tool names as character vector).
# @param app_name Character string naming the MCP app.
# @return A list with `appName`, `tools`, and `version`.
# @noRd
bridge_config <- function(
  tools = list(),
  app_name = "shinymcp-app",
  tool_args = NULL
) {
  tool_names <- if (is.character(tools)) {
    tools
  } else {
    vapply(
      tools,
      function(t) {
        if (is.character(t)) t else t$name %||% "unknown"
      },
      character(1)
    )
  }

  config <- list(
    appName = app_name,
    tools = as.list(tool_names),
    version = as.character(utils::packageVersion("shinymcp"))
  )

  if (!is.null(tool_args)) {
    config$toolArgs <- tool_args
  }

  config
}

#' Bridge script tag
#'
#' Returns an [htmltools::tags] `<script>` element that inlines the shinymcp
#' JavaScript bridge. Include this in your HTML page to enable the MCP Apps
#' postMessage/JSON-RPC protocol.
#'
#' @return An `htmltools::tags$script` HTML tag.
#' @export
bridge_script_tag <- function() {
  js_path <- system.file("js", "shinymcp-bridge.js", package = "shinymcp")
  if (!nzchar(js_path)) {
    cli::cli_abort("Cannot find {.file shinymcp-bridge.js} in package.")
  }
  js_content <- paste(readLines(js_path, warn = FALSE), collapse = "\n")
  htmltools::tags$script(htmltools::HTML(js_content))
}

#' Bridge config tag
#'
#' Returns an [htmltools::tags] `<script>` element containing the JSON
#' configuration for the shinymcp bridge. The element has
#' `id="shinymcp-config"` and `type="application/json"` so the bridge
#' JavaScript can read it on initialization.
#'
#' @param config A list as returned by `bridge_config()`, or any named list
#'   that should be serialized as the bridge configuration.
#' @return An `htmltools::tags$script` HTML tag.
#' @export
bridge_config_tag <- function(config) {
  json <- to_json(config)
  htmltools::tags$script(
    id = "shinymcp-config",
    type = "application/json",
    htmltools::HTML(json)
  )
}

# Internal: inject bridge into HTML content
#
# Takes an HTML content string and injects the bridge script and config
# tags just before `</body>`. If no `</body>` tag is found the tags are
# appended at the end.
#
# @param html_content Character string of HTML content.
# @param config A list as returned by `bridge_config()`.
# @return Modified HTML string with bridge injected.
# @noRd
inject_bridge <- function(html_content, config) {
  config_tag <- bridge_config_tag(config)
  script_tag <- bridge_script_tag()

  config_html <- as.character(config_tag)
  script_html <- as.character(script_tag)

  inject <- paste0("\n", config_html, "\n", script_html, "\n")

  if (grepl("</body>", html_content, ignore.case = TRUE)) {
    sub(
      "</body>",
      paste0(inject, "</body>"),
      html_content,
      ignore.case = TRUE
    )
  } else {
    paste0(html_content, inject)
  }
}
