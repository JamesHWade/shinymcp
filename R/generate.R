# Generate MCP App files from analysis

#' Generate MCP App from analysis
#'
#' Produces HTML, tools, and server code for an MCP App based on the
#' analysis of a Shiny app.
#'
#' @param analysis A `ReactiveAnalysis` object from [analyze_reactive_graph()]
#' @param ir The original `ShinyAppIR` object
#' @param output_dir Directory to write generated files
#' @return The output directory path (invisibly)
#' @export
generate_mcp_app <- function(analysis, ir, output_dir) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Generate UI HTML
  html <- generate_html(ir$inputs, ir$outputs)
  writeLines(html, file.path(output_dir, "ui.html"))

  # Generate tools.R
  tools_code <- generate_tools(analysis$tool_groups)
  writeLines(tools_code, file.path(output_dir, "tools.R"))

  # Generate server.R entrypoint
  server_code <- generate_server(analysis$tool_groups)
  writeLines(server_code, file.path(output_dir, "server.R"))

  # Generate app.R that ties it together
  app_code <- generate_app_entry(ir)
  writeLines(app_code, file.path(output_dir, "app.R"))

  # Write conversion notes for complex apps
  if (ir$complexity == "complex" || length(analysis$warnings) > 0) {
    notes <- generate_conversion_notes(analysis, ir)
    writeLines(notes, file.path(output_dir, "CONVERSION_NOTES.md"))
  }

  cli::cli_alert_success("Generated MCP App in {.path {output_dir}}")
  invisible(output_dir)
}

#' Generate HTML for MCP App UI
#'
#' Maps Shiny input/output definitions to shinymcp component calls.
#'
#' @param inputs List of input definitions from IR
#' @param outputs List of output definitions from IR
#' @return Character string of R code that builds htmltools UI
#' @noRd
generate_html <- function(inputs, outputs) {
  lines <- character()
  lines <- c(lines, "# Generated MCP App UI")
  lines <- c(lines, "# This file defines the UI using shinymcp components")
  lines <- c(lines, "")
  lines <- c(lines, "library(shinymcp)")
  lines <- c(lines, "")
  lines <- c(lines, "ui <- htmltools::tagList(")

  components <- character()

  # Map inputs to mcp_* components
  for (inp in inputs) {
    comp <- generate_input_component(inp)
    if (!is.null(comp)) {
      components <- c(components, comp)
    }
  }

  # Map outputs to mcp_* components
  for (out in outputs) {
    comp <- generate_output_component(out)
    if (!is.null(comp)) {
      components <- c(components, comp)
    }
  }

  if (length(components) > 0) {
    lines <- c(lines, paste0("  ", paste(components, collapse = ",\n  ")))
  }

  lines <- c(lines, ")")
  lines <- c(lines, "")

  paste(lines, collapse = "\n")
}

#' Generate an MCP input component call from an input definition
#' @param inp Input definition from IR
#' @return Character string of R code, or NULL
#' @noRd
generate_input_component <- function(inp) {
  id <- deparse_string(inp$id)
  label <- deparse_string(inp$label)

  switch(
    inp$type,
    select = ,
    selectize = {
      choices <- extract_choices_code(inp$args)
      sprintf('mcp_select(%s, %s, %s)', id, label, choices)
    },
    text = ,
    textArea = ,
    password = {
      value <- extract_arg_code(inp$args, "value", '""')
      sprintf('mcp_text_input(%s, %s, value = %s)', id, label, value)
    },
    numeric = {
      value <- extract_arg_code(inp$args, "value", "0")
      min_val <- extract_arg_code(inp$args, "min", "NA")
      max_val <- extract_arg_code(inp$args, "max", "NA")
      sprintf(
        'mcp_numeric_input(%s, %s, value = %s, min = %s, max = %s)',
        id,
        label,
        value,
        min_val,
        max_val
      )
    },
    checkbox = {
      value <- extract_arg_code(inp$args, "value", "FALSE")
      sprintf('mcp_checkbox(%s, %s, value = %s)', id, label, value)
    },
    slider = {
      min_val <- extract_arg_code(inp$args, "min", "0")
      max_val <- extract_arg_code(inp$args, "max", "100")
      value <- extract_arg_code(inp$args, "value", min_val)
      sprintf(
        'mcp_slider(%s, %s, min = %s, max = %s, value = %s)',
        id,
        label,
        min_val,
        max_val,
        value
      )
    },
    radio = {
      choices <- extract_choices_code(inp$args)
      sprintf('mcp_radio(%s, %s, %s)', id, label, choices)
    },
    action = ,
    actionLink = {
      sprintf('mcp_action_button(%s, %s)', id, label)
    },
    # Default: text input fallback
    {
      sprintf(
        'mcp_text_input(%s, %s)\n# NOTE: Unsupported input type "%s" converted to text input',
        id,
        label,
        inp$type
      )
    }
  )
}

#' Generate an MCP output component call from an output definition
#' @param out Output definition from IR
#' @return Character string of R code, or NULL
#' @noRd
generate_output_component <- function(out) {
  id <- deparse_string(out$id)

  switch(
    out$type,
    plot = ,
    image = sprintf('mcp_plot(%s)', id),
    text = ,
    verbatimText = sprintf('mcp_text(%s)', id),
    table = ,
    dataTable = sprintf('mcp_table(%s)', id),
    html = ,
    ui = sprintf('mcp_html(%s)', id),
    # Default
    sprintf(
      'mcp_text(%s)\n# NOTE: Unsupported output type "%s" converted to text output',
      id,
      out$type
    )
  )
}

#' Generate tools.R code from tool groups
#'
#' Creates ellmer::tool() definitions for each tool group.
#'
#' @param tool_groups List of tool group definitions
#' @return Character string of R code
#' @noRd
generate_tools <- function(tool_groups) {
  lines <- c(
    "# Generated MCP App Tools",
    "# Each tool corresponds to a reactive computation group from the original Shiny app",
    "",
    "library(ellmer)"
  )

  for (group in tool_groups) {
    lines <- c(lines, "", generate_tool_definition(group))
  }

  lines <- c(
    lines,
    "",
    "# Collect all tools",
    sprintf(
      "tools <- list(%s)",
      paste(
        vapply(tool_groups, function(g) g$name, character(1)),
        collapse = ", "
      )
    )
  )

  paste(lines, collapse = "\n")
}

#' Generate a single ellmer::tool() definition
#' @param group A tool group definition
#' @return Character vector of R code lines
#' @noRd
generate_tool_definition <- function(group) {
  # Build argument list for ellmer type specs
  arg_specs <- vapply(
    group$input_args,
    function(inp) {
      type_fn <- switch(
        inp$type,
        numeric = ,
        slider = "type_number",
        checkbox = "type_boolean",
        "type_string"
      )
      sprintf(
        '    %s = ellmer::%s("%s")',
        inp$id,
        type_fn,
        inp$label %||% inp$id
      )
    },
    character(1)
  )

  # Build function parameter list
  param_list <- paste(
    vapply(group$input_args, function(inp) inp$id, character(1)),
    collapse = ", "
  )

  # Determine if any outputs are plots
  has_plot <- any(vapply(
    group$output_targets,
    function(o) o$type %in% c("plot", "image"),
    logical(1)
  ))

  # Build function body
  if (has_plot) {
    body_lines <- c(
      "    # Render plot to base64 PNG",
      "    tmp <- tempfile(fileext = \".png\")",
      "    grDevices::png(tmp, width = 800, height = 600)",
      "    on.exit(unlink(tmp), add = TRUE)",
      "    # TODO: Insert plot logic from original render function here",
      "    plot(1, main = \"Placeholder\")",
      "    grDevices::dev.off()",
      "    raw <- readBin(tmp, \"raw\", file.info(tmp)$size)",
      "    paste0(\"data:image/png;base64,\", base64enc::base64encode(raw))"
    )
  } else {
    body_lines <- c(
      "    # TODO: Insert computation logic from original render function here",
      sprintf("    paste(\"Result for:\", %s)", param_list)
    )
  }

  # Annotations
  annotations <- c(
    "  annotations = ellmer::tool_annotations(",
    "    read_only_hint = TRUE,",
    "    destructive_hint = FALSE,",
    "    open_world_hint = FALSE,",
    "    idempotent_hint = TRUE",
    "  )"
  )

  c(
    sprintf("%s <- ellmer::tool(", group$name),
    sprintf("  fun = function(%s) {", param_list),
    body_lines,
    "  },",
    sprintf('  name = "%s",', group$name),
    sprintf('  description = "%s",', gsub('"', '\\\\"', group$description)),
    "  arguments = list(",
    paste(arg_specs, collapse = ",\n"),
    "  ),",
    annotations,
    ")"
  )
}

#' Generate server.R that sets up state and tool handlers
#'
#' @param tool_groups List of tool group definitions
#' @return Character string of R code
#' @noRd
generate_server <- function(tool_groups) {
  lines <- c(
    "# Generated MCP App Server",
    "# Sets up state environment and sources tools",
    "",
    "# Create shared state environment for tools",
    "state <- new.env(parent = emptyenv())",
    "",
    "# Source tool definitions",
    'source("tools.R", local = TRUE)',
    "",
    "# Tool handler function",
    "handle_tool_call <- function(tool_name, args) {",
    "  tool <- tools[[tool_name]]",
    "  if (is.null(tool)) {",
    '    stop(sprintf("Unknown tool: %s", tool_name))',
    "  }",
    "  do.call(tool$fun, args)",
    "}"
  )

  paste(lines, collapse = "\n")
}

#' Generate app.R that ties everything together
#'
#' @param ir The ShinyAppIR object
#' @return Character string of R code
#' @noRd
generate_app_entry <- function(ir) {
  app_name <- basename(ir$path)

  lines <- c(
    "# Generated MCP App",
    sprintf("# Converted from Shiny app: %s", app_name),
    "",
    "library(shinymcp)",
    "",
    "# Source server setup",
    'source("server.R", local = TRUE)',
    "",
    "# Source UI definition",
    'source("ui.html", local = TRUE)',
    "",
    "# Create MCP App",
    sprintf('app <- mcp_app(ui = ui, tools = tools, name = "%s")', app_name),
    "",
    "# The app object can be served with shinymcp::serve_mcp_app(app)"
  )

  paste(lines, collapse = "\n")
}

#' Generate conversion notes markdown
#'
#' @param analysis ReactiveAnalysis object
#' @param ir ShinyAppIR object
#' @return Character string of markdown
#' @noRd
generate_conversion_notes <- function(analysis, ir) {
  lines <- c(
    "# Conversion Notes",
    "",
    sprintf("Source: `%s`", ir$path),
    sprintf("Complexity: **%s**", ir$complexity),
    "",
    "## Summary",
    "",
    sprintf("- **Inputs:** %d", length(ir$inputs)),
    sprintf("- **Outputs:** %d", length(ir$outputs)),
    sprintf("- **Reactives:** %d", length(ir$reactives)),
    sprintf("- **Observers:** %d", length(ir$observers)),
    sprintf("- **Tool groups:** %d", length(analysis$tool_groups)),
    ""
  )

  if (length(analysis$warnings) > 0) {
    lines <- c(lines, "## Warnings", "")
    for (w in analysis$warnings) {
      lines <- c(lines, sprintf("- %s", w))
    }
    lines <- c(lines, "")
  }

  lines <- c(
    lines,
    "## Manual Review Required",
    "",
    "The following areas may need manual adjustment:",
    "",
    "1. **Tool function bodies**: The generated tools contain placeholder logic.",
    "   Copy the computation from the original `render*()` functions.",
    "",
    "2. **Reactive dependencies**: Complex reactive chains may not be fully captured.",
    "   Review the tool groups to ensure correct data flow.",
    "",
    "3. **Side effects**: Any `observe()` or `observeEvent()` side effects",
    "   (e.g., database writes, file operations) need manual porting.",
    ""
  )

  if (ir$complexity == "complex") {
    lines <- c(
      lines,
      "## Complex App Notes",
      "",
      "This app was classified as **complex**. Consider:",
      "",
      "- Breaking into multiple simpler MCP Apps",
      "- Using sub-agents for multi-step workflows",
      "- Reviewing all tool group boundaries for correctness",
      ""
    )
  }

  paste(lines, collapse = "\n")
}

# ---- Code generation utilities ----

#' Deparse a string value for code generation
#' @param x A value to deparse
#' @return Character string with quotes
#' @noRd
deparse_string <- function(x) {
  if (is.null(x)) {
    return('NULL')
  }
  if (is.character(x)) {
    return(deparse(x))
  }
  if (is.numeric(x)) {
    return(as.character(x))
  }
  deparse(x)
}

#' Extract a named argument as R code
#' @param args Named list of arguments
#' @param name Argument name
#' @param default Default R code string
#' @return Character string of R code
#' @noRd
extract_arg_code <- function(args, name, default = "NULL") {
  val <- args[[name]]
  if (is.null(val)) {
    return(default)
  }
  tryCatch(deparse(val, width.cutoff = 500), error = function(e) default)
}

#' Extract choices argument as R code
#' @param args Named list of arguments
#' @return Character string of R code for choices vector
#' @noRd
extract_choices_code <- function(args) {
  val <- args[["choices"]]
  if (is.null(val)) {
    return('c("option1", "option2")')
  }
  tryCatch(
    paste(deparse(val, width.cutoff = 500), collapse = " "),
    error = function(e) 'c("option1", "option2")'
  )
}
