# MCP-compatible output placeholder components
#
# These functions generate placeholder divs with data-shinymcp-* attributes
# that the JS bridge populates with server-rendered content.

#' Create an MCP plot output
#'
#' Generates a placeholder div for plot output with MCP data attributes.
#'
#' @param id Output ID
#' @param width CSS width (default "100%")
#' @param height CSS height (default "400px")
#' @return An [htmltools::tag] object
#' @export
mcp_plot <- function(id, width = "100%", height = "400px") {
  htmltools::tags$div(
    id = id,
    class = "shinymcp-output",
    `data-shinymcp-output` = id,
    `data-shinymcp-output-type` = "plot",
    style = paste0("width: ", width, "; height: ", height, ";")
  )
}

#' Create an MCP text output
#'
#' Generates a placeholder element for text output with MCP data attributes.
#' Uses a `<pre>` tag so R console/summary output renders with monospace
#' font and preserved whitespace.
#'
#' @param id Output ID
#' @return An [htmltools::tag] object
#' @export
mcp_text <- function(id) {
  htmltools::tags$pre(
    id = id,
    class = "shinymcp-output",
    `data-shinymcp-output` = id,
    `data-shinymcp-output-type` = "text",
    style = "white-space: pre; overflow-x: auto; margin: 0; font-size: 0.85em;"
  )
}

#' Create an MCP table output
#'
#' Generates a placeholder div for table output with MCP data attributes.
#'
#' @param id Output ID
#' @return An [htmltools::tag] object
#' @export
mcp_table <- function(id) {
  htmltools::tags$div(
    id = id,
    class = "shinymcp-output",
    `data-shinymcp-output` = id,
    `data-shinymcp-output-type` = "table"
  )
}

#' Create an MCP HTML output
#'
#' Generates a placeholder div for raw HTML output with MCP data attributes.
#'
#' @param id Output ID
#' @return An [htmltools::tag] object
#' @export
mcp_html <- function(id) {
  htmltools::tags$div(
    id = id,
    class = "shinymcp-output",
    `data-shinymcp-output` = id,
    `data-shinymcp-output-type` = "html"
  )
}
