# Tool results
#
# A tool's return value has two audiences. The model reads text and compact
# data; the app's UI renders HTML, tables, and images. An MCP tool result has
# room for both, so shinymcp fills three places:
#
#   content            text for the model and for hosts without MCP Apps,
#                      plus plot images the model can look at
#   structuredContent  the model-facing value of each output, keyed by id
#   _meta              what the UI needs to render each output (HTML, PNG
#                      data, dependencies), under "shinymcp/view", which
#                      hosts pass to the app but do not show the model
#
# The typed constructors below let a tool say what each output is and what
# the model should see for it.

# ---- Typed outputs ----

#' @noRd
new_mcp_result <- function(kind, value, model_value = NULL, text = NULL, ...) {
  structure(
    list(
      kind = kind,
      value = value,
      model_value = model_value,
      text = text,
      options = list(...)
    ),
    class = "shinymcp_result"
  )
}

#' @noRd
is_mcp_result <- function(x) {
  inherits(x, "shinymcp_result")
}

#' Typed output values for tool results
#'
#' @description
#' A tool that feeds an app returns a named list: one element per output,
#' named by the output's id. Plain values work (a string for [mcp_text()], a
#' data frame for [mcp_table()]), but the typed constructors say more:
#'
#' * `mcp_result_text()`: text, rendered in a `<pre>` by [mcp_text()].
#' * `mcp_result_html()`: HTML or an htmltools tag.
#' * `mcp_result_table()`: a data frame, rendered as an HTML table.
#' * `mcp_result_plot()`: a plot, rendered to PNG.
#' * `mcp_result_image()`: an image file or raw PNG/JPEG data.
#' * `mcp_result_pdf()`: a PDF the user can download from the app.
#' * `mcp_result_widget()`: an htmlwidget or other tag with JavaScript
#'   dependencies, such as a plotly chart.
#'
#' Each takes a `model_value`, the value the model sees for this output in
#' the tool result's structured content, and a `text`, the plain-text
#' version used when the model or host can only read text. The defaults are
#' sensible (a table's rows, a plot's description), so set them when the
#' model needs something more specific: identifiers, a decision, the numbers
#' behind a chart.
#'
#' @param value,html,data,plot,path_or_data,ui The content to render.
#' @param model_value What the model sees for this output. Defaults to the
#'   text for text and HTML outputs, the rows for tables, and `text` for
#'   plots, images, PDFs, and widgets.
#' @param text Plain-text version of the output.
#' @param width,height Plot size in CSS pixels.
#' @param res Plot resolution in pixels per inch at 1x.
#' @param scale Pixel density multiplier; `2` gives sharp plots on high
#'   density screens at four times the file size.
#' @param filename File name offered when the user downloads a PDF.
#' @return A typed output value, to be returned from a tool inside a named
#'   list or on its own.
#' @family tool results
#' @examples
#' summarise_cars <- function(cyl = 4) {
#'   cars <- mtcars[mtcars$cyl == cyl, ]
#'   list(
#'     summary = mcp_result_text(
#'       paste(nrow(cars), "cars with", cyl, "cylinders"),
#'       model_value = list(cyl = cyl, n = nrow(cars))
#'     ),
#'     cars = mcp_result_table(head(cars)),
#'     scatter = mcp_result_plot(
#'       function() plot(cars$wt, cars$mpg),
#'       text = "Weight against fuel economy"
#'     )
#'   )
#' }
#' @name mcp_result
NULL

#' @rdname mcp_result
#' @export
mcp_result_text <- function(value, model_value = NULL, text = NULL) {
  value <- paste(as.character(value), collapse = "\n")
  new_mcp_result("text", value, model_value, text %||% value)
}

#' @rdname mcp_result
#' @export
mcp_result_html <- function(html, model_value = NULL, text = NULL) {
  new_mcp_result("html", html, model_value, text)
}

#' @rdname mcp_result
#' @export
mcp_result_table <- function(data, model_value = NULL, text = NULL) {
  new_mcp_result("table", data, model_value, text)
}

#' @rdname mcp_result
#' @export
mcp_result_plot <- function(
  plot,
  model_value = NULL,
  text = NULL,
  width = 800,
  height = 500,
  res = 96,
  scale = getOption("shinymcp.plot_scale", 1.5)
) {
  new_mcp_result(
    "plot",
    plot,
    model_value,
    text,
    width = width,
    height = height,
    res = res,
    scale = scale
  )
}

#' @rdname mcp_result
#' @export
mcp_result_image <- function(path_or_data, model_value = NULL, text = NULL) {
  new_mcp_result("image", path_or_data, model_value, text)
}

#' @rdname mcp_result
#' @export
mcp_result_pdf <- function(
  path_or_data,
  model_value = NULL,
  text = NULL,
  filename = NULL
) {
  new_mcp_result("pdf", path_or_data, model_value, text, filename = filename)
}

#' @rdname mcp_result
#' @export
mcp_result_widget <- function(ui, model_value = NULL, text = NULL) {
  new_mcp_result("widget", ui, model_value, text)
}

#' Set a tool result's text and data explicitly
#'
#' By default the text a model reads from a tool result is assembled from the
#' outputs, and the structured content is each output's model value. Wrap a
#' tool's outputs in `mcp_tool_result()` to write those yourself, for example
#' to lead with record identifiers the model should quote back:
#'
#' ```r
#' mcp_tool_result(
#'   proposal = mcp_result_table(batches),
#'   text = "Proposal P-3 drafted for campaign C-014: six batches.",
#'   data = list(campaign = "C-014", proposal = "P-3", revision = 47)
#' )
#' ```
#'
#' @param ... Outputs, named by output id, as in a tool's usual return list.
#' @param text Text for the model and for hosts that only show text. Replaces
#'   the text assembled from the outputs.
#' @param data A named list sent as the result's structured content. Replaces
#'   the default of one entry per output.
#' @param error If `TRUE`, the result is marked as a tool error. Use it for
#'   failures the model should see and react to.
#' @return An object a tool can return.
#' @family tool results
#' @export
mcp_tool_result <- function(..., text = NULL, data = NULL, error = FALSE) {
  outputs <- list(...)
  if (
    length(outputs) && (is.null(names(outputs)) || any(!nzchar(names(outputs))))
  ) {
    shinymcp_abort(
      "Outputs passed to {.fn mcp_tool_result} must be named by output id.",
      class = "shinymcp_error_validation"
    )
  }
  if (!is.null(text)) {
    text <- paste(as.character(text), collapse = "\n")
  }
  structure(
    list(outputs = outputs, text = text, data = data, error = isTRUE(error)),
    class = "shinymcp_tool_result"
  )
}

#' @noRd
is_tool_result <- function(x) {
  inherits(x, "shinymcp_tool_result")
}

# ---- Resolving values into outputs ----

#' Resolve a value into a rendered output entry
#'
#' @param value A typed result or plain R value.
#' @param skip_deps Dependencies ("name@version") the view already has.
#' @return A list with `kind`, `render` (payload for the view), `model`
#'   (model-facing value), `text`, and optionally `image` and `deps`.
#' @noRd
resolve_output <- function(value, skip_deps = character(), hint = NULL) {
  if (!is_mcp_result(value)) {
    value <- as_typed_result(value, hint)
  }
  kind <- value$kind
  out <- switch(
    kind,
    text = list(
      kind = "text",
      render = value$value,
      model = value$model_value %||% value$value,
      text = value$text %||% value$value
    ),
    html = resolve_html_output(value, skip_deps),
    widget = resolve_html_output(value, skip_deps, kind = "widget"),
    table = resolve_table_output(value),
    plot = resolve_plot_output(value),
    image = resolve_image_output(value),
    pdf = resolve_pdf_output(value),
    json = list(
      kind = "text",
      render = value$text,
      model = value$model_value %||% value$value,
      text = value$text
    ),
    shinymcp_abort(
      "Unknown output kind {.val {kind}}.",
      class = "shinymcp_error_validation"
    )
  )
  out
}

#' Classify a plain R value returned by a tool
#'
#' `hint` is the type of the UI placeholder the value goes to, if known: a
#' base64 string headed for an `mcp_plot()` is an image, not text.
#' @noRd
as_typed_result <- function(x, hint = NULL) {
  if (is.null(x)) {
    return(new_mcp_result("text", "", NULL, ""))
  }
  if (is.data.frame(x) || is.matrix(x)) {
    return(mcp_result_table(x))
  }
  if (inherits(x, "htmlwidget")) {
    return(mcp_result_widget(x))
  }
  if (inherits(x, c("shiny.tag", "shiny.tag.list", "html"))) {
    return(mcp_result_html(x))
  }
  if (inherits(x, c("ggplot", "recordedplot", "trellis"))) {
    return(mcp_result_plot(x))
  }
  if (is.character(x)) {
    if (
      length(hint) == 1 &&
        hint %in% c("plot", "image") &&
        looks_like_image_data(x)
    ) {
      return(mcp_result_image(x))
    }
    return(mcp_result_text(x))
  }
  if (is.atomic(x)) {
    text <- if (length(x) == 1) format(x) else paste(format(x), collapse = ", ")
    return(new_mcp_result("text", text, unclass(x), text))
  }
  text <- paste(
    utils::capture.output(utils::str(x, give.attr = FALSE)),
    collapse = "\n"
  )
  new_mcp_result("json", x, x, text)
}

#' @noRd
resolve_html_output <- function(value, skip_deps, kind = "html") {
  rendered <- render_html_payload(value$value, skip_deps)
  text <- value$text %||% html_to_text(rendered$html)
  list(
    kind = kind,
    render = rendered$html,
    deps = rendered$deps,
    model = value$model_value %||% text,
    text = text
  )
}

#' @noRd
resolve_table_output <- function(value) {
  data <- value$value
  if (is.character(data) && length(data) == 1) {
    text <- value$text %||% html_to_text(data)
    return(list(
      kind = "table",
      render = data,
      model = value$model_value %||% text,
      text = text
    ))
  }
  data <- as_data_frame_safely(data)
  if (is.null(data)) {
    text <- paste(utils::capture.output(print(value$value)), collapse = "\n")
    return(list(
      kind = "text",
      render = text,
      model = value$model_value %||% text,
      text = value$text %||% text
    ))
  }
  list(
    kind = "table",
    render = render_table_html(data),
    model = value$model_value %||% table_records(data),
    text = value$text %||% table_text(data)
  )
}

#' @noRd
resolve_plot_output <- function(value) {
  opts <- value$options
  png <- render_plot_png(
    value$value,
    width = opts$width %||% 800,
    height = opts$height %||% 500,
    res = opts$res %||% 96,
    scale = opts$scale %||% 1.5
  )
  text <- value$text %||% "A plot."
  list(
    kind = "plot",
    render = list(
      src = paste0("data:image/png;base64,", png),
      width = opts$width %||% 800,
      height = opts$height %||% 500,
      alt = text
    ),
    image = list(data = png, mimeType = "image/png"),
    model = value$model_value %||% text,
    text = text
  )
}

#' @noRd
resolve_image_output <- function(value) {
  img <- read_binary_input(value$value, default_mime = "image/png")
  text <- value$text %||% "An image."
  list(
    kind = "image",
    render = list(
      src = paste0("data:", img$mime, ";base64,", img$data),
      alt = text
    ),
    image = if (
      img$mime %in% c("image/png", "image/jpeg", "image/gif", "image/webp")
    ) {
      list(data = img$data, mimeType = img$mime)
    },
    model = value$model_value %||% text,
    text = text
  )
}

#' @noRd
resolve_pdf_output <- function(value) {
  pdf <- read_binary_input(value$value, default_mime = "application/pdf")
  filename <- value$options$filename %||%
    (if (
      is.character(value$value) &&
        length(value$value) == 1 &&
        file.exists(value$value)
    ) {
      basename(value$value)
    }) %||%
    "document.pdf"
  text <- value$text %||% paste0("A PDF, ", filename, ".")
  list(
    kind = "download",
    render = list(
      filename = filename,
      mimeType = "application/pdf",
      data = pdf$data,
      label = paste("Download", filename)
    ),
    model = value$model_value %||% text,
    text = text
  )
}

#' Is a string a data URI or base64 of a PNG, JPEG, GIF, or WebP image?
#' @noRd
looks_like_image_data <- function(x) {
  is.character(x) &&
    length(x) == 1 &&
    !is.na(x) &&
    (startsWith(x, "data:image/") ||
      (nchar(x) > 64 && !is.na(sniff_image_mime(x))))
}

#' The image type of base64 data, from its first bytes
#' @noRd
sniff_image_mime <- function(x) {
  prefixes <- c(
    "iVBORw0KGgo" = "image/png",
    "/9j/" = "image/jpeg",
    "R0lGOD" = "image/gif",
    "UklGR" = "image/webp"
  )
  for (prefix in names(prefixes)) {
    if (startsWith(x, prefix)) {
      return(prefixes[[prefix]])
    }
  }
  NA_character_
}

#' Read a file path, raw vector, or base64 string as base64
#' @noRd
read_binary_input <- function(x, default_mime) {
  if (is.character(x) && length(x) == 1 && file.exists(x)) {
    return(list(data = base64_file(x), mime = mime_type_for(x, default_mime)))
  }
  if (is.raw(x)) {
    return(list(data = base64_raw(x), mime = default_mime))
  }
  if (is.character(x) && length(x) == 1) {
    if (startsWith(x, "data:")) {
      mime <- sub("^data:([^;,]+).*$", "\\1", x)
      return(list(data = sub("^data:[^,]*,", "", x), mime = mime))
    }
    mime <- if (startsWith(default_mime, "image/")) {
      sniff_image_mime(x)
    } else {
      NA_character_
    }
    return(list(data = x, mime = if (is.na(mime)) default_mime else mime))
  }
  shinymcp_abort(
    "Expected a file path, a raw vector, or a base64 string, not {.cls {class(x)}}.",
    class = "shinymcp_error_validation"
  )
}

# ---- Assembling the MCP result ----

#' Build an MCP `CallToolResult` from a tool's return value
#'
#' @param raw What the tool function returned.
#' @param images Whether to add plot and image content blocks for the model.
#' @param skip_deps HTML dependencies the view already loaded.
#' @param view Extra fields for `_meta["shinymcp/view"]` (runtime state).
#' @param output_types Named character vector of the UI's output types, so
#'   plain values can be read the way their placeholder expects.
#' @return A list ready to serialize as a `tools/call` result.
#' @noRd
build_tool_result <- function(
  raw,
  images = TRUE,
  skip_deps = character(),
  view = NULL,
  output_types = NULL
) {
  text <- NULL
  data <- NULL
  error <- FALSE
  if (is_tool_result(raw)) {
    text <- raw$text
    data <- raw$data
    error <- raw$error
    outputs <- raw$outputs
  } else if (is_named_output_list(raw)) {
    outputs <- raw
  } else {
    outputs <- NULL
  }

  if (is.null(outputs)) {
    # A single unnamed value: the view routes it to its only output, whose
    # type says how to read it.
    hint <- if (length(output_types) == 1) output_types[[1]]
    entry <- resolve_output(raw, skip_deps, hint = hint)
    limit <- getOption("shinymcp.max_text_chars", 4000)
    content <- list(text_block(
      text %||% truncate_text(entry$text %||% "", limit)
    ))
    if (images && !is.null(entry$image)) {
      content <- c(content, list(image_block(entry$image)))
    }
    view_meta <- compact_list(c(
      list(result = view_payload(entry)),
      view
    ))
    result <- list(content = content)
    structured <- data %||% single_structured_value(entry)
    if (!is.null(structured)) {
      result$structuredContent <- structured
    }
  } else {
    # Each library once per result: an output skips what earlier ones
    # brought.
    entries <- list()
    for (id in names(outputs)) {
      hint <- if (id %in% names(output_types)) output_types[[id]]
      entry <- resolve_output(outputs[[id]], skip_deps = skip_deps, hint = hint)
      skip_deps <- c(
        skip_deps,
        vapply(entry$deps %||% list(), function(d) d$name, character(1))
      )
      entries[[length(entries) + 1]] <- entry
    }
    names(entries) <- names(outputs)
    content <- list(text_block(text %||% summarize_entries(entries)))
    if (images) {
      for (entry in entries) {
        if (!is.null(entry$image)) {
          content <- c(content, list(image_block(entry$image)))
        }
      }
    }
    view_meta <- compact_list(c(
      list(outputs = lapply(entries, view_payload)),
      view
    ))
    result <- list(
      content = content,
      structuredContent = data %||%
        lapply(entries, function(e) json_safe(e$model))
    )
  }

  if (isTRUE(error)) {
    result$isError <- TRUE
  }
  result[["_meta"]] <- list(`shinymcp/view` = view_meta)
  result
}

#' @noRd
is_named_output_list <- function(x) {
  is.list(x) &&
    !is.data.frame(x) &&
    !is_mcp_result(x) &&
    !inherits(x, c("shiny.tag", "shiny.tag.list", "htmlwidget")) &&
    length(x) > 0 &&
    !is.null(names(x)) &&
    all(nzchar(names(x)))
}

#' @noRd
view_payload <- function(entry) {
  compact_list(list(
    kind = entry$kind,
    value = entry$render,
    deps = if (length(entry$deps)) entry$deps
  ))
}

#' @noRd
single_structured_value <- function(entry) {
  model <- json_safe(entry$model)
  if (is.null(model)) {
    return(NULL)
  }
  # structuredContent must be a JSON object for protocol versions before
  # 2026-07-28; wrap anything that isn't one.
  if (is.list(model) && !is.null(names(model)) && all(nzchar(names(model)))) {
    return(model)
  }
  if (identical(entry$kind, "text") && is.character(model)) {
    return(NULL)
  }
  list(value = model)
}

#' @noRd
text_block <- function(text) {
  list(type = "text", text = as.character(text %||% ""))
}

#' @noRd
image_block <- function(image) {
  list(type = "image", data = image$data, mimeType = image$mimeType)
}

#' Join each output's text into the text the model reads
#' @noRd
summarize_entries <- function(entries) {
  limit <- getOption("shinymcp.max_text_chars", 4000)
  parts <- character()
  for (id in names(entries)) {
    text <- truncate_text(entries[[id]]$text %||% "", limit)
    if (!nzchar(text)) {
      next
    }
    parts <- c(
      parts,
      if (grepl("\n", text, fixed = TRUE)) {
        paste0(id, ":\n", text)
      } else {
        paste0(id, ": ", text)
      }
    )
  }
  paste(parts, collapse = "\n\n")
}

#' @noRd
truncate_text <- function(text, limit) {
  if (is.null(limit) || nchar(text) <= limit) {
    return(text)
  }
  paste0(
    substr(text, 1, limit),
    "\n... [",
    nchar(text) - limit,
    " more characters]"
  )
}

#' Make a model value serializable
#'
#' Data frames become rows; factors and dates become strings; other objects
#' are left to jsonlite.
#' @noRd
json_safe <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (is.data.frame(x)) {
    return(table_records(x))
  }
  if (is.factor(x)) {
    return(as.character(x))
  }
  if (inherits(x, c("Date", "POSIXt"))) {
    return(format(x))
  }
  if (is.list(x) && !inherits(x, "json")) {
    return(lapply(x, json_safe))
  }
  x
}

# ---- Rendering helpers ----

#' @noRd
render_html_payload <- function(x, skip_deps = character()) {
  if (is.character(x) && !inherits(x, "html")) {
    return(list(html = paste(x, collapse = "\n"), deps = list()))
  }
  rendered <- htmltools::renderTags(x)
  deps <- htmltools::resolveDependencies(rendered$dependencies)
  deps <- Filter(function(d) !dependency_loaded(d, skip_deps), deps)
  html <- rendered$html
  if (nzchar(rendered$head %||% "")) {
    html <- paste(rendered$head, html, sep = "\n")
  }
  list(
    html = as.character(html),
    deps = lapply(deps, dependency_payload)
  )
}

#' @noRd
dependency_key <- function(dep) {
  paste0(dep$name, "@", dep$version)
}

#' Does the page already have a dependency of this name?
#'
#' Any version counts, as in htmltools::resolveDependencies(): loading a
#' second copy of a library (jQuery, say) over the first would drop the
#' plugins attached to it.
#' @param loaded Keys ("name@version") the page reported.
#' @noRd
dependency_loaded <- function(dep, loaded) {
  length(loaded) > 0 && dep$name %in% sub("@[^@]*$", "", loaded)
}

#' An HTML dependency as inline markup the view can inject once
#' @noRd
dependency_payload <- function(dep) {
  list(
    name = dep$name,
    version = dep$version,
    head = inline_dependency(dep)
  )
}

#' @noRd
render_table_html <- function(data) {
  limit <- getOption("shinymcp.max_display_rows", 1000)
  shown <- if (nrow(data) > limit) utils::head(data, limit) else data
  header <- htmltools::tags$thead(htmltools::tags$tr(
    lapply(names(shown), htmltools::tags$th)
  ))
  rows <- lapply(seq_len(nrow(shown)), function(i) {
    htmltools::tags$tr(lapply(shown[i, , drop = FALSE], function(cell) {
      htmltools::tags$td(format_cell(cell))
    }))
  })
  table <- htmltools::tags$table(
    class = "table table-sm shinymcp-table",
    header,
    htmltools::tags$tbody(rows)
  )
  note <- if (nrow(data) > limit) {
    htmltools::tags$p(
      class = "shinymcp-table-note",
      sprintf("Showing %d of %d rows.", limit, nrow(data))
    )
  }
  as.character(htmltools::tagList(table, note))
}

#' @noRd
format_cell <- function(x) {
  x <- x[[1]]
  if (is.null(x) || (length(x) == 1 && is.na(x))) {
    return("")
  }
  if (is.numeric(x)) {
    return(format(x, big.mark = ",", scientific = FALSE, trim = TRUE))
  }
  as.character(x)
}

#' Table rows for the model, capped
#' @noRd
table_records <- function(data) {
  limit <- getOption("shinymcp.max_model_rows", 100)
  data <- as.data.frame(data)
  if (nrow(data) > limit) {
    data <- utils::head(data, limit)
  }
  data[] <- lapply(data, function(col) {
    if (is.factor(col) || inherits(col, c("Date", "POSIXt"))) {
      format(col)
    } else {
      col
    }
  })
  if (nrow(data) == 0) {
    return(list())
  }
  unname(lapply(seq_len(nrow(data)), function(i) {
    row <- lapply(data[i, , drop = FALSE], function(v) {
      v <- v[[1]]
      if (length(v) == 1 && is.na(v)) NULL else v
    })
    row
  }))
}

#' @noRd
table_text <- function(data) {
  limit <- getOption("shinymcp.max_model_rows", 100)
  shown <- if (nrow(data) > limit) utils::head(data, limit) else data
  text <- paste(
    utils::capture.output(print(shown, row.names = FALSE)),
    collapse = "\n"
  )
  if (nrow(data) > limit) {
    text <- paste0(text, "\n(", nrow(data) - limit, " more rows)")
  }
  text
}

#' @noRd
as_data_frame_safely <- function(x) {
  if (is.data.frame(x)) {
    return(x)
  }
  tryCatch(as.data.frame(x), error = function(e) NULL)
}

#' Render a plot to base64 PNG
#' @noRd
render_plot_png <- function(
  x,
  width = 800,
  height = 500,
  res = 96,
  scale = 1.5
) {
  if (is.character(x) && length(x) == 1 && file.exists(x)) {
    return(base64_file(x))
  }
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp), add = TRUE)
  grDevices::png(
    tmp,
    width = round(width * scale),
    height = round(height * scale),
    res = res * scale
  )
  device <- grDevices::dev.cur()
  closed <- FALSE
  on.exit(if (!closed) grDevices::dev.off(device), add = TRUE, after = FALSE)
  if (is.function(x)) {
    x()
  } else {
    print(x)
  }
  grDevices::dev.off(device)
  closed <- TRUE
  base64_file(tmp)
}

#' Strip tags from HTML to get readable text
#'
#' Tables become Markdown tables, which models read well.
#' @noRd
html_to_text <- function(html) {
  html <- paste(as.character(html), collapse = "\n")
  html <- gsub("(?is)<(script|style)[^>]*>.*?</\\1>", " ", html, perl = TRUE)
  # Preformatted text keeps its line breaks; set it aside while the rest
  # is reflowed.
  pre <- regmatches(
    html,
    gregexpr("(?is)<pre\\b.*?</pre>", html, perl = TRUE)
  )[[1]]
  for (i in seq_along(pre)) {
    html <- sub(pre[[i]], paste0("\u0001", i, "\u0001"), html, fixed = TRUE)
  }
  html <- tables_to_markdown(html)
  # Line breaks in the source are layout; tags decide where lines break.
  html <- gsub("[ \t]*\n[ \t]*", " ", html, perl = TRUE)
  html <- gsub("[ \t]+", " ", html, perl = TRUE)
  html <- gsub("(?i)<br\\s*/?>", "\n", html, perl = TRUE)
  html <- gsub(
    "(?i)</(p|div|li|tr|h[1-6]|table|ul|ol|section|article)>",
    "\n",
    html,
    perl = TRUE
  )
  html <- gsub(
    "(?i)<(p|div|li|h[1-6]|ul|ol|section|article)\\b[^>]*>",
    "\n",
    html,
    perl = TRUE
  )
  html <- gsub("\u0002", "\n", html, fixed = TRUE)
  for (i in seq_along(pre)) {
    text <- gsub("(?is)^<pre\\b[^>]*>|</pre>$", "", pre[[i]], perl = TRUE)
    html <- sub(
      paste0("\u0001", i, "\u0001"),
      paste0("\n", text, "\n"),
      html,
      fixed = TRUE
    )
  }
  html <- gsub("<[^>]+>", "", html)
  html <- unescape_html(html)
  lines <- strsplit(html, "\n", fixed = TRUE)[[1]]
  lines <- sub("[ \t]+$", "", sub("^[ \t]+(?=\\S)", "", lines, perl = TRUE))
  paste(lines[nzchar(trimws(lines))], collapse = "\n")
}

#' Replace each HTML table with a Markdown table
#' @noRd
tables_to_markdown <- function(html) {
  matches <- gregexpr("(?is)<table\\b.*?</table>", html, perl = TRUE)
  tables <- regmatches(html, matches)[[1]]
  if (length(tables) == 0) {
    return(html)
  }
  regmatches(html, matches) <- list(vapply(
    tables,
    html_table_markdown,
    character(1),
    USE.NAMES = FALSE
  ))
  html
}

#' @noRd
html_table_markdown <- function(table) {
  rows <- regmatches(
    table,
    gregexpr("(?is)<tr\\b.*?</tr>", table, perl = TRUE)
  )[[1]]
  cells <- lapply(rows, function(row) {
    found <- regmatches(
      row,
      gregexpr("(?is)<t[hd]\\b[^>]*>.*?</t[hd]>", row, perl = TRUE)
    )[[1]]
    # Entities stay escaped here: html_to_text() strips tags from the whole
    # text afterwards and only then unescapes, so "&lt; 0.001" survives.
    text <- gsub("(?is)^<t[hd]\\b[^>]*>|</t[hd]>$", "", found, perl = TRUE)
    text <- gsub("<[^>]+>", "", text)
    text <- trimws(gsub("\\s+", " ", text))
    gsub("|", "\\|", text, fixed = TRUE)
  })
  cells <- Filter(length, cells)
  if (length(cells) == 0) {
    return("\u0002")
  }
  width <- max(lengths(cells))
  line <- function(x) {
    x <- c(x, rep("", width - length(x)))
    paste0(
      "|",
      paste0(ifelse(nzchar(x), paste0(" ", x, " "), " "), collapse = "|"),
      "|"
    )
  }
  body <- vapply(cells, line, character(1))
  # U+0002 marks line breaks that survive html_to_text()'s reflow.
  paste0(
    "\u0002",
    paste(c(body[1], line(rep("---", width)), body[-1]), collapse = "\u0002"),
    "\u0002"
  )
}

#' @noRd
unescape_html <- function(x) {
  entities <- c(
    "&lt;" = "<",
    "&gt;" = ">",
    "&quot;" = "\"",
    "&#39;" = "'",
    "&#x27;" = "'",
    "&#10;" = "\n",
    "&#13;" = "\r",
    "&nbsp;" = " ",
    "&amp;" = "&"
  )
  for (e in names(entities)) {
    x <- gsub(e, entities[[e]], x, fixed = TRUE)
  }
  x
}
