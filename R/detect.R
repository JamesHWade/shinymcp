# Tag introspection for detecting Shiny input/output roles
#
# These functions inspect evaluated htmltools tag trees to determine
# whether a tag represents a Shiny input or output, and extract its
# ID and type. Used by bindMcp() and parse_shiny_ui_tags().

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

  # --- Output patterns (more specific, check first) ---

  if (grepl("shiny-plot-output", classes, fixed = TRUE)) {
    return(list(role = "output", id = tag_id, type = "plot"))
  }

  if (grepl("shiny-text-output", classes, fixed = TRUE)) {
    return(list(role = "output", id = tag_id, type = "text"))
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

  # --- Input pattern ---

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
#'   "radio", "slider", "button", or "unknown"
#' @noRd
detect_input_type <- function(tag) {
  tq <- htmltools::tagQuery(tag)

  if (tq$find("select")$length() > 0) return("select")
  if (tq$find("textarea")$length() > 0) return("text")
  if (tq$find("button")$length() > 0) return("button")

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


#' Extract label text from a Shiny input container
#'
#' Looks for a `<label>` element inside the tag and returns its text content.
#'
#' @param tag An [htmltools::tag] with class "shiny-input-container"
#' @return Character string label, or NULL
#' @noRd
extract_label_from_tag <- function(tag) {
  tq <- htmltools::tagQuery(tag)
  labels <- tq$find("label")
  if (labels$length() > 0) {
    label_tag <- labels$selectedTags()[[1]]
    # Extract text from children (skip child tags, get character nodes)
    texts <- Filter(is.character, label_tag$children)
    if (length(texts) > 0) {
      return(trimws(paste(texts, collapse = " ")))
    }
  }
  NULL
}
