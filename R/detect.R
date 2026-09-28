# Tag introspection for detecting Shiny input/output roles
#
# These functions inspect evaluated htmltools tag trees to determine
# whether a tag represents a Shiny input or output, and extract its
# ID and type. Used by bindMcp(), mcp_app(), mcp_tool_module(), and the
# live runtime.

#' Detect the MCP role of a Shiny UI tag
#'
#' Inspects a tag's class attributes and structure to determine if it
#' represents a Shiny input container, output placeholder, or neither.
#'
#' @param tag An [htmltools::tag] object (e.g., from `shiny::selectInput()`)
#' @return A list with `role` ("input", "output", or "unknown"),
#'   `id` (character or NULL), and `type` (character or NULL).
#' @noRd
detect_mcp_role <- function(tag) {
  if (!inherits(tag, "shiny.tag")) {
    return(list(role = "unknown", id = NULL, type = NULL))
  }

  classes <- htmltools::tagGetAttribute(tag, "class") %||% ""
  tag_id <- htmltools::tagGetAttribute(tag, "id")
  tag_name <- tolower(tag$name %||% "")

  # --- Output patterns (more specific, check first) ---

  if (grepl("shiny-plot-output", classes, fixed = TRUE)) {
    return(list(role = "output", id = tag_id, type = "plot"))
  }

  if (grepl("shiny-text-output", classes, fixed = TRUE)) {
    return(list(role = "output", id = tag_id, type = "text"))
  }

  if (grepl("shiny-table-output", classes, fixed = TRUE)) {
    return(list(role = "output", id = tag_id, type = "table"))
  }

  if (grepl("shiny-html-output", classes, fixed = TRUE)) {
    return(list(role = "output", id = tag_id, type = "html"))
  }

  if (
    grepl("datatables", classes, fixed = TRUE) &&
      grepl("html-widget-output", classes, fixed = TRUE)
  ) {
    return(list(role = "output", id = tag_id, type = "table"))
  }

  if (grepl("shiny-image-output", classes, fixed = TRUE)) {
    return(list(role = "output", id = tag_id, type = "plot"))
  }

  # Other htmlwidgets (plotly, leaflet, ...).
  if (grepl("html-widget-output", classes, fixed = TRUE)) {
    return(list(role = "output", id = tag_id, type = "widget"))
  }

  # --- Input pattern ---

  if (
    grepl("action-button", classes, fixed = TRUE) &&
      tag_name %in% c("a", "button")
  ) {
    return(list(role = "input", id = tag_id, type = "button"))
  }

  if (grepl("shiny-input-container", classes, fixed = TRUE)) {
    input_id <- find_form_element_id(tag) %||% tag_id
    input_type <- detect_input_type(tag)
    return(list(role = "input", id = input_id, type = input_type))
  }

  list(role = "unknown", id = tag_id, type = NULL)
}


#' Find the ID of the first form element inside a tag
#'
#' Searches the tag tree for `<select>`, `<input>`, `<textarea>`, or
#' `<button>` elements and returns the `id` attribute of the first one found.
#'
#' @param tag An [htmltools::tag] object
#' @return Character string ID, or NULL if not found
#' @noRd
find_form_element_id <- function(tag) {
  tq <- htmltools::tagQuery(tag)
  for (sel in c("select", "input", "textarea", "button")) {
    found <- tq$find(sel)
    if (found$length() > 0) {
      first <- found$selectedTags()[[1]]
      el_id <- htmltools::tagGetAttribute(first, "id")
      if (!is.null(el_id)) return(el_id)
    }
  }
  NULL
}


#' Detect the input type from a Shiny input container tag
#'
#' Inspects child elements to determine what kind of form control is present.
#'
#' @param tag An [htmltools::tag] with class "shiny-input-container"
#' @return Character string: "select", "text", "numeric", "checkbox",
#'   "radio", "slider", "date", "file", "button", or "unknown"
#' @noRd
detect_input_type <- function(tag) {
  tq <- htmltools::tagQuery(tag)
  classes <- htmltools::tagGetAttribute(tag, "class") %||% ""

  if (
    grepl("shiny-date-input", classes, fixed = TRUE) ||
      grepl("shiny-date-range-input", classes, fixed = TRUE)
  ) {
    return("date")
  }

  if (grepl("shiny-input-radiogroup", classes, fixed = TRUE)) {
    return("radio")
  }

  if (grepl("shiny-input-checkboxgroup", classes, fixed = TRUE)) {
    return("checkbox")
  }

  if (tq$find("select")$length() > 0) {
    return("select")
  }
  if (tq$find("textarea")$length() > 0) {
    return("text")
  }
  if (tq$find("button")$length() > 0) {
    return("button")
  }

  # sliderInput() renders as <input class="js-range-slider"> without
  # a type attribute in current Shiny markup.
  if (tq$find("input.js-range-slider")$length() > 0) {
    return("slider")
  }

  inputs <- tq$find("input")
  if (inputs$length() > 0) {
    first <- inputs$selectedTags()[[1]]
    input_type <- htmltools::tagGetAttribute(first, "type") %||% "text"
    return(switch(
      input_type,
      number = "numeric",
      range = "slider",
      checkbox = "checkbox",
      radio = "radio",
      date = "date",
      file = "file",
      text = "text",
      password = "text",
      "text"
    ))
  }

  "unknown"
}


#' Walk an htmltools tag tree, calling fn on each tag
#'
#' Recursively visits every [htmltools::tag] and [htmltools::tagList]
#' node in the tree.
#'
#' @param x A tag, tagList, or list of tags
#' @param fn A callback function receiving one tag at a time
#' @noRd
walk_tag_tree <- function(x, fn) {
  if (inherits(x, "shiny.tag")) {
    fn(x)
    if (!is.null(x$children)) {
      for (child in x$children) {
        walk_tag_tree(child, fn)
      }
    }
  } else if (inherits(x, "shiny.tag.list") || is.list(x)) {
    for (child in x) {
      walk_tag_tree(child, fn)
    }
  }
}

#' The DOM id of an element marked as an input or output
#'
#' @param tag An htmltools tag
#' @param role Either "input" or "output"
#' @return Character string DOM id, or NULL
#' @noRd
infer_mcp_dom_id <- function(tag, role = c("input", "output")) {
  role <- match.arg(role)
  if (role == "output") {
    return(htmltools::tagGetAttribute(tag, "id"))
  }
  htmltools::tagGetAttribute(tag, "id") %||% find_form_element_id(tag)
}

#' The inputs in a UI, marked or recognized
#'
#' @param ui An htmltools tag or tagList
#' @param selective If TRUE, only elements marked with data-shinymcp-input
#' @return List of inputs, each with `id`, `dom_id`, and `type`
#' @noRd
extract_inputs_from_tags <- function(ui, selective = FALSE) {
  inputs <- list()
  seen_ids <- character()

  walk_tag_tree(ui, function(tag) {
    if (!inherits(tag, "shiny.tag")) {
      return()
    }

    mcp_id <- htmltools::tagGetAttribute(tag, "data-shinymcp-input")
    if (!is.null(mcp_id) && !(mcp_id %in% seen_ids)) {
      mcp_type <- htmltools::tagGetAttribute(tag, "data-shinymcp-type")
      seen_ids[length(seen_ids) + 1L] <<- mcp_id
      inputs[[length(inputs) + 1L]] <<- list(
        id = mcp_id,
        dom_id = infer_mcp_dom_id(tag, "input"),
        type = mcp_type %||% detect_input_type(tag)
      )
      return()
    }

    if (selective) {
      return()
    }

    role <- detect_mcp_role(tag)
    if (role$role == "input" && !is.null(role$id) && !(role$id %in% seen_ids)) {
      seen_ids[length(seen_ids) + 1L] <<- role$id
      inputs[[length(inputs) + 1L]] <<- list(
        id = role$id,
        dom_id = role$id,
        type = role$type %||% "unknown"
      )
    }
  })

  inputs
}

#' The outputs in a UI, marked or recognized
#'
#' @param ui An htmltools tag or tagList
#' @param selective If TRUE, only elements marked with data-shinymcp-output
#' @return List of outputs, each with `id`, `dom_id`, and `type`
#' @noRd
extract_outputs_from_tags <- function(ui, selective = FALSE) {
  outputs <- list()
  seen_ids <- character()

  walk_tag_tree(ui, function(tag) {
    if (!inherits(tag, "shiny.tag")) {
      return()
    }

    mcp_id <- htmltools::tagGetAttribute(tag, "data-shinymcp-output")
    if (!is.null(mcp_id) && !(mcp_id %in% seen_ids)) {
      mcp_type <- htmltools::tagGetAttribute(tag, "data-shinymcp-output-type")
      seen_ids[length(seen_ids) + 1L] <<- mcp_id
      outputs[[length(outputs) + 1L]] <<- list(
        id = mcp_id,
        dom_id = infer_mcp_dom_id(tag, "output"),
        type = mcp_type %||% "html"
      )
      return()
    }

    if (selective) {
      return()
    }

    role <- detect_mcp_role(tag)
    if (
      role$role == "output" && !is.null(role$id) && !(role$id %in% seen_ids)
    ) {
      seen_ids[length(seen_ids) + 1L] <<- role$id
      outputs[[length(outputs) + 1L]] <<- list(
        id = role$id,
        dom_id = role$id,
        type = role$type %||% "html"
      )
    }
  })

  outputs
}
