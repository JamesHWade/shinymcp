# MCP-compatible input components
#
# These functions generate static HTML with data-shinymcp-* attributes
# that the JS bridge reads to construct MCP tool parameters.

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
