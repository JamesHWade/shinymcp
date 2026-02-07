# Top-level Shiny-to-MCP conversion orchestrator

#' Convert a Shiny app to an MCP App
#'
#' Parses a Shiny app, analyzes its reactive graph, and generates
#' an MCP App with tools and UI.
#'
#' @param path Path to a Shiny app directory
#' @param output_dir Output directory for the generated MCP App.
#'   Defaults to `{path}_mcp/`.
#' @return An [McpApp] object (invisibly). Generated files are also
#'   written to `output_dir`.
#' @export
convert_app <- function(path, output_dir = NULL) {
  if (!is.character(path) || length(path) != 1) {
    rlang::abort(
      cli::format_inline("{.arg path} must be a single character string."),
      class = "shinymcp_error_validation"
    )
  }
  if (!dir.exists(path)) {
    shinymcp_error_parse("Directory does not exist", path = path)
  }

  if (is.null(output_dir)) {
    output_dir <- paste0(normalizePath(path), "_mcp")
  }

  cli::cli_h1("Converting Shiny app to MCP App")
  cli::cli_text("Source: {.path {path}}")
  cli::cli_text("Output: {.path {output_dir}}")

  # Parse
  cli::cli_h2("Parsing")
  ir <- parse_shiny_app(path)
  cli::cli_alert_info(
    "Found {length(ir$inputs)} input(s) and {length(ir$outputs)} output(s)"
  )
  cli::cli_alert_info("Complexity: {ir$complexity}")

  # Analyze
  cli::cli_h2("Analyzing")
  analysis <- analyze_reactive_graph(ir)
  cli::cli_alert_info("Identified {length(analysis$tool_groups)} tool group(s)")

  if (length(analysis$warnings) > 0) {
    for (w in analysis$warnings) {
      cli::cli_alert_warning(w)
    }
  }

  # Generate
  cli::cli_h2("Generating")
  generate_mcp_app(analysis, ir, output_dir)

  # Build McpApp from generated files
  app_file <- file.path(output_dir, "app.R")
  ui_file <- file.path(output_dir, "ui.html")

  # Read generated UI as HTML content and wrap in an McpApp
  ui_html <- paste(readLines(ui_file, warn = FALSE), collapse = "\n")
  ui <- htmltools::tags$div(htmltools::HTML(ui_html))

  # Source tools if available
  tools_file <- file.path(output_dir, "tools.R")
  tools <- list()
  if (file.exists(tools_file)) {
    tools_env <- new.env(parent = baseenv())
    tryCatch(
      {
        source(tools_file, local = tools_env)
        if (exists("tools", envir = tools_env)) {
          tools <- get("tools", envir = tools_env)
        }
      },
      error = function(e) {
        cli::cli_warn("Could not source tools.R: {e$message}")
      }
    )
  }

  app <- McpApp$new(
    ui = ui,
    tools = tools,
    name = basename(normalizePath(path))
  )

  cli::cli_alert_success("Conversion complete!")

  if (ir$complexity == "complex") {
    cli::cli_alert_warning(
      "This app has complex patterns. Review {.path CONVERSION_NOTES.md}."
    )
  }

  invisible(app)
}
