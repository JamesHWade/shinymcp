# Inputs of a Shiny UI, described for the live runtime
#
# The runtime needs to know, for every input in the UI, what kind of control
# it is, its default value, and its allowed values. From that it builds the
# JSON Schema of the tool the model calls (select inputs become enums,
# sliders become bounded numbers), sets initial values the way Shiny's
# browser client would, and converts JSON values back into the R values a
# server function expects (dates as Date, action buttons as counters).

#' Describe every input in a Shiny UI
#'
#' @param ui An htmltools tag tree.
#' @return A named list (by input id) of input specs: `id`, `kind`, `label`,
#'   `value` (default, as Shiny delivers it), and kind-specific fields
#'   (`choices`, `choice_labels`, `min`, `max`, `step`, `data_type`), plus
#'   `bound` (annotated with [bindMcp()]).
#' @noRd
describe_ui_inputs <- function(ui) {
  specs <- list()
  add <- function(spec) {
    if (!is.null(spec) && is_string(spec$id) && is.null(specs[[spec$id]])) {
      specs[[spec$id]] <<- spec
    }
  }
  visit <- function(x) {
    if (inherits(x, "shiny.tag")) {
      spec <- describe_input_tag(x)
      if (!is.null(spec)) {
        spec$bound <- tag_is_bound(x, spec$id)
        add(spec)
        if (isTRUE(spec$container)) {
          # Radio groups, checkbox groups and date inputs: the inner <input>s
          # belong to this container, not to inputs of their own.
          return(invisible())
        }
      }
      for (child in x$children) {
        visit(child)
      }
    } else if (
      inherits(x, "shiny.tag.list") ||
        (is.list(x) && !inherits(x, "html_dependency"))
    ) {
      for (child in x) {
        visit(child)
      }
    }
    invisible()
  }
  visit(ui)
  specs
}

#' Was an input annotated with bindMcp() or built with an mcp_*() function?
#'
#' The annotation sits on the input element itself or, for containers such
#' as radio groups and date inputs, on an element inside it.
#' @noRd
tag_is_bound <- function(tag, id) {
  own <- htmltools::tagGetAttribute(tag, "data-shinymcp-input")
  if (!is.null(own)) {
    return(TRUE)
  }
  found <- FALSE
  walk_tag_tree(tag$children, function(child) {
    if (
      !found &&
        identical(htmltools::tagGetAttribute(child, "data-shinymcp-input"), id)
    ) {
      found <<- TRUE
    }
  })
  found
}

#' Describe one tag if it is a Shiny input
#' @noRd
describe_input_tag <- function(tag) {
  name <- tolower(tag$name %||% "")
  id <- htmltools::tagGetAttribute(tag, "id")
  classes <- strsplit(
    htmltools::tagGetAttribute(tag, "class") %||% "",
    "\\s+"
  )[[1]]
  has_class <- function(cls) cls %in% classes

  # shinymcp's own radio group carries its id in data attributes.
  if (
    identical(htmltools::tagGetAttribute(tag, "data-shinymcp-type"), "radio")
  ) {
    id <- htmltools::tagGetAttribute(tag, "data-shinymcp-input")
    opts <- group_options(tag, "radio")
    return(new_input_spec(
      id,
      "radio",
      tag,
      choices = opts$values,
      choice_labels = opts$labels,
      value = if (length(opts$checked)) opts$checked[[1]],
      container = TRUE
    ))
  }

  if (is.null(id)) {
    return(NULL)
  }

  if (
    name == "input" &&
      identical(
        tolower(htmltools::tagGetAttribute(tag, "type") %||% ""),
        "range"
      )
  ) {
    return(new_input_spec(
      id,
      "slider",
      tag,
      value = as_number_or_null(htmltools::tagGetAttribute(tag, "value")),
      min = as_number_or_null(htmltools::tagGetAttribute(tag, "min")),
      max = as_number_or_null(htmltools::tagGetAttribute(tag, "max")),
      step = as_number_or_null(htmltools::tagGetAttribute(tag, "step")),
      data_type = "number"
    ))
  }

  if (has_class("shiny-input-radiogroup")) {
    opts <- group_options(tag, "radio")
    return(new_input_spec(
      id,
      "radio",
      tag,
      choices = opts$values,
      choice_labels = opts$labels,
      value = if (length(opts$checked)) opts$checked[[1]],
      container = TRUE
    ))
  }
  if (has_class("shiny-input-checkboxgroup")) {
    opts <- group_options(tag, "checkbox")
    return(new_input_spec(
      id,
      "checkbox-group",
      tag,
      choices = opts$values,
      choice_labels = opts$labels,
      value = if (length(opts$checked)) opts$checked,
      container = TRUE
    ))
  }
  if (has_class("shiny-date-range-input")) {
    inputs <- find_tags(tag, "input")
    dates <- vapply(
      inputs,
      function(t) {
        htmltools::tagGetAttribute(t, "data-initial-date") %||% NA_character_
      },
      character(1)
    )
    first <- if (length(inputs)) inputs[[1]] else NULL
    return(new_input_spec(
      id,
      "date-range",
      tag,
      value = parse_initial_dates(dates, 2),
      min = attr_or_null(first, "data-min-date"),
      max = attr_or_null(first, "data-max-date"),
      container = TRUE
    ))
  }
  if (has_class("shiny-date-input")) {
    inputs <- find_tags(tag, "input")
    first <- if (length(inputs)) inputs[[1]] else NULL
    initial <- attr_or_null(first, "data-initial-date")
    return(new_input_spec(
      id,
      "date",
      tag,
      value = parse_initial_dates(initial %||% NA_character_, 1),
      min = attr_or_null(first, "data-min-date"),
      max = attr_or_null(first, "data-max-date"),
      container = TRUE
    ))
  }

  if (name == "select") {
    opts <- select_options(tag)
    multiple <- !is.null(htmltools::tagGetAttribute(tag, "multiple"))
    value <- if (length(opts$selected)) {
      opts$selected
    } else if (!multiple && length(opts$values)) {
      opts$values[[1]]
    }
    return(new_input_spec(
      id,
      if (multiple) "select-multiple" else "select",
      tag,
      choices = opts$values,
      choice_labels = opts$labels,
      value = if (!multiple && length(value)) value[[1]] else value
    ))
  }

  if (name == "textarea") {
    return(new_input_spec(
      id,
      "textarea",
      tag,
      value = paste(unlist(Filter(is.character, tag$children)), collapse = "")
    ))
  }

  if (name == "input") {
    type <- tolower(htmltools::tagGetAttribute(tag, "type") %||% "text")
    if (has_class("js-range-slider")) {
      return(describe_slider(tag, id))
    }
    return(switch(
      type,
      checkbox = new_input_spec(
        id,
        "checkbox",
        tag,
        value = !is.null(htmltools::tagGetAttribute(tag, "checked"))
      ),
      number = new_input_spec(
        id,
        "number",
        tag,
        value = as_number_or_na(htmltools::tagGetAttribute(tag, "value")),
        min = as_number_or_null(htmltools::tagGetAttribute(tag, "min")),
        max = as_number_or_null(htmltools::tagGetAttribute(tag, "max")),
        step = as_number_or_null(htmltools::tagGetAttribute(tag, "step"))
      ),
      password = new_input_spec(id, "password", tag, value = ""),
      file = new_input_spec(id, "file", tag, value = NULL),
      radio = NULL,
      date = new_input_spec(
        id,
        "date",
        tag,
        value = parse_initial_dates(
          htmltools::tagGetAttribute(tag, "value") %||% NA_character_,
          1
        )
      ),
      new_input_spec(
        id,
        "text",
        tag,
        value = htmltools::tagGetAttribute(tag, "value") %||% ""
      )
    ))
  }

  if (name %in% c("button", "a") && has_class("action-button")) {
    return(new_input_spec(
      id,
      "action",
      tag,
      value = action_value(0L),
      label = trimws(tag_text(tag))
    ))
  }

  NULL
}

#' @noRd
new_input_spec <- function(id, kind, tag, value = NULL, label = NULL, ...) {
  spec <- list(
    id = id,
    kind = kind,
    label = label %||% input_label(tag, id),
    value = value,
    ...
  )
  spec
}

#' @noRd
describe_slider <- function(tag, id) {
  attr <- function(nm) htmltools::tagGetAttribute(tag, nm)
  data_type <- attr("data-data-type") %||% "number"
  range <- identical(attr("data-type"), "double")
  convert <- function(x) {
    x <- as_number_or_null(x)
    if (is.null(x)) {
      return(NULL)
    }
    slider_value_from_number(x, data_type, attr("data-time-zone"))
  }
  from <- convert(attr("data-from"))
  to <- convert(attr("data-to"))
  new_input_spec(
    id,
    if (range) "slider-range" else "slider",
    tag,
    value = if (range) c(from, to) else from,
    min = convert(attr("data-min")),
    max = convert(attr("data-max")),
    step = as_number_or_null(attr("data-step")),
    data_type = data_type
  )
}

#' Slider values for dates travel as milliseconds since the epoch
#' @noRd
slider_value_from_number <- function(x, data_type, tz = NULL) {
  switch(
    data_type,
    date = as.Date(as.POSIXct(x / 1000, origin = "1970-01-01", tz = "UTC")),
    datetime = as.POSIXct(x / 1000, origin = "1970-01-01", tz = tz %||% ""),
    x
  )
}

#' @noRd
input_label <- function(tag, id) {
  labels <- find_tags(tag, "label")
  for (label in labels) {
    target <- htmltools::tagGetAttribute(label, "for")
    if (is.null(target) || identical(target, id)) {
      text <- trimws(tag_text(label))
      if (nzchar(text)) {
        return(text)
      }
    }
  }
  NULL
}

#' Options of a radio or checkbox group
#' @noRd
group_options <- function(tag, type) {
  inputs <- Filter(
    function(t) {
      identical(tolower(htmltools::tagGetAttribute(t, "type") %||% ""), type)
    },
    find_tags(tag, "input")
  )
  values <- vapply(
    inputs,
    function(t) htmltools::tagGetAttribute(t, "value") %||% "",
    character(1)
  )
  checked <- values[vapply(
    inputs,
    function(t) !is.null(htmltools::tagGetAttribute(t, "checked")),
    logical(1)
  )]
  labels <- values
  # Labels sit in the <label> that wraps each input.
  wrappers <- find_tags(tag, "label")
  for (w in wrappers) {
    inner <- Filter(
      function(t) {
        identical(tolower(htmltools::tagGetAttribute(t, "type") %||% ""), type)
      },
      find_tags(w, "input")
    )
    if (length(inner) == 1) {
      v <- htmltools::tagGetAttribute(inner[[1]], "value") %||% ""
      text <- trimws(tag_text(w))
      if (nzchar(text) && v %in% values) {
        labels[match(v, values)] <- text
      }
    }
  }
  list(
    values = unname(values),
    labels = unname(labels),
    checked = unname(checked)
  )
}

#' Options of a <select>
#' @noRd
select_options <- function(tag) {
  values <- character()
  labels <- character()
  selected <- character()
  walk <- function(x) {
    if (inherits(x, "shiny.tag")) {
      if (identical(tolower(x$name), "option")) {
        value <- htmltools::tagGetAttribute(x, "value") %||% trimws(tag_text(x))
        values <<- c(values, value)
        labels <<- c(labels, trimws(tag_text(x)))
        if (!is.null(htmltools::tagGetAttribute(x, "selected"))) {
          selected <<- c(selected, value)
        }
      } else {
        for (child in x$children) {
          walk(child)
        }
      }
    } else if (is.character(x)) {
      # selectInput() writes its options as an HTML string.
      parsed <- html_options(paste(x, collapse = ""))
      values <<- c(values, parsed$values)
      labels <<- c(labels, parsed$labels)
      selected <<- c(selected, parsed$selected)
    } else if (is.list(x) && !inherits(x, "html_dependency")) {
      for (child in x) {
        walk(child)
      }
    }
  }
  walk(tag$children)
  list(
    values = unname(values),
    labels = unname(labels),
    selected = unname(selected)
  )
}

#' `<option>` elements in an HTML string
#' @noRd
html_options <- function(html) {
  empty <- list(
    values = character(),
    labels = character(),
    selected = character()
  )
  if (!nzchar(html) || !grepl("<option", html, ignore.case = TRUE)) {
    return(empty)
  }
  matches <- regmatches(
    html,
    gregexpr(
      "<option\\b([^>]*)>(.*?)</option>",
      html,
      perl = TRUE,
      ignore.case = TRUE
    )
  )[[1]]
  if (length(matches) == 0) {
    return(empty)
  }
  attrs <- sub(
    "^<option\\b([^>]*)>.*$",
    "\\1",
    matches,
    perl = TRUE,
    ignore.case = TRUE
  )
  labels <- unescape_html(trimws(gsub(
    "<[^>]*>",
    "",
    sub(
      "^<option\\b[^>]*>(.*?)</option>$",
      "\\1",
      matches,
      perl = TRUE,
      ignore.case = TRUE
    )
  )))
  values <- vapply(
    seq_along(attrs),
    function(i) {
      m <- regmatches(
        attrs[[i]],
        regexec(
          "\\bvalue\\s*=\\s*(\"([^\"]*)\"|'([^']*)')",
          attrs[[i]],
          perl = TRUE
        )
      )[[1]]
      if (length(m) == 0) {
        return(labels[[i]])
      }
      unescape_html(if (nzchar(m[[3]])) m[[3]] else m[[4]])
    },
    character(1)
  )
  is_selected <- grepl("(^|\\s)selected(\\s|=|$)", attrs, perl = TRUE)
  list(values = values, labels = labels, selected = values[is_selected])
}

#' All descendant tags with a given name
#' @noRd
find_tags <- function(tag, name) {
  found <- list()
  walk <- function(x) {
    if (inherits(x, "shiny.tag")) {
      if (identical(tolower(x$name), name)) {
        found[[length(found) + 1]] <<- x
      }
      for (child in x$children) {
        walk(child)
      }
    } else if (is.list(x) && !inherits(x, "html_dependency")) {
      for (child in x) {
        walk(child)
      }
    }
  }
  for (child in tag$children) {
    walk(child)
  }
  found
}

#' Concatenated text of a tag's descendants
#' @noRd
tag_text <- function(tag) {
  out <- character()
  walk <- function(x) {
    if (inherits(x, "shiny.tag")) {
      if (!tolower(x$name) %in% c("script", "style", "input", "select")) {
        for (child in x$children) {
          walk(child)
        }
      }
    } else if (is.character(x)) {
      out <<- c(out, x)
    } else if (is.list(x) && !inherits(x, "html_dependency")) {
      for (child in x) {
        walk(child)
      }
    }
  }
  walk(tag$children)
  gsub("\\s+", " ", paste(out, collapse = " "))
}

#' @noRd
attr_or_null <- function(tag, name) {
  if (is.null(tag)) NULL else htmltools::tagGetAttribute(tag, name)
}

#' @noRd
as_number_or_null <- function(x) {
  if (is.null(x) || !nzchar(x)) {
    return(NULL)
  }
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) NULL else out
}

#' @noRd
as_number_or_na <- function(x) {
  as_number_or_null(x) %||% NA_real_
}

#' Initial dates, with today standing in for missing ones (as Shiny does)
#' @noRd
parse_initial_dates <- function(x, n) {
  x <- rep_len(as.character(x), n)
  out <- suppressWarnings(as.Date(x))
  out[is.na(out)] <- Sys.Date()
  out
}

#' An action button's value as Shiny delivers it
#' @noRd
action_value <- function(n) {
  structure(as.integer(n), class = c("shinyActionButtonValue", "integer"))
}

# ---- JSON Schema for the model-facing tool ----

#' Kinds of input the model can set
#' @noRd
MODEL_INPUT_KINDS <- c(
  "select",
  "select-multiple",
  "radio",
  "checkbox-group",
  "checkbox",
  "number",
  "slider",
  "slider-range",
  "date",
  "date-range",
  "text",
  "textarea"
)

#' JSON Schema for one input, as a tool argument
#' @noRd
input_json_schema <- function(spec) {
  label <- spec$label %||% spec$id
  default <- format_input_default(spec)
  describe <- function(extra = NULL) {
    paste0(
      label,
      if (!is.null(extra)) paste0(" (", extra, ")"),
      if (!is.null(default)) paste0(". Default: ", default, ".") else "."
    )
  }
  choices <- spec$choices
  enum_ok <- length(choices) > 0 && length(choices) <= 200
  choice_hint <- function() {
    if (length(choices) == 0 || enum_ok) {
      return(NULL)
    }
    paste0(
      "one of ",
      length(choices),
      " values, e.g. ",
      paste(utils::head(choices, 5), collapse = ", ")
    )
  }
  bounds <- function(prefix = NULL) {
    parts <- c(
      if (!is.null(spec$min)) paste("min", format_input_scalar(spec$min)),
      if (!is.null(spec$max)) paste("max", format_input_scalar(spec$max))
    )
    if (length(parts)) paste(c(prefix, parts), collapse = ", ") else prefix
  }
  numeric_bounds <- function(schema) {
    if (is.numeric(spec$min)) {
      schema$minimum <- spec$min
    }
    if (is.numeric(spec$max)) {
      schema$maximum <- spec$max
    }
    schema
  }

  switch(
    spec$kind,
    select = ,
    radio = compact_list(list(
      type = "string",
      enum = if (enum_ok) I(choices),
      description = describe(choice_hint())
    )),
    "select-multiple" = ,
    "checkbox-group" = list(
      type = "array",
      items = compact_list(list(
        type = "string",
        enum = if (enum_ok) I(choices)
      )),
      description = describe(choice_hint() %||% "any number of values")
    ),
    checkbox = list(type = "boolean", description = describe()),
    number = numeric_bounds(list(
      type = "number",
      description = describe(bounds())
    )),
    slider = if (spec$data_type %in% c("date", "datetime")) {
      list(
        type = "string",
        format = if (spec$data_type == "date") "date" else "date-time",
        description = describe(bounds())
      )
    } else {
      numeric_bounds(list(type = "number", description = describe(bounds())))
    },
    "slider-range" = if (spec$data_type %in% c("date", "datetime")) {
      list(
        type = "array",
        items = list(
          type = "string",
          format = if (spec$data_type == "date") "date" else "date-time"
        ),
        minItems = 2L,
        maxItems = 2L,
        description = describe(bounds("start and end"))
      )
    } else {
      list(
        type = "array",
        items = numeric_bounds(list(type = "number")),
        minItems = 2L,
        maxItems = 2L,
        description = describe(bounds("start and end"))
      )
    },
    date = list(
      type = "string",
      format = "date",
      description = describe(bounds("YYYY-MM-DD"))
    ),
    "date-range" = list(
      type = "array",
      items = list(type = "string", format = "date"),
      minItems = 2L,
      maxItems = 2L,
      description = describe("start and end dates, YYYY-MM-DD")
    ),
    action = list(
      type = "boolean",
      description = paste0(
        "Set to true to press the '",
        label,
        "' button after the other inputs are set."
      )
    ),
    list(type = "string", description = describe())
  )
}

#' @noRd
format_input_default <- function(spec) {
  value <- spec$value
  if (identical(spec$kind, "action") || is.null(value) || length(value) == 0) {
    return(NULL)
  }
  if (length(value) == 1 && is.na(value)) {
    return(NULL)
  }
  if (is.character(value) && length(value) == 1 && !nzchar(value)) {
    return(NULL)
  }
  if (is.logical(value)) {
    return(tolower(as.character(value)))
  }
  paste(vapply(value, format_input_scalar, character(1)), collapse = ", ")
}

#' @noRd
format_input_scalar <- function(x) {
  if (inherits(x, "Date")) {
    return(format(x, "%Y-%m-%d"))
  }
  if (inherits(x, "POSIXt")) {
    return(format(x, "%Y-%m-%dT%H:%M:%S"))
  }
  format(x, scientific = FALSE, trim = TRUE)
}

# ---- Converting JSON values into Shiny input values ----

#' Convert a value from the model or the page into what Shiny delivers
#'
#' @param value Parsed JSON value.
#' @param spec The input spec (from the UI, or a kind hint from the page).
#' @param previous The input's current value (for action buttons).
#' @param strict Check choices and types (for values from the model).
#' @noRd
coerce_input_value <- function(value, spec, previous = NULL, strict = FALSE) {
  kind <- spec$kind %||% "unknown"
  label <- spec$id %||% "input"
  if (is.list(value) && is.null(names(value))) {
    value <- simplify_json_value(value)
  }

  check_choices <- function(x) {
    if (strict && length(spec$choices) && length(x)) {
      bad <- setdiff(as.character(x), spec$choices)
      if (length(bad)) {
        shinymcp_abort(
          c(
            "{.val {bad}} is not a valid value for {.field {label}}.",
            "i" = "Use one of {.val {spec$choices}}."
          ),
          class = "shinymcp_error_arguments"
        )
      }
    }
    x
  }

  switch(
    kind,
    select = ,
    radio = if (length(value) == 0) {
      NULL
    } else {
      check_choices(as.character(unlist(value))[1])
    },
    "select-multiple" = ,
    "checkbox-group" = {
      if (is.null(value) || length(value) == 0) {
        NULL
      } else {
        check_choices(as.character(unlist(value)))
      }
    },
    checkbox = ,
    switch = isTRUE(as.logical(value)),
    number = {
      if (is.null(value) || identical(value, "")) {
        NA_real_
      } else {
        as_number_strict(value, label, strict)
      }
    },
    slider = coerce_slider_value(value, spec, label, strict, n = 1),
    "slider-range" = coerce_slider_value(value, spec, label, strict, n = 2),
    date = {
      if (is.null(value) || identical(value, "")) {
        NULL
      } else {
        as_date_strict(value, label, strict)
      }
    },
    "date-range" = {
      v <- unlist(value)
      if (length(v) == 0) NULL else as_date_strict(rep_len(v, 2), label, strict)
    },
    text = ,
    textarea = ,
    password = if (is.null(value)) {
      ""
    } else {
      paste(as.character(unlist(value)), collapse = "")
    },
    action = {
      current <- as.integer(previous %||% 0L)
      if (is.logical(value)) {
        action_value(current + if (isTRUE(value)) 1L else 0L)
      } else {
        action_value(as.integer(value %||% current))
      }
    },
    file = NULL,
    value
  )
}

#' @noRd
coerce_slider_value <- function(value, spec, label, strict, n) {
  if (is.null(value)) {
    return(spec$value)
  }
  data_type <- spec$data_type %||% "number"
  v <- unlist(value)
  out <- if (data_type == "date") {
    if (is.numeric(v)) {
      slider_value_from_number(v, "date")
    } else {
      as_date_strict(v, label, strict)
    }
  } else if (data_type == "datetime") {
    if (is.numeric(v)) {
      slider_value_from_number(v, "datetime")
    } else {
      as.POSIXct(v, tz = "UTC")
    }
  } else {
    as_number_strict(v, label, strict)
  }
  if (!is.null(spec$min)) {
    out[out < spec$min] <- spec$min
  }
  if (!is.null(spec$max)) {
    out[out > spec$max] <- spec$max
  }
  if (n == 2) {
    out <- sort(rep_len(out, 2))
  } else {
    out <- out[1]
  }
  out
}

#' @noRd
as_number_strict <- function(x, label, strict) {
  out <- suppressWarnings(as.numeric(unlist(x)))
  if (strict && any(is.na(out))) {
    shinymcp_abort(
      "{.field {label}} must be a number, not {.val {x}}.",
      class = "shinymcp_error_arguments"
    )
  }
  out
}

#' @noRd
as_date_strict <- function(x, label, strict) {
  out <- suppressWarnings(as.Date(as.character(unlist(x))))
  if (strict && any(is.na(out))) {
    shinymcp_abort(
      "{.field {label}} must be a date as YYYY-MM-DD, not {.val {x}}.",
      class = "shinymcp_error_arguments"
    )
  }
  out
}

#' Shiny input values as JSON the page can show
#' @noRd
input_value_for_page <- function(value) {
  if (is.null(value)) {
    return(NULL)
  }
  if (inherits(value, "shinyActionButtonValue")) {
    return(as.integer(unclass(value)))
  }
  if (inherits(value, "Date")) {
    out <- format(value, "%Y-%m-%d")
    return(if (length(out) == 1) out else I(out))
  }
  if (inherits(value, "POSIXt")) {
    out <- format(value, "%Y-%m-%dT%H:%M:%S")
    return(if (length(out) == 1) out else I(out))
  }
  if (is.atomic(value) && length(value) > 1) {
    return(I(unclass(value)))
  }
  if (is.atomic(value) && length(value) == 1 && is.na(value)) {
    return(NULL)
  }
  unclass(value)
}
