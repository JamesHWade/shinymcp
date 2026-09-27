# Inputs for apps built from tools
#
# Plain HTML controls with data-shinymcp-* attributes, which the bridge
# reads. Shiny's and bslib's own inputs work too; these need neither.

#' Mark an element as an input of an app's tools
#'
#' In an app built with [mcp_app()], a tool's argument takes its value from
#' the input whose id matches the argument's name. Shiny's and bslib's
#' inputs are found that way on their own. `mcp_input()` marks anything
#' else: an element whose id differs from the argument name, or a form
#' element shinymcp doesn't recognize.
#'
#' @param tag A tag or tag list. The mark goes on the tag if it is a form
#'   element or an input group (radio buttons, a date input), otherwise on
#'   the first one inside it.
#' @param id The tool argument the element feeds. Defaults to the element's
#'   own id.
#' @return `tag`, marked.
#' @family components
#' @export
#' @examples
#' mcp_input(htmltools::tags$input(id = "q", type = "search"), id = "query")
mcp_input <- function(tag, id = NULL) {
  if (inherits(tag, "shiny.tag") && is_input_element(tag)) {
    return(stamp_input(tag, id %||% htmltools::tagGetAttribute(tag, "id")))
  }

  # Otherwise the first input inside it. Groups (radio buttons, checkbox
  # groups, date inputs) are matched as a whole, before the <input>s inside
  # them.
  tq <- htmltools::tagQuery(tag)
  for (selector in c(
    INPUT_GROUP_SELECTORS,
    "select",
    "input",
    "textarea",
    "button"
  )) {
    found <- tq$find(selector)
    if (found$length() > 0) {
      first <- found$selectedTags()[[1]]
      resolved <- id %||% htmltools::tagGetAttribute(first, "id")
      check_input_id(resolved)
      found$filter(function(x, i) i == 1)$addAttrs(
        `data-shinymcp-input` = resolved
      )
      return(tq$allTags())
    }
  }

  if (!inherits(tag, "shiny.tag")) {
    shinymcp_abort(
      "Couldn't find an input in {.arg tag}.",
      class = "shinymcp_error_validation"
    )
  }
  stamp_input(tag, id %||% htmltools::tagGetAttribute(tag, "id"))
}

#' Shiny inputs whose value belongs to a container, not an <input>
#' @noRd
INPUT_GROUP_SELECTORS <- c(
  ".shiny-input-radiogroup",
  ".shiny-input-checkboxgroup",
  ".shiny-date-input",
  ".shiny-date-range-input",
  ".shiny-tab-input"
)

#' @noRd
is_input_element <- function(tag) {
  if (
    tolower(tag$name %||% "") %in% c("input", "select", "textarea", "button")
  ) {
    return(TRUE)
  }
  classes <- strsplit(
    htmltools::tagGetAttribute(tag, "class") %||% "",
    "\\s+"
  )[[1]]
  any(sub("^\\.", "", INPUT_GROUP_SELECTORS) %in% classes)
}

#' @noRd
stamp_input <- function(tag, id) {
  check_input_id(id)
  htmltools::tagAppendAttributes(tag, `data-shinymcp-input` = id)
}

#' @noRd
check_input_id <- function(id, call = rlang::caller_env()) {
  if (!is_string(id)) {
    shinymcp_abort(
      "Can't tell which input this is. Supply {.arg id}, or give the element an {.field id} attribute.",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  invisible(id)
}

#' Mark an element as an output of an app's tools
#'
#' A tool fills the outputs whose ids match the names of the list it
#' returns. [mcp_text()], [mcp_plot()] and the other output functions make
#' those elements; `mcp_output()` turns any element into one.
#'
#' @param tag A tag.
#' @param id The output id. Defaults to the element's own id.
#' @param type How to show the value: `"text"`, `"html"`, `"plot"`,
#'   `"table"`, `"image"`, or `"widget"`.
#' @return `tag`, marked.
#' @family components
#' @export
#' @examples
#' mcp_output(htmltools::div(class = "summary-card"), id = "summary", type = "html")
mcp_output <- function(
  tag,
  id = NULL,
  type = c("text", "html", "plot", "table", "image", "widget")
) {
  type <- rlang::arg_match(type)
  resolved_id <- id %||% htmltools::tagGetAttribute(tag, "id")
  if (!is_string(resolved_id)) {
    shinymcp_abort(
      "Can't tell which output this is. Supply {.arg id}, or give the element an {.field id} attribute.",
      class = "shinymcp_error_validation"
    )
  }
  htmltools::tagAppendAttributes(
    tag,
    `data-shinymcp-output` = resolved_id,
    `data-shinymcp-output-type` = type
  )
}

#' Inputs for apps built from tools
#'
#' @description
#' Small form controls for [mcp_app()] UIs, drawn by the page itself.
#' Shiny's and bslib's inputs work just as well in an MCP App; these need
#' neither package and keep the page light.
#'
#' * `mcp_select()`: a drop-down list.
#' * `mcp_text_input()`: a line of text.
#' * `mcp_numeric_input()`: a number.
#' * `mcp_checkbox()`: `TRUE` or `FALSE`.
#' * `mcp_slider()`: a number on a range.
#' * `mcp_radio()`: one of a few choices.
#' * `mcp_action_button()`: a button; a tool taking its id runs when it's
#'   pressed.
#'
#' @param id The input id, which is the name of the tool argument it feeds.
#' @param label The label shown with the input.
#' @param choices The values to choose from. Names, if any, are shown in
#'   their place.
#' @param selected The value selected at first. Defaults to the first
#'   choice.
#' @return A tag.
#' @family components
#' @export
#' @examples
#' htmltools::tagList(
#'   mcp_select("species", "Species", c("Adelie", "Gentoo", "Chinstrap")),
#'   mcp_slider("alpha", "Opacity", min = 0, max = 1, value = 0.7, step = 0.1),
#'   mcp_checkbox("smooth", "Add a trend line")
#' )
mcp_select <- function(id, label, choices, selected = choices[[1]]) {
  choice_names <- names(choices) %||% unname(choices)
  choice_values <- unname(choices)

  options <- mapply(
    function(name, value) {
      htmltools::tags$option(
        value = value,
        selected = if (identical(value, selected)) NA else NULL,
        name
      )
    },
    choice_names,
    choice_values,
    SIMPLIFY = FALSE,
    USE.NAMES = FALSE
  )

  htmltools::tags$div(
    class = "shinymcp-input-group",
    htmltools::tags$label(`for` = id, label),
    htmltools::tags$select(
      id = id,
      `data-shinymcp-input` = id,
      `data-shinymcp-type` = "select",
      options
    )
  )
}

#' @rdname mcp_select
#' @param value The value at first.
#' @param placeholder Text shown while the input is empty.
#' @export
mcp_text_input <- function(id, label, value = "", placeholder = NULL) {
  htmltools::tags$div(
    class = "shinymcp-input-group",
    htmltools::tags$label(`for` = id, label),
    htmltools::tags$input(
      type = "text",
      id = id,
      `data-shinymcp-input` = id,
      `data-shinymcp-type` = "text",
      value = value,
      placeholder = placeholder
    )
  )
}

#' @rdname mcp_select
#' @param min,max The smallest and largest values allowed.
#' @param step The step between values.
#' @export
mcp_numeric_input <- function(id, label, value, min = NA, max = NA, step = NA) {
  attrs <- list(
    type = "number",
    id = id,
    `data-shinymcp-input` = id,
    `data-shinymcp-type` = "numeric",
    value = value
  )
  if (!is.na(min)) {
    attrs$min <- min
  }
  if (!is.na(max)) {
    attrs$max <- max
  }
  if (!is.na(step)) {
    attrs$step <- step
  }

  htmltools::tags$div(
    class = "shinymcp-input-group",
    htmltools::tags$label(`for` = id, label),
    do.call(htmltools::tags$input, attrs)
  )
}

#' @rdname mcp_select
#' @export
mcp_checkbox <- function(id, label, value = FALSE) {
  input_tag <- htmltools::tags$input(
    type = "checkbox",
    id = id,
    `data-shinymcp-input` = id,
    `data-shinymcp-type` = "checkbox",
    checked = if (isTRUE(value)) NA else NULL
  )

  htmltools::tags$div(
    class = "shinymcp-input-group",
    htmltools::tags$label(
      input_tag,
      label
    )
  )
}

#' @rdname mcp_select
#' @export
mcp_slider <- function(id, label, min, max, value = min, step = 1) {
  htmltools::tags$div(
    class = "shinymcp-input-group",
    htmltools::tags$label(`for` = id, label),
    htmltools::tags$input(
      type = "range",
      id = id,
      `data-shinymcp-input` = id,
      `data-shinymcp-type` = "slider",
      min = min,
      max = max,
      value = value,
      step = step
    )
  )
}

#' @rdname mcp_select
#' @export
mcp_radio <- function(id, label, choices, selected = choices[[1]]) {
  choice_names <- names(choices) %||% unname(choices)
  choice_values <- unname(choices)

  radio_items <- mapply(
    function(name, value) {
      htmltools::tags$label(
        htmltools::tags$input(
          type = "radio",
          name = id,
          value = value,
          checked = if (identical(value, selected)) NA else NULL
        ),
        name
      )
    },
    choice_names,
    choice_values,
    SIMPLIFY = FALSE,
    USE.NAMES = FALSE
  )

  htmltools::tags$div(
    class = "shinymcp-input-group",
    `data-shinymcp-input` = id,
    `data-shinymcp-type` = "radio",
    htmltools::tags$label(label),
    htmltools::tagList(radio_items)
  )
}

#' @rdname mcp_select
#' @export
mcp_action_button <- function(id, label) {
  htmltools::tags$div(
    class = "shinymcp-input-group",
    htmltools::tags$button(
      id = id,
      `data-shinymcp-input` = id,
      `data-shinymcp-type` = "button",
      label
    )
  )
}

#' An apply button for apps that wait for it
#'
#' In an app made with `mcp_app(trigger = "submit")`, input changes wait
#' until the user presses an apply button. Without one in the UI, the page
#' adds its own at the bottom; use `mcp_submit_button()` to choose where it
#' goes and what it says. The button is disabled until something changes.
#'
#' @param label Button text.
#' @param class CSS classes for the button.
#' @return An htmltools `<button>` tag.
#' @family components
#' @export
#' @examples
#' mcp_submit_button("Run analysis")
mcp_submit_button <- function(label = "Apply", class = "btn btn-primary") {
  htmltools::tags$button(
    type = "button",
    class = class,
    `data-shinymcp-submit` = "",
    label
  )
}
