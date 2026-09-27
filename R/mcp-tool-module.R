# mcp_tool_module(): serve a Shiny module as an MCP App

#' Serve a Shiny module as an MCP App
#'
#' @description
#' Wraps a Shiny module (a UI function and a server function that take an
#' `id`) as an [McpApp]. The module runs live, as with [as_mcp_app()]: its
#' UI is the page and its server function runs in R for each view. The tool
#' the model calls takes the module's inputs by their un-namespaced ids.
#'
#' Pass `handler` to skip the live runtime and compute the module's outputs
#' with your own function instead. Its arguments are input ids and it
#' returns a list named by output ids, as tools for [mcp_app()] do.
#'
#' The same module can be shown in a shinychat conversation with
#' `shinychat::chat_tool_module()` and served here to MCP clients.
#'
#' @param module_ui A module UI function, `function(id)`.
#' @param module_server A module server function, `function(id, ...)`,
#'   that calls [shiny::moduleServer()].
#' @param name App and tool name.
#' @param description What the module does, for the model.
#' @param handler Optional function to use instead of running
#'   `module_server`.
#' @param arguments With `handler`, optional [ellmer::tool()] argument types.
#'   Without them, the input schema is guessed from the handler's defaults.
#' @param version App version string.
#' @param ... Extra arguments passed to `module_server`.
#' @return An [McpApp].
#' @family apps
#' @export
#' @examples
#' \dontrun{
#' library(shiny)
#'
#' hist_ui <- function(id) {
#'   ns <- NS(id)
#'   tagList(
#'     sliderInput(ns("bins"), "Bins", min = 5, max = 50, value = 20),
#'     plotOutput(ns("plot"), height = "250px")
#'   )
#' }
#' hist_server <- function(id) {
#'   moduleServer(id, function(input, output, session) {
#'     output$plot <- renderPlot(hist(faithful$eruptions, breaks = input$bins))
#'   })
#' }
#'
#' app <- mcp_tool_module(
#'   hist_ui,
#'   hist_server,
#'   name = "eruptions",
#'   description = "Histogram of Old Faithful eruption times."
#' )
#' preview_app(app)
#' }
mcp_tool_module <- function(
  module_ui,
  module_server,
  name,
  description,
  handler = NULL,
  arguments = NULL,
  version = "0.1.0",
  ...
) {
  if (!is.function(module_ui)) {
    shinymcp_abort("{.arg module_ui} must be a function.", class = "shinymcp_error_validation")
  }
  if (!is.function(module_server)) {
    shinymcp_abort("{.arg module_server} must be a function.", class = "shinymcp_error_validation")
  }
  if (!is_string(name)) {
    shinymcp_abort("{.arg name} must be a non-empty string.", class = "shinymcp_error_validation")
  }
  if (!is.character(description) || length(description) != 1) {
    shinymcp_abort("{.arg description} must be a single string.", class = "shinymcp_error_validation")
  }

  ns_id <- paste0("mcp-", sanitize_name(name))
  ui <- tryCatch(
    module_ui(ns_id),
    error = function(e) {
      shinymcp_abort(
        c("Couldn't render {.arg module_ui} with id {.val {ns_id}}.", "x" = conditionMessage(e)),
        class = "shinymcp_error_validation",
        parent = e
      )
    }
  )

  if (is.null(handler)) {
    extra <- list(...)
    runtime <- ShinyRuntime$new(
      server = function(input, output, session) {
        do.call(module_server, c(list(ns_id), extra))
      },
      ui = ui,
      app_name = name,
      description = description,
      ns = ns_id
    )
    return(mcp_app(
      ui = ui,
      tools = runtime$tools(),
      name = name,
      description = description,
      version = version,
      runtime = runtime
    ))
  }

  # A handler: the module's UI with a stateless tool behind it.
  inputs <- normalize_module_bindings(extract_inputs_from_tags(ui, selective = FALSE), ns_id)
  outputs <- normalize_module_bindings(extract_outputs_from_tags(ui, selective = FALSE), ns_id)
  ui <- annotate_module_ui(ui, inputs, outputs)
  tool <- if (!is.null(arguments)) {
    rlang::check_installed("ellmer", reason = "for typed tool arguments.")
    ellmer::tool(handler, name = name, description = description, arguments = arguments)
  } else {
    list(
      name = name,
      description = description,
      fun = handler,
      inputSchema = schema_from_formals(handler),
      outputs = vapply(outputs, `[[`, character(1), "id")
    )
  }
  mcp_app(ui = ui, tools = list(tool), name = name, description = description, version = version)
}

#' Strip a module namespace from binding ids, keeping DOM ids separately
#' @noRd
normalize_module_bindings <- function(bindings, ns_id) {
  prefix <- paste0(ns_id, "-")
  lapply(bindings, function(binding) {
    binding$dom_id <- binding$dom_id %||% binding$id
    if (!is.null(binding$id) && startsWith(binding$id, prefix)) {
      binding$id <- substr(binding$id, nchar(prefix) + 1L, nchar(binding$id))
    }
    binding
  })
}

#' Stamp MCP attributes on detected inputs and outputs
#'
#' In tools mode the bridge finds inputs by tool argument name; a module's
#' elements have namespaced ids, so `data-shinymcp-input` records the plain
#' name. Outputs get `data-shinymcp-output` and a type.
#' @noRd
annotate_module_ui <- function(ui, inputs, outputs) {
  input_ids <- vapply(inputs, function(x) x$id, character(1))
  input_dom_ids <- vapply(inputs, function(x) x$dom_id %||% x$id, character(1))
  output_ids <- vapply(outputs, function(x) x$id, character(1))
  output_dom_ids <- vapply(outputs, function(x) x$dom_id %||% x$id, character(1))
  output_types <- vapply(outputs, function(x) x$type %||% "html", character(1))

  annotate_node <- function(node) {
    if (inherits(node, "shiny.tag")) {
      detected <- detect_mcp_role(node)
      if (!is.null(detected$id) && detected$role == "output" && detected$id %in% output_dom_ids) {
        idx <- match(detected$id, output_dom_ids)
        if (
          !identical(htmltools::tagGetAttribute(node, "data-shinymcp-output"), output_ids[[idx]]) ||
            !identical(htmltools::tagGetAttribute(node, "data-shinymcp-output-type"), output_types[[idx]])
        ) {
          node <- mcp_output(node, id = output_ids[[idx]], type = output_types[[idx]])
        }
      }
      if (!is.null(detected$id) && detected$role == "input" && detected$id %in% input_dom_ids) {
        idx <- match(detected$id, input_dom_ids)
        if (!has_mcp_annotation(node)) {
          node <- mcp_input(node, id = input_ids[[idx]])
        }
      }
      if (!is.null(node$children)) {
        for (i in seq_along(node$children)) {
          node$children[i] <- list(annotate_node(node$children[[i]]))
        }
      }
      return(node)
    }
    if (inherits(node, "html_dependency")) {
      return(node)
    }
    if (is.list(node)) {
      for (i in seq_along(node)) {
        node[i] <- list(annotate_node(node[[i]]))
      }
    }
    node
  }
  annotate_node(ui)
}
