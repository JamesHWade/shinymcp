# MCP-compatible input components
#
# These functions generate static HTML with data-shinymcp-* attributes
# that the JS bridge reads to construct MCP tool parameters.

#' Mark an element as an MCP input
#'
#' Stamps `data-shinymcp-input` on a tag or its first form-element descendant.
#' Use this as an escape hatch when auto-detection by tool argument name doesn't
#' work (e.g., custom widgets or elements whose `id` doesn't match the tool
#' argument name).
#'
#' @param tag An [htmltools::tag] object (e.g., from `shiny::selectInput()`
#'   or `bslib::input_select()`).
#' @param id The input ID to register. If `NULL` (the default), reads the
#'   element's existing `id` attribute.
#' @return The modified [htmltools::tag] with `data-shinymcp-input` stamped.
#' @export
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

  stamp_input(tag, id %||% htmltools::tagGetAttribute(tag, "id"))
}

#' Shiny inputs whose value belongs to a container, not an <input>
#' @noRd
INPUT_GROUP_SELECTORS <- c(
  ".shiny-input-radiogroup",
  ".shiny-input-checkboxgroup",
  ".shiny-date-input",
  ".shiny-date-range-input"
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

#' Mark an element as an MCP output
#'
#' Stamps `data-shinymcp-output` and `data-shinymcp-output-type` on a tag.
#' Use this to turn any container element into a target for tool result output.
#'
#' @param tag An [htmltools::tag] object.
#' @param id The output ID. If `NULL` (the default), reads the element's
#'   existing `id` attribute.
#' @param type Output type: `"text"`, `"html"`, `"plot"`, `"table"`,
#'   `"image"`, or `"widget"`.
#' @return The modified [htmltools::tag] with output attributes stamped.
#' @export
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

#' Create an MCP select input
#'
#' Generates a dropdown select element with MCP data attributes.
#'
#' @param id Input ID
#' @param label Display label
#' @param choices Character vector of choices. If named, names are used as
#'   display labels and values as the option values.
#' @param selected The initially selected value. Defaults to the first choice.
#' @return An [htmltools::tag] object
#' @export
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

#' Create an MCP text input
#'
#' Generates a text input element with MCP data attributes.
#'
#' @param id Input ID
#' @param label Display label
#' @param value Initial value
#' @param placeholder Placeholder text
#' @return An [htmltools::tag] object
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

#' Create an MCP numeric input
#'
#' Generates a numeric input element with MCP data attributes.
#'
#' @param id Input ID
#' @param label Display label
#' @param value Initial value
#' @param min Minimum allowed value
#' @param max Maximum allowed value
#' @param step Step increment
#' @return An [htmltools::tag] object
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

#' Create an MCP checkbox input
#'
#' Generates a checkbox input element with MCP data attributes.
#'
#' @param id Input ID
#' @param label Display label
#' @param value Initial checked state
#' @return An [htmltools::tag] object
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

#' Create an MCP slider input
#'
#' Generates a range slider element with MCP data attributes.
#'
#' @param id Input ID
#' @param label Display label
#' @param min Minimum value
#' @param max Maximum value
#' @param value Initial value
#' @param step Step increment
#' @return An [htmltools::tag] object
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

#' Create MCP radio button inputs
#'
#' Generates a set of radio buttons with MCP data attributes.
#'
#' @param id Input ID
#' @param label Display label
#' @param choices Character vector of choices. If named, names are used as
#'   display labels and values as the radio values.
#' @param selected The initially selected value. Defaults to the first choice.
#' @return An [htmltools::tag] object
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

#' Create an MCP action button
#'
#' Generates a button element with MCP data attributes.
#'
#' @param id Input ID
#' @param label Button label
#' @return An [htmltools::tag] object
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
