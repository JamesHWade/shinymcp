# Top-level Shiny-to-MCP conversion orchestrator

#' Start rewriting a Shiny app as tools
#'
#' @description
#' `convert_app()` reads a Shiny app's code and writes the first draft of an
#' MCP App built from tools: one tool for each group of connected inputs,
#' reactive expressions, and outputs. The draft is a starting point, not a
#' finished app: each tool takes its inputs as typed arguments with the
#' app's defaults and returns its outputs by id, and its body holds the
#' app's code for them (reactive expressions and render calls) as comments
#' for you to rewrite.
#'
#' Most apps don't need this: [as_mcp_app()] serves a Shiny app as it is.
#' Rewrite an app as tools when the model should be able to use its
#' computations without the app open, or when each call should stand alone
#' with no session in R. `vignette("rewriting-as-tools")` walks through it.
#'
#' The steps are also available separately: [parse_shiny_app()] reads the
#' code, [analyze_reactive_graph()] groups it into tools, and
#' [generate_mcp_app()] writes the files.
#'
#' @param path Path to a Shiny app directory, with `app.R`, or `ui.R` and
#'   `server.R`.
#' @param output_dir Where to write the draft. Defaults to the app's
#'   directory name with `_mcp` added.
#' @param mode `"scaffold"` writes one app with every tool. `"cards"` writes
#'   one small app per tool group, sized for a chat card.
#' @param selective In `"cards"` mode, whether to split by tool group
#'   (`TRUE`) or make one card of the whole app.
#' @param max_inputs_per_card In `"cards"` mode, the most inputs a card
#'   should show.
#' @param compact_layout In `"cards"` mode, whether cards use a compact
#'   layout.
#' @return The draft as an [McpApp] (or, in `"cards"` mode, a list of
#'   them), invisibly. The files are in `output_dir`: `ui.R`, `tools.R`,
#'   `app.R`, and, for apps with code that doesn't fit a tool (observers
#'   with side effects, for example), `CONVERSION_NOTES.md`.
#' @family conversion
#' @export
#' @examples
#' \dontrun{
#' convert_app("path/to/my-app")
#' }
convert_app <- function(
  path,
  output_dir = NULL,
  mode = c("scaffold", "cards"),
  selective = TRUE,
  max_inputs_per_card = 5,
  compact_layout = TRUE
) {
  mode <- match.arg(mode)
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
  cli::cli_text("Mode: {.val {mode}}")

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
  if (identical(mode, "cards")) {
    apps <- as_mcp_apps(
      ir,
      split = if (isTRUE(selective)) "tool_group" else "manual",
      max_inputs_per_card = max_inputs_per_card,
      compact_layout = compact_layout
    )
    generate_card_scaffolds(
      analysis = analysis,
      ir = ir,
      output_dir = output_dir,
      split = if (isTRUE(selective)) "tool_group" else "manual"
    )
    writeLines(
      generate_conversion_notes(analysis, ir, mode = "cards"),
      file.path(output_dir, "CONVERSION_NOTES.md")
    )
    cli::cli_alert_success("Card scaffolds generated!")
    return(invisible(apps))
  }

  generate_mcp_app(analysis, ir, output_dir)

  # Build McpApp from generated files by sourcing them
  app_env <- new.env(parent = globalenv())
  ui_file <- file.path(output_dir, "ui.R")
  tools_file <- file.path(output_dir, "tools.R")

  problems <- character()

  # Source UI definition (creates `ui` variable)
  tryCatch(
    source(ui_file, local = app_env),
    error = function(e) {
      problems <<- c(
        problems,
        sprintf("ui.R did not load: %s", conditionMessage(e))
      )
    }
  )

  # Source tools if available (creates `tools` variable)
  if (file.exists(tools_file)) {
    tryCatch(
      source(tools_file, local = app_env),
      error = function(e) {
        problems <<- c(
          problems,
          sprintf("tools.R did not load: %s", conditionMessage(e))
        )
      }
    )
  }

  has_ui <- exists("ui", envir = app_env)
  ui <- if (has_ui) {
    get("ui", envir = app_env)
  } else {
    problems <- c(problems, "no UI object was produced")
    htmltools::tags$div("Conversion produced no UI")
  }
  tools <- if (exists("tools", envir = app_env)) {
    get("tools", envir = app_env)
  } else {
    list()
  }

  app <- McpApp$new(
    ui = ui,
    tools = tools,
    name = basename(normalizePath(path))
  )

  # Report honestly: only claim success when the app actually materialized.
  if (length(problems) > 0) {
    names(problems) <- rep("*", length(problems))
    cli::cli_warn(c(
      "Conversion finished with problems; the generated app may be incomplete:",
      problems
    ))
  } else {
    cli::cli_alert_success("Conversion complete!")
  }

  if (ir$complexity == "complex") {
    cli::cli_alert_warning(
      "This app has complex patterns. Review {.path CONVERSION_NOTES.md}."
    )
  }

  invisible(app)
}

#' Draft one small app per tool group
#'
#' `as_mcp_apps()` is the `"cards"` mode of [convert_app()] without writing
#' files: it returns one draft [McpApp] for each group of connected inputs
#' and outputs, each with placeholder tools.
#'
#' @param app A path to a Shiny app directory, or the result of
#'   [parse_shiny_app()].
#' @param split `"tool_group"` for one app per tool group, or `"manual"`
#'   for a single app with every input and output.
#' @param max_inputs_per_card The most inputs a card should show.
#' @param compact_layout Whether cards use a compact layout.
#' @return A list of [McpApp] objects.
#' @family conversion
#' @export
as_mcp_apps <- function(
  app,
  split = c("tool_group", "manual"),
  max_inputs_per_card = 5,
  compact_layout = TRUE
) {
  split <- match.arg(split)

  ir <- if (inherits(app, "ShinyAppIR")) {
    app
  } else if (is.character(app) && length(app) == 1) {
    parse_shiny_app(app)
  } else {
    cli::cli_abort(
      "{.arg app} must be a Shiny app path or a {.cls ShinyAppIR} object."
    )
  }

  analysis <- analyze_reactive_graph(ir)
  groups <- if (identical(split, "tool_group")) {
    analysis$tool_groups
  } else {
    list(list(
      name = "manual_card",
      input_args = ir$inputs,
      output_targets = ir$outputs,
      reactive_names = vapply(ir$reactives, `[[`, character(1), "name"),
      description = "Manual card scaffold for the full app"
    ))
  }

  app_name <- basename(ir$path)
  apps <- lapply(groups, function(group) {
    mcp_app(
      ui = build_card_ui(group, max_inputs_per_card, compact_layout),
      tools = list(build_scaffold_tool(group)),
      name = paste0(app_name, "-", sanitize_dom_id(group$name))
    )
  })

  names(apps) <- vapply(groups, function(group) group$name, character(1))
  apps
}

#' @noRd
generate_card_scaffolds <- function(
  analysis,
  ir,
  output_dir,
  split = c("tool_group", "manual")
) {
  split <- match.arg(split)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  groups <- if (identical(split, "tool_group")) {
    analysis$tool_groups
  } else {
    list(list(
      name = "manual_card",
      input_args = ir$inputs,
      output_targets = ir$outputs,
      reactive_names = vapply(ir$reactives, `[[`, character(1), "name"),
      description = "Manual card scaffold for the full app"
    ))
  }

  for (i in seq_along(groups)) {
    group <- groups[[i]]
    group_dir <- file.path(
      output_dir,
      sprintf("%02d-%s", i, sanitize_dom_id(group$name))
    )
    group_ir <- ir
    group_ir$inputs <- group$input_args
    group_ir$outputs <- group$output_targets
    group_ir$path <- file.path(ir$path, sanitize_dom_id(group$name))

    group_analysis <- structure(
      list(
        graph = analysis$graph,
        tool_groups = list(group),
        warnings = analysis$warnings
      ),
      class = "ReactiveAnalysis"
    )

    generate_mcp_app(group_analysis, group_ir, group_dir)
  }
}

#' @noRd
build_card_ui <- function(
  group,
  max_inputs_per_card = 5,
  compact_layout = TRUE
) {
  visible_inputs <- group$input_args
  input_note <- NULL

  if (length(visible_inputs) > max_inputs_per_card) {
    input_note <- htmltools::tags$p(
      class = "shinymcp-card-note",
      sprintf(
        "Scaffold note: %d inputs were detected; review this group for chat-friendly simplification.",
        length(visible_inputs)
      )
    )
  }

  input_tags <- lapply(visible_inputs, build_card_input_component)
  output_tags <- lapply(group$output_targets, build_card_output_component)

  gap <- if (isTRUE(compact_layout)) "12px" else "18px"
  plot_height <- if (isTRUE(compact_layout)) "220px" else "320px"

  htmltools::tagList(
    htmltools::tags$style(htmltools::HTML(paste(
      ".shinymcp-converted-card { display: flex; flex-direction: column; gap:",
      gap,
      "; }",
      ".shinymcp-converted-card-header h2 { margin: 0; font-size: 1rem; }",
      ".shinymcp-converted-card-note { margin: 0; color: #6a7280; font-size: 0.85rem; }",
      ".shinymcp-converted-card-outputs { display: flex; flex-direction: column; gap:",
      gap,
      "; }",
      ".shinymcp-converted-card .shinymcp-output[data-shinymcp-output-type='plot'] { min-height:",
      plot_height,
      "; }"
    ))),
    htmltools::tags$div(
      class = "shinymcp-converted-card",
      htmltools::tags$div(
        class = "shinymcp-converted-card-header",
        htmltools::tags$h2(group$description)
      ),
      input_note,
      input_tags,
      htmltools::tags$div(
        class = "shinymcp-converted-card-outputs",
        output_tags
      )
    )
  )
}

#' @noRd
build_card_input_component <- function(inp) {
  id <- inp$id
  label <- inp$label %||% inp$id

  switch(
    inp$type,
    select = ,
    selectize = mcp_select(id, label, extract_choices_value(inp$args)),
    text = ,
    textArea = ,
    password = mcp_text_input(
      id,
      label,
      value = extract_literal_arg(inp$args, "value", "")
    ),
    numeric = mcp_numeric_input(
      id,
      label,
      value = extract_literal_arg(inp$args, "value", 0),
      min = extract_literal_arg(inp$args, "min", NA),
      max = extract_literal_arg(inp$args, "max", NA)
    ),
    checkbox = mcp_checkbox(
      id,
      label,
      value = isTRUE(extract_literal_arg(inp$args, "value", FALSE))
    ),
    slider = mcp_slider(
      id,
      label,
      min = extract_literal_arg(inp$args, "min", 0),
      max = extract_literal_arg(inp$args, "max", 100),
      value = extract_literal_arg(
        inp$args,
        "value",
        extract_literal_arg(inp$args, "min", 0)
      )
    ),
    radio = mcp_radio(id, label, extract_choices_value(inp$args)),
    action = ,
    actionButton = ,
    actionLink = mcp_action_button(id, label),
    mcp_text_input(id, label)
  )
}

#' @noRd
build_card_output_component <- function(out) {
  switch(
    out$type,
    plot = ,
    image = mcp_plot(out$id, height = "220px"),
    text = ,
    verbatimText = mcp_text(out$id),
    table = ,
    dataTable = mcp_table(out$id),
    html = ,
    ui = mcp_html(out$id),
    mcp_text(out$id)
  )
}

#' @noRd
build_scaffold_tool <- function(group) {
  props <- setNames(
    lapply(group$input_args, function(inp) {
      list(type = scaffold_input_schema_type(inp$type))
    }),
    vapply(group$input_args, `[[`, character(1), "id")
  )

  list(
    name = group$name,
    description = paste0(group$description, " (scaffold placeholder)"),
    inputSchema = list(
      type = "object",
      properties = props
    ),
    fun = function(...) {
      scaffold_tool_outputs(group, list(...))
    }
  )
}

#' @noRd
scaffold_input_schema_type <- function(type) {
  switch(
    type,
    numeric = ,
    slider = "number",
    checkbox = "boolean",
    "string"
  )
}

#' @noRd
scaffold_tool_outputs <- function(group, args) {
  arg_text <- if (length(args) > 0) {
    # Inputs such as multi-select, slider ranges, and checkbox groups deliver
    # length > 1 values, so format each argument with a length-safe collapse.
    formatted <- vapply(
      args,
      function(v) paste(format(v), collapse = ", "),
      character(1)
    )
    paste(sprintf("%s=%s", names(args), formatted), collapse = ", ")
  } else {
    "defaults"
  }

  outputs <- list()
  for (out in group$output_targets) {
    note <- paste(
      "Scaffold placeholder for",
      out$id,
      "from",
      group$name,
      "with",
      arg_text
    )

    outputs[[out$id]] <- switch(
      out$type,
      plot = ,
      image = mcp_result_plot(
        function() {
          graphics::plot.new()
          graphics::text(0.5, 0.5, note, cex = 0.9)
        },
        text = note
      ),
      table = ,
      dataTable = mcp_result_table(data.frame(note = note), text = note),
      html = ,
      ui = mcp_result_html(htmltools::tags$div(note), text = note),
      mcp_result_text(note)
    )
  }

  outputs
}

#' @noRd
extract_literal_arg <- function(args, name, default = NULL) {
  value <- args[[name]]
  if (is.null(value)) {
    return(default)
  }
  if (is.atomic(value) && length(value) == 1) {
    return(value)
  }
  if (is.language(value)) {
    evaluated <- tryCatch(
      eval(value, envir = baseenv()),
      error = function(...) NULL
    )
    if (!is.null(evaluated)) {
      return(evaluated)
    }
  }
  default
}

#' @noRd
extract_choices_value <- function(args) {
  choices <- extract_literal_arg(args, "choices", NULL)
  if (is.null(choices)) {
    return(c("option1", "option2"))
  }
  choices
}
