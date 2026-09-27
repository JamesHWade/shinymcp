# Output placeholders: elements the bridge draws tool results into

#' Output placeholders for tool results
#'
#' @description
#' These make the elements a tool's results are drawn into, for apps built
#' with [mcp_app()]. Each is matched to a tool result by `id`: a tool that
#' returns `list(summary = ..., plot = ...)` fills `mcp_text("summary")` and
#' `mcp_plot("plot")`.
#'
#' * `mcp_text()` shows text in a monospaced block, as R prints it.
#' * `mcp_plot()` shows an image, usually from [mcp_result_plot()].
#' * `mcp_table()` shows a data frame as an HTML table.
#' * `mcp_html()` shows HTML: tags, [mcp_result_html()], or an htmlwidget.
#'
#' Shiny's own output functions ([shiny::textOutput()],
#' [shiny::plotOutput()], and the rest) work too; their ids are matched the
#' same way.
#'
#' @param id Output id, matching a name in the tool's result.
#' @param width,height CSS size of the plot area. With `height = NULL` the
#'   plot keeps its own aspect ratio; with a height, it's scaled to fit.
#' @return An htmltools tag.
#' @family components
#' @export
#' @examples
#' htmltools::tagList(
#'   mcp_text("summary"),
#'   mcp_plot("histogram"),
#'   mcp_table("rows")
#' )
mcp_plot <- function(id, width = "100%", height = NULL) {
  htmltools::tags$div(
    id = id,
    class = if (is.null(height)) "shinymcp-output shinymcp-plot" else "shinymcp-output shinymcp-plot shinymcp-plot-fixed",
    `data-shinymcp-output` = id,
    `data-shinymcp-output-type` = "plot",
    style = htmltools::css(width = width, height = height)
  )
}

#' @rdname mcp_plot
#' @export
mcp_text <- function(id) {
  htmltools::tags$pre(
    id = id,
    class = "shinymcp-output shinymcp-text",
    `data-shinymcp-output` = id,
    `data-shinymcp-output-type` = "text"
  )
}

#' @rdname mcp_plot
#' @export
mcp_table <- function(id) {
  htmltools::tags$div(
    id = id,
    class = "shinymcp-output",
    `data-shinymcp-output` = id,
    `data-shinymcp-output-type` = "table"
  )
}

#' @rdname mcp_plot
#' @export
mcp_html <- function(id) {
  htmltools::tags$div(
    id = id,
    class = "shinymcp-output",
    `data-shinymcp-output` = id,
    `data-shinymcp-output-type` = "html"
  )
}
