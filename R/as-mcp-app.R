# as_mcp_app() — convert various objects to McpApp
#
# S3 generic that converts Shiny app objects, modules, or other
# representations into McpApp instances for serving over MCP.

#' Convert an object to an MCP App
#'
#' S3 generic that converts various Shiny-related objects into an [McpApp].
#' The primary method converts `shiny.appobj` (from [shiny::shinyApp()]) by
#' parsing its UI and server to build tool definitions automatically.
#'
#' @param x An object to convert. Currently supports:
#'   - `shiny.appobj` (from [shiny::shinyApp()])
#'   - `McpApp` (returned as-is)
#' @param ... Additional arguments passed to methods.
#' @return An [McpApp] object.
#'
#' @examples
#' \dontrun{
#' library(shiny)
#'
#' ui <- fluidPage(
#'   selectInput("dataset", "Choose", c("mtcars", "iris")) |> bindMcp(),
#'   plotOutput("plot") |> bindMcp(),
#'   textOutput("summary") |> bindMcp()
#' )
#'
#' server <- function(input, output, session) {
#'   output$plot <- renderPlot(plot(get(input$dataset)))
#'   output$summary <- renderText(paste("Rows:", nrow(get(input$dataset))))
#' }
#'
#' # Convert and serve
#' shinyApp(ui, server) |> as_mcp_app(name = "explorer") |> serve()
#' }
#'
#' @export
as_mcp_app <- function(x, ...) {
  UseMethod("as_mcp_app")
}

#' @rdname as_mcp_app
#' @param name App name (used in resource URIs). Defaults to `"shinymcp-app"`.
#' @param tools Optional list of explicit [ellmer::tool()] definitions. If
#'   provided, these are used instead of auto-generating tools from the
#'   reactive graph.
#' @param selective Logical. If `TRUE` (default when `bindMcp()` annotations
#'   are present), only annotated elements are exposed. If `FALSE`, all
#'   detected inputs/outputs are exposed.
#' @param version App version string. Defaults to `"0.1.0"`.
#' @export
as_mcp_app.shiny.appobj <- function(x, name = NULL, tools = NULL,
                                    selective = NULL, version = "0.1.0",
                                    ...) {
  rlang::check_installed("shiny", reason = "for converting Shiny apps")

  # Extract UI from the shinyApp object
  ui <- extract_shiny_ui(x)
  server_fn <- extract_shiny_server(x)

  # If explicit tools are provided, use them directly
  if (!is.null(tools)) {
    return(mcp_app(ui = ui, tools = tools, name = name %||% "shinymcp-app",
                   version = version))
  }

  # Determine selective mode: auto-detect if any bindMcp() annotations exist
  if (is.null(selective)) {
    selective <- has_any_mcp_annotations(ui)
  }

  # Parse UI tags + server body into IR
  server_body <- if (!is.null(server_fn)) body(server_fn) else NULL
  ir <- parse_shiny_app_object(ui, server_body, selective = selective)

  if (length(ir$inputs) == 0 && length(ir$outputs) == 0) {
    cli::cli_warn(c(
      "No inputs or outputs detected in the app.",
      i = "Use {.fn bindMcp} to annotate elements, or set {.code selective = FALSE}."
    ))
  }

  # Analyze reactive graph and generate tool definitions
  analysis <- analyze_reactive_graph(ir)
  generated_tools <- generate_tools_from_groups(analysis$tool_groups, ir)

  if (length(analysis$warnings) > 0) {
    for (w in analysis$warnings) {
      cli::cli_warn(w)
    }
  }

  mcp_app(
    ui = ui,
    tools = generated_tools,
    name = name %||% "shinymcp-app",
    version = version
  )
}

#' @rdname as_mcp_app
#' @export
as_mcp_app.McpApp <- function(x, ...) {
  x
}

#' @rdname as_mcp_app
#' @export
as_mcp_app.default <- function(x, ...) {
  # If it's a path string, convert via convert_app
  if (is.character(x) && length(x) == 1 && dir.exists(x)) {
    return(convert_app(x, ...))
  }
  cli::cli_abort(
    c(
      "{.fn as_mcp_app} does not know how to handle objects of class {.cls {class(x)}}.",
      i = "Expected a {.cls shiny.appobj}, {.cls McpApp}, or a directory path."
    ),
    class = "shinymcp_error_validation"
  )
}


# ---- Internal helpers ----

#' Extract UI from a shiny.appobj
#' @param app A shiny.appobj
#' @return htmltools tag or tagList
#' @noRd
extract_shiny_ui <- function(app) {
  # shiny.appobj stores UI in multiple possible ways
  ui <- app$ui
  if (is.function(ui)) {
    # Some apps use a UI function — call it with a mock request
    ui <- ui(NULL)
  }
  if (is.null(ui)) {
    rlang::abort(
      "Could not extract UI from the shinyApp object.",
      class = "shinymcp_error_validation"
    )
  }
  ui
}

#' Extract server function from a shiny.appobj
#' @param app A shiny.appobj
#' @return A function, or NULL
#' @noRd
extract_shiny_server <- function(app) {
  # Try serverFuncSource first (preferred), then fall back to server field
  if (is.function(app$serverFuncSource)) {
    tryCatch(
      app$serverFuncSource(),
      error = function(e) NULL
    )
  } else {
    NULL
  }
}

#' Check if any tag in the tree has MCP annotations
#' @param ui An htmltools tag or tagList
#' @return Logical
#' @noRd
has_any_mcp_annotations <- function(ui) {
  found <- FALSE
  walk_tag_tree(ui, function(tag) {
    if (found) return()
    if (!is.null(htmltools::tagGetAttribute(tag, "data-shinymcp-input")) ||
          !is.null(htmltools::tagGetAttribute(tag, "data-shinymcp-output"))) {
      found <<- TRUE
    }
  })
  found
}

#' Generate ellmer tool definitions from tool groups
#'
#' Creates tool objects from the analysis output. In Round 1, tool handler
#' functions are stubs that describe their expected behavior. In Round 2,
#' these will be backed by a headless Shiny session.
#'
#' @param tool_groups List of tool groups from [analyze_reactive_graph()]
#' @param ir The ShinyAppIR for metadata
#' @return List of tool objects (plain lists with name, description, fun, inputSchema)
#' @noRd
generate_tools_from_groups <- function(tool_groups, ir) {
  lapply(tool_groups, function(group) {
    # Build input schema from input args
    properties <- list()
    for (inp in group$input_args) {
      prop_type <- switch(
        inp$type %||% "unknown",
        numeric = "number",
        slider = "number",
        checkbox = "boolean",
        "string"
      )
      properties[[inp$id]] <- list(
        type = prop_type,
        description = inp$label %||% inp$id
      )
    }

    input_schema <- list(
      type = "object",
      properties = properties
    )

    # Build output target IDs for the tool result
    output_ids <- vapply(
      group$output_targets,
      function(o) o$id,
      character(1)
    )

    # Create tool handler stub
    # The function accepts tool arguments and returns a named list
    # matching output IDs
    tool_fn <- make_stub_handler(group$input_args, group$output_targets)

    list(
      name = group$name,
      description = group$description %||% "",
      inputSchema = input_schema,
      fun = tool_fn,
      .output_ids = output_ids
    )
  })
}

#' Create a stub handler function for a tool group
#'
#' Builds a function whose formals match the input argument IDs and
#' which returns a named list of output placeholders.
#'
#' @param input_args List of input definitions
#' @param output_targets List of output definitions
#' @return A function
#' @noRd
make_stub_handler <- function(input_args, output_targets) {
  output_ids <- vapply(output_targets, function(o) o$id, character(1))

  fn <- function(...) {
    args <- list(...)
    result <- setNames(
      lapply(output_ids, function(id) {
        paste0("[Output '", id, "' — provide a handler via `tools` argument]")
      }),
      output_ids
    )
    result
  }

  # Set proper formals from input metadata
  if (length(input_args) > 0) {
    input_formals <- lapply(input_args, function(inp) {
      # Use a sensible default based on type
      switch(
        inp$type %||% "unknown",
        numeric = 0,
        slider = 0,
        checkbox = FALSE,
        ""
      )
    })
    names(input_formals) <- vapply(input_args, function(inp) inp$id, character(1))
    formals(fn) <- input_formals
  }

  fn
}
