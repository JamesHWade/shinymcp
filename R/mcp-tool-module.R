# mcp_tool_module() — wrap a Shiny module as an MCP App
#
# Mirrors shinychat's chat_tool_module() for the MCP runtime.
# Takes a standard Shiny module (ui + server) and creates an McpApp.

#' Create an MCP App from a Shiny module
#'
#' Wraps a standard Shiny module (UI function + server function) as an
#' [McpApp]. The module UI is rendered with MCP-compatible attributes, and
#' a tool is created to drive the module's inputs and outputs.
#'
#' This mirrors `shinychat::chat_tool_module()` for the MCP runtime — the
#' same module can be used in both contexts.
#'
#' @param module_ui A Shiny module UI function that accepts an `id` argument
#'   (e.g., `function(id) { ns <- NS(id); tagList(...) }`).
#' @param module_server A Shiny module server function (currently stored
#'   as metadata for Round 2 headless driver support).
#' @param name Tool/app name. Used in `ui://` resource URIs.
#' @param description Human-readable description of what the tool does.
#' @param handler Optional tool handler function. If provided, this function
#'   is called when the MCP tool is invoked. Its arguments should match the
#'   module's input IDs. If `NULL`, a stub handler is generated.
#' @param arguments Optional list of [ellmer::type_string()], [ellmer::type_number()],
#'   etc. for the tool's input schema. If `NULL`, arguments are auto-detected
#'   from the rendered module UI.
#' @param version App version string.
#' @param ... Additional arguments stored as module metadata (e.g., shared
#'   reactive values to pass to the module server in Round 2).
#'
#' @return An [McpApp] object.
#'
#' @examples
#' \dontrun{
#' library(shiny)
#'
#' # Define a standard Shiny module
#' hist_ui <- function(id) {
#'   ns <- NS(id)
#'   tagList(
#'     sliderInput(ns("bins"), "Bins:", min = 5, max = 50, value = 25),
#'     plotOutput(ns("plot"), height = "250px")
#'   )
#' }
#'
#' hist_server <- function(id, dataset) {
#'   moduleServer(id, function(input, output, session) {
#'     output$plot <- renderPlot({
#'       hist(dataset(), breaks = input$bins, col = "#007bc2")
#'     })
#'   })
#' }
#'
#' # Create and serve as MCP App
#' app <- mcp_tool_module(
#'   hist_ui, hist_server,
#'   name = "histogram",
#'   description = "Show an interactive histogram",
#'   handler = function(bins = 25) {
#'     tmp <- tempfile(fileext = ".png")
#'     grDevices::png(tmp, width = 600, height = 250)
#'     hist(faithful$eruptions, breaks = bins, col = "#007bc2")
#'     grDevices::dev.off()
#'     list(plot = base64enc::base64encode(tmp))
#'   }
#' )
#' serve(app)
#' }
#'
#' @export
mcp_tool_module <- function(module_ui, module_server, name, description,
                            handler = NULL, arguments = NULL,
                            version = "0.1.0", ...) {
  if (!is.function(module_ui)) {
    rlang::abort(
      cli::format_inline("{.arg module_ui} must be a function."),
      class = "shinymcp_error_validation"
    )
  }
  if (!is.function(module_server)) {
    rlang::abort(
      cli::format_inline("{.arg module_server} must be a function."),
      class = "shinymcp_error_validation"
    )
  }
  if (!is.character(name) || length(name) != 1 || !nzchar(name)) {
    rlang::abort(
      cli::format_inline("{.arg name} must be a non-empty string."),
      class = "shinymcp_error_validation"
    )
  }

  ns_id <- paste0("shinymcp-", name)

  # Render the module UI with namespace
  ui <- module_ui(ns_id)

  # Auto-detect inputs and outputs from the rendered UI
  detected_inputs <- extract_inputs_from_tags(ui, selective = FALSE)
  detected_outputs <- extract_outputs_from_tags(ui, selective = FALSE)

  # Stamp MCP annotations on all detected elements
  ui <- annotate_module_ui(ui, detected_inputs, detected_outputs)

  # Build the tool
  if (!is.null(handler)) {
    # User-provided handler — use ellmer if arguments are provided
    if (!is.null(arguments)) {
      rlang::check_installed("ellmer", reason = "for typed tool arguments")
      tool <- ellmer::tool(
        fun = handler,
        name = name,
        description = description %||% "",
        arguments = arguments
      )
    } else {
      tool <- list(
        name = name,
        description = description %||% "",
        fun = handler,
        inputSchema = build_schema_from_formals(handler)
      )
    }
  } else {
    # Generate stub tool from detected inputs/outputs
    tool <- list(
      name = name,
      description = description %||% "",
      fun = make_stub_handler(detected_inputs, detected_outputs),
      inputSchema = build_schema_from_inputs(detected_inputs)
    )
  }

  # Store module metadata for Round 2 headless driver
  extra_args <- list(...)
  attr(tool, "module_metadata") <- list(
    module_ui = module_ui,
    module_server = module_server,
    ns_id = ns_id,
    extra_args = extra_args
  )

  mcp_app(ui = ui, tools = list(tool), name = name, version = version)
}


#' Annotate module UI tags with MCP attributes
#'
#' Stamps `data-shinymcp-input` and `data-shinymcp-output` on detected
#' elements so the JS bridge can discover them.
#'
#' @param ui htmltools tag or tagList
#' @param inputs List of detected input definitions
#' @param outputs List of detected output definitions
#' @return Modified UI with MCP annotations
#' @noRd
annotate_module_ui <- function(ui, inputs, outputs) {
  input_ids <- vapply(inputs, function(x) x$id, character(1))
  output_ids <- vapply(outputs, function(x) x$id, character(1))
  output_types <- vapply(outputs, function(x) x$type %||% "html", character(1))

  # Walk and annotate
  annotate_tag <- function(tag) {
    if (!inherits(tag, "shiny.tag")) return(tag)

    tag_id <- htmltools::tagGetAttribute(tag, "id")
    classes <- htmltools::tagGetAttribute(tag, "class") %||% ""

    # Annotate outputs (they have the id directly on the tag)
    if (!is.null(tag_id) && tag_id %in% output_ids) {
      idx <- match(tag_id, output_ids)
      if (!is.null(htmltools::tagGetAttribute(tag, "data-shinymcp-output"))) {
        # Already annotated
      } else {
        tag <- htmltools::tagAppendAttributes(
          tag,
          `data-shinymcp-output` = tag_id,
          `data-shinymcp-output-type` = output_types[idx]
        )
      }
    }

    # Annotate input containers (find form element inside)
    if (grepl("shiny-input-container", classes, fixed = TRUE)) {
      form_id <- find_form_element_id(tag)
      if (!is.null(form_id) && form_id %in% input_ids) {
        tq <- htmltools::tagQuery(tag)
        for (sel in c("select", "input", "textarea", "button")) {
          found <- tq$find(sel)
          if (found$length() > 0) {
            first <- found$selectedTags()[[1]]
            existing <- htmltools::tagGetAttribute(first, "data-shinymcp-input")
            if (is.null(existing)) {
              found$addAttrs(`data-shinymcp-input` = form_id)
            }
            break
          }
        }
        tag <- tq$allTags()
      }
    }

    # Recurse into children
    if (!is.null(tag$children)) {
      tag$children <- lapply(tag$children, annotate_tag)
    }
    tag
  }

  if (inherits(ui, "shiny.tag")) {
    annotate_tag(ui)
  } else if (inherits(ui, "shiny.tag.list") || is.list(ui)) {
    htmltools::tagList(lapply(ui, annotate_tag))
  } else {
    ui
  }
}


#' Build JSON Schema from a function's formals
#' @param fn A function
#' @return A list with type = "object" and properties
#' @noRd
build_schema_from_formals <- function(fn) {
  frmls <- formals(fn)
  props <- list()
  for (nm in names(frmls)) {
    default <- frmls[[nm]]
    prop_type <- if (is.numeric(default)) {
      "number"
    } else if (is.logical(default)) {
      "boolean"
    } else {
      "string"
    }
    props[[nm]] <- list(type = prop_type, description = nm)
  }
  list(type = "object", properties = props)
}


#' Build JSON Schema from detected input definitions
#' @param inputs List of input definitions (id, type, label)
#' @return A list with type = "object" and properties
#' @noRd
build_schema_from_inputs <- function(inputs) {
  props <- list()
  for (inp in inputs) {
    prop_type <- switch(
      inp$type %||% "unknown",
      numeric = "number",
      slider = "number",
      checkbox = "boolean",
      "string"
    )
    props[[inp$id]] <- list(
      type = prop_type,
      description = inp$label %||% inp$id
    )
  }
  list(type = "object", properties = props)
}
