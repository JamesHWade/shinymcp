# Generate MCP App files from analysis

#' Write the draft of an app built from tools
#'
#' `generate_mcp_app()` writes the files of [convert_app()]'s draft: `ui.R`
#' (the app's inputs and outputs), `tools.R` (one tool per group, with the
#' app's code for it as comments), `app.R`, and, when some of the app's code
#' doesn't fit a tool, `CONVERSION_NOTES.md`.
#'
#' @param analysis The result of [analyze_reactive_graph()].
#' @param ir The result of [parse_shiny_app()] it was made from.
#' @param output_dir Directory to write the files to.
#' @return `output_dir`, invisibly.
#' @family conversion
#' @export
generate_mcp_app <- function(analysis, ir, output_dir) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Generate UI HTML
  html <- generate_html(ir$inputs, ir$outputs)
  writeLines(html, file.path(output_dir, "ui.R"))

  # Generate tools.R
  tools_code <- generate_tools(analysis$tool_groups, ir$reactives)
  writeLines(tools_code, file.path(output_dir, "tools.R"))

  # Generate app.R that ties it together
  app_code <- generate_app_entry(ir, analysis)
  writeLines(app_code, file.path(output_dir, "app.R"))

  # Write conversion notes for complex apps
  if (ir$complexity == "complex" || length(analysis$warnings) > 0) {
    notes <- generate_conversion_notes(analysis, ir)
    writeLines(notes, file.path(output_dir, "CONVERSION_NOTES.md"))
  }

  # Fail loudly at write time rather than letting unparseable generated code
  # degrade silently downstream in convert_app().
  for (f in c("ui.R", "tools.R", "app.R")) {
    validate_generated_r(file.path(output_dir, f))
  }

  cli::cli_alert_success("Generated MCP App in {.path {output_dir}}")
  invisible(output_dir)
}

#' Validate that a generated file is syntactically valid R
#'
#' Parses (without evaluating) a generated file and raises a structured
#' generation error naming the file if it is not valid R. Catching this here
#' turns a whole class of code-generation bugs from silent into loud.
#'
#' @param path Path to a generated `.R` file.
#' @return The path, invisibly.
#' @noRd
validate_generated_r <- function(path) {
  tryCatch(
    parse(file = path),
    error = function(e) {
      shinymcp_error_generation(
        c(
          "Generated file {.path {basename(path)}} is not valid R.",
          "x" = "{conditionMessage(e)}",
          "i" = "This is a shinymcp code-generation bug. Please report it at {.url https://github.com/JamesHWade/shinymcp/issues}."
        )
      )
    }
  )
  invisible(path)
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
  lines <- c(
    lines,
    "# The app's UI, drafted by shinymcp::convert_app(). Shiny and bslib"
  )
  lines <- c(
    lines,
    "# inputs and outputs work here too; ids connect them to the tools."
  )
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
    actionButton = ,
    actionLink = {
      sprintf('mcp_action_button(%s, %s)', id, label)
    },
    # Default: text input fallback
    {
      sprintf(
        '# NOTE: Unsupported input type "%s" converted to text input\n  mcp_text_input(%s, %s)',
        inp$type,
        id,
        label
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
      '# NOTE: Unsupported output type "%s" converted to text output\n  mcp_text(%s)',
      out$type,
      id
    )
  )
}

#' Draft the tools.R of a converted app
#'
#' One `ellmer::tool()` per tool group. Each draft takes the group's inputs as
#' typed arguments with the app's defaults, carries the app's code for the
#' group (reactive expressions and render calls) as comments to rewrite, and
#' already returns a list named by the group's outputs.
#'
#' @param tool_groups Tool groups from [analyze_reactive_graph()].
#' @param reactives The parsed app's reactive expressions (`ir$reactives`).
#' @return Character string of R code.
#' @noRd
generate_tools <- function(tool_groups, reactives = list()) {
  lines <- c(
    "# The app's tools, drafted by shinymcp::convert_app().",
    "#",
    "# Each tool computes outputs that share inputs in the Shiny app. Its body",
    "# holds the app's code for them as comments: rewrite it with the tool's",
    "# arguments in place of input$..., and return each output by its id."
  )
  for (group in tool_groups) {
    lines <- c(lines, "", generate_tool_definition(group, reactives))
  }
  lines <- c(
    lines,
    "",
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

#' The app's code for a tool group, as comment lines
#' @noRd
group_code_comment <- function(group, reactives = list()) {
  code <- character()
  by_name <- stats::setNames(
    reactives,
    vapply(reactives, function(r) r$name %||% "", character(1))
  )
  for (name in group$reactive_names %||% character()) {
    r <- by_name[[name]]
    if (is.null(r) || is.null(r$body_expr)) {
      next
    }
    body <- deparse(r$body_expr, width.cutoff = 70)
    body[1] <- paste0(name, " <- reactive(", body[1])
    body[length(body)] <- paste0(body[length(body)], ")")
    code <- c(code, body, "")
  }
  for (out in group$output_targets) {
    if (is.null(out$render_expr)) {
      next
    }
    body <- deparse(out$render_expr, width.cutoff = 70)
    body[1] <- paste0("output$", out$id, " <- ", body[1])
    code <- c(code, body, "")
  }
  if (length(code) == 0) {
    return(character())
  }
  code <- code[seq_len(max(which(nzchar(code))))]
  c(
    "    # From the Shiny app:",
    "    #",
    sub("\\s+$", "", paste0("    # ", code))
  )
}

#' A literal vector from a call such as c("a", "b"), or NULL
#' @noRd
literal_values <- function(expr) {
  if (is.atomic(expr)) {
    return(expr)
  }
  if (!is.call(expr) || !identical(expr[[1]], as.name("c"))) {
    return(NULL)
  }
  parts <- as.list(expr)[-1]
  if (
    !all(vapply(parts, function(p) is.atomic(p) && length(p) == 1, logical(1)))
  ) {
    return(NULL)
  }
  values <- unlist(parts)
  names(values) <- NULL
  values
}

#' The draft of one tool argument: its type and its default
#' @return A list with `type` (R code) and `default` (R code or NULL).
#' @noRd
draft_argument <- function(inp) {
  label <- sub("[:[:space:]]+$", "", trimws(inp$label %||% inp$id))
  if (!nzchar(label)) {
    label <- inp$id
  }
  args <- inp$args %||% list()
  code <- function(x) paste(deparse(x), collapse = "")
  choices <- literal_values(args$choices)
  default <- switch(
    inp$type,
    select = ,
    selectize = ,
    radio = literal_values(args$selected) %||%
      if (length(choices)) choices[[1]],
    checkboxGroup = literal_values(args$selected),
    numeric = ,
    slider = ,
    checkbox = ,
    text = ,
    textArea = ,
    date = literal_values(args$value),
    NULL
  )
  if (identical(inp$type, "checkbox") && is.null(default)) {
    default <- FALSE
  }
  type_code <- function(fn, extra = NULL) {
    paste0(
      "ellmer::",
      fn,
      "(",
      paste(
        c(
          extra,
          deparse_string(label),
          if (!is.null(default)) "required = FALSE"
        ),
        collapse = ", "
      ),
      ")"
    )
  }
  type <- switch(
    inp$type,
    select = ,
    selectize = ,
    radio = if (length(choices)) {
      type_code("type_enum", code(as.character(choices)))
    } else {
      type_code("type_string")
    },
    checkboxGroup = paste0(
      "ellmer::type_array(ellmer::type_string(), ",
      deparse_string(label),
      if (!is.null(default)) ", required = FALSE",
      ")"
    ),
    numeric = ,
    slider = type_code("type_number"),
    checkbox = type_code("type_boolean"),
    date = {
      label <- paste(label, "(YYYY-MM-DD)")
      type_code("type_string")
    },
    type_code("type_string")
  )
  list(type = type, default = if (!is.null(default)) code(default))
}

#' Draft one ellmer::tool() definition
#' @param group A tool group.
#' @param reactives The parsed app's reactive expressions.
#' @return Character vector of R code lines.
#' @noRd
generate_tool_definition <- function(group, reactives = list()) {
  drafts <- lapply(group$input_args, draft_argument)
  ids <- vapply(group$input_args, function(inp) inp$id, character(1))
  params <- vapply(
    seq_along(ids),
    function(i) {
      if (is.null(drafts[[i]]$default)) {
        ids[[i]]
      } else {
        paste0(ids[[i]], " = ", drafts[[i]]$default)
      }
    },
    character(1)
  )
  arg_specs <- vapply(
    seq_along(ids),
    function(i) sprintf("    %s = %s", ids[[i]], drafts[[i]]$type),
    character(1)
  )
  outputs <- vapply(group$output_targets, function(o) o$id, character(1))
  returns <- if (length(outputs)) {
    c(
      "    list(",
      paste0(
        sprintf('      %s = "TODO: output$%s"', outputs, outputs),
        c(rep(",", length(outputs) - 1), "")
      ),
      "    )"
    )
  } else {
    "    list()"
  }
  description <- gsub(":", "", group$description %||% group$name, fixed = TRUE)

  c(
    sprintf("%s <- ellmer::tool(", group$name),
    sprintf("  function(%s) {", paste(params, collapse = ", ")),
    group_code_comment(group, reactives),
    returns,
    "  },",
    sprintf("  name = %s,", deparse_string(group$name)),
    sprintf("  description = %s,", deparse_string(description)),
    "  arguments = list(",
    paste(arg_specs, collapse = ",\n"),
    "  ),",
    "  annotations = ellmer::tool_annotations(read_only_hint = TRUE)",
    ")"
  )
}

#' Generate app.R that ties everything together
#'
#' @param ir The ShinyAppIR object
#' @param analysis Optional ReactiveAnalysis; when provided, a commented
#'   `tool_outputs` mapping is emitted for the user to enable once the
#'   placeholder tool bodies return named lists keyed by output ids.
#' @return Character string of R code
#' @noRd
generate_app_entry <- function(ir, analysis = NULL) {
  app_name <- basename(ir$path)

  # The drafted tools return lists named by these outputs, so each can
  # declare them (and get an outputSchema).
  tool_output_lines <- character()
  if (!is.null(analysis)) {
    mappings <- character()
    for (group in analysis$tool_groups) {
      output_ids <- vapply(group$output_targets, function(o) o$id, character(1))
      if (length(output_ids) > 0) {
        mappings <- c(
          mappings,
          sprintf(
            "    %s = c(%s)",
            group$name,
            paste0('"', output_ids, '"', collapse = ", ")
          )
        )
      }
    }
    if (length(mappings) > 0) {
      mappings <- paste0(mappings, c(rep(",", length(mappings) - 1), ""))
      tool_output_lines <- c("  tool_outputs = list(", mappings, "  ),")
    }
  }

  lines <- c(
    sprintf(
      "# Drafted by shinymcp::convert_app() from the Shiny app in %s.",
      app_name
    ),
    "# Fill in the tools in tools.R, then try the app:",
    '#   shinymcp::preview_app("app.R")',
    "",
    "library(shinymcp)",
    "",
    "# A chat client runs this file with Rscript from a directory of its own;",
    "# work from the one this file is in.",
    'script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))',
    'if (!file.exists("tools.R") && length(script) == 1) {',
    "  setwd(dirname(script))",
    "}",
    "",
    'source("ui.R", local = TRUE)',
    'source("tools.R", local = TRUE)',
    "",
    "app <- mcp_app(",
    "  ui,",
    "  tools = tools,",
    tool_output_lines,
    sprintf('  name = "%s"', app_name),
    ")",
    "",
    "if (interactive()) preview_app(app) else serve(app)"
  )

  paste(lines, collapse = "\n")
}

#' Generate conversion notes markdown
#'
#' @param analysis ReactiveAnalysis object
#' @param ir ShinyAppIR object
#' @return Character string of markdown
#' @noRd
generate_conversion_notes <- function(
  analysis,
  ir,
  mode = c("scaffold", "cards")
) {
  mode <- match.arg(mode)
  lines <- c(
    "# Conversion Notes",
    "",
    sprintf("Source: `%s`", ir$path),
    sprintf("Complexity: **%s**", ir$complexity),
    sprintf("Mode: **%s**", mode),
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
    "## Scaffold Status",
    "",
    "This output is **scaffold-oriented**, not a headless execution runtime.",
    "Generated tool bodies remain placeholders until you supply explicit logic.",
    "",
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

  if (identical(mode, "cards")) {
    lines <- c(
      lines,
      "## Card Mode Notes",
      "",
      "Card mode prefers multiple compact chat-sized surfaces over a single dashboard.",
      "Review each generated card directory and tighten labels, defaults, and output copy for chat use.",
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
  # deparse() can return a multi-element character vector for wide or
  # multi-line values; collapse so callers always get one parseable string.
  tryCatch(
    paste(deparse(val, width.cutoff = 500), collapse = " "),
    error = function(e) default
  )
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
