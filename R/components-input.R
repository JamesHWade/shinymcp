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
  form_selectors <- c("input", "select", "textarea", "button")
  tag_name <- tag$name %||% ""

  if (tolower(tag_name) %in% form_selectors) {
    # Tag itself is a form element — stamp directly
    resolved_id <- id %||% htmltools::tagGetAttribute(tag, "id")
    if (is.null(resolved_id)) {
      rlang::abort(
        cli::format_inline(
          "Cannot determine input ID. Provide {.arg id} or ensure the tag has an {.field id} attribute."
        ),
        class = "shinymcp_error_validation"
      )
    }
    tag <- htmltools::tagAppendAttributes(
      tag,
      `data-shinymcp-input` = resolved_id
    )
    return(tag)
  }

  # Find the first form-element descendant using tagQuery
  tq <- htmltools::tagQuery(tag)
  for (sel in form_selectors) {
    found <- tq$find(sel)
    if (found$length() > 0) {
      first_el <- found$selectedTags()[[1]]
      el_id <- htmltools::tagGetAttribute(first_el, "id")
      resolved_id <- id %||% el_id
      if (is.null(resolved_id)) {
        rlang::abort(
          cli::format_inline(
            "Cannot determine input ID. Provide {.arg id} or ensure the element has an {.field id} attribute."
          ),
          class = "shinymcp_error_validation"
        )
      }
      # Target just the first element to avoid stamping siblings
      if (!is.null(el_id) && found$length() > 1) {
        tq$find(paste0("#", el_id))$addAttrs(
          `data-shinymcp-input` = resolved_id
        )
      } else if (found$length() > 1) {
        # First element has no id and there are siblings — stamp manually
        stamped <- htmltools::tagAppendAttributes(
          first_el,
          `data-shinymcp-input` = resolved_id
        )
        # Rebuild the tree: replace children of the parent tag
        result_tag <- tag
        result_tag$children <- lapply(tag$children, function(child) {
          if (identical(child, first_el)) stamped else child
        })
        return(result_tag)
      } else {
        found$addAttrs(`data-shinymcp-input` = resolved_id)
      }
      return(tq$allTags())
    }
  }

  # No form element found — stamp the tag itself (e.g., radio group container)
  resolved_id <- id %||% htmltools::tagGetAttribute(tag, "id")
  if (is.null(resolved_id)) {
    rlang::abort(
      cli::format_inline(
        "Cannot determine input ID. Provide {.arg id} or ensure the tag has an {.field id} attribute."
      ),
      class = "shinymcp_error_validation"
    )
  }
  htmltools::tagAppendAttributes(tag, `data-shinymcp-input` = resolved_id)
}

#' Mark an element as an MCP output
#'
#' Stamps `data-shinymcp-output` and `data-shinymcp-output-type` on a tag.
#' Use this to turn any container element into a target for tool result output.
#'
#' @param tag An [htmltools::tag] object.
#' @param id The output ID. If `NULL` (the default), reads the element's
#'   existing `id` attribute.
#' @param type Output type: `"text"`, `"html"`, `"plot"`, or `"table"`.
#' @return The modified [htmltools::tag] with output attributes stamped.
#' @export
mcp_output <- function(
  tag,
  id = NULL,
  type = c("text", "html", "plot", "table")
) {
  type <- rlang::arg_match(type)
  resolved_id <- id %||% htmltools::tagGetAttribute(tag, "id")
  if (is.null(resolved_id)) {
    rlang::abort(
      cli::format_inline(
        "Cannot determine output ID. Provide {.arg id} or ensure the tag has an {.field id} attribute."
      ),
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
