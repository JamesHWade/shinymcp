# bindMcp() - pipe operator for annotating Shiny elements for MCP exposure
#
# Stamps data-shinymcp-* attributes on Shiny input/output tags so the
# JS bridge and McpApp can discover them. Works as a pipe:
#   selectInput("x", "X", choices) |> bindMcp()

#' Choose what the model sees of a Shiny app
#'
#' @description
#' In a Shiny app served with [as_mcp_app()], every input becomes an
#' argument of the app's tool and every output is reported to the model.
#' Mark some of them with `bindMcp()` and only the marked ones are: the
#' model gets a smaller tool that is easier to use well. The person using
#' the app still sees all of it.
#'
#' ```r
#' ui <- fluidPage(
#'   selectInput("species", "Species", species) |> bindMcp(),
#'   sliderInput("alpha", "Point opacity", 0, 1, 0.7),
#'   plotOutput("scatter") |> bindMcp(),
#'   verbatimTextOutput("debug")
#' )
#' ```
#'
#' Here the model can set the species and reads the plot; the opacity
#' slider and the debug output stay between the app and its user.
#' Action buttons are only pressed by the model when marked.
#'
#' In a UI for [mcp_app()], `bindMcp()` marks an element as an input or an
#' output of the app's tools when shinymcp can't tell on its own.
#'
#' `bindMcp()` recognizes Shiny's and bslib's inputs and outputs, and
#' htmlwidget outputs. For anything else, give `type`. Marking an element
#' twice does nothing.
#'
#' @param tag A tag or tag list from a Shiny input or output function.
#' @param id The id to use, when it isn't the element's own.
#' @param type For outputs: `"text"`, `"html"`, `"plot"`, `"table"`,
#'   `"image"`, or `"widget"`. Usually detected; required to mark an
#'   element shinymcp doesn't recognize.
#' @param ... Unused.
#' @return `tag`, marked.
#' @family apps
#' @export
#' @examplesIf rlang::is_installed("shiny")
#' shiny::selectInput("species", "Species", c("Adelie", "Gentoo")) |>
#'   bindMcp()
bindMcp <- function(tag, ...) {
  UseMethod("bindMcp")
}

#' @rdname bindMcp
#' @export
bindMcp.shiny.tag <- function(
  tag,
  id = NULL,
  type = NULL,
  ...
) {
  # Idempotency: check if already annotated anywhere in the tree
  if (has_mcp_annotation(tag)) {
    return(tag)
  }

  detected <- detect_mcp_role(tag)

  if (detected$role == "input") {
    resolved_id <- id %||% detected$id
    if (is.null(resolved_id)) {
      cli::cli_abort(
        "Cannot detect input ID from this tag. Provide {.arg id} explicitly.",
        class = "shinymcp_error_validation"
      )
    }
    return(mcp_input(tag, id = resolved_id))
  }

  if (detected$role == "output") {
    resolved_id <- id %||% detected$id
    resolved_type <- type %||% detected$type %||% "html"
    if (is.null(resolved_id)) {
      cli::cli_abort(
        "Cannot detect output ID from this tag. Provide {.arg id} explicitly.",
        class = "shinymcp_error_validation"
      )
    }
    return(mcp_output(tag, id = resolved_id, type = resolved_type))
  }

  # An element shinymcp can't classify is an output when given a type.
  if (!is.null(type)) {
    resolved_id <- id %||% detected$id
    if (is.null(resolved_id)) {
      cli::cli_abort(
        "Cannot detect an ID for this element. Provide {.arg id} explicitly.",
        class = "shinymcp_error_validation"
      )
    }
    return(mcp_output(tag, id = resolved_id, type = type))
  }

  cli::cli_abort(
    c(
      "Cannot determine MCP role for this element.",
      i = "For an output shinymcp doesn't recognize, give its {.arg type} (and {.arg id} if the element has none)."
    ),
    class = "shinymcp_error_validation"
  )
}

#' @rdname bindMcp
#' @export
bindMcp.shiny.tag.list <- function(
  tag,
  id = NULL,
  type = NULL,
  ...
) {
  matching_children <- integer()

  for (i in seq_along(tag)) {
    child <- tag[[i]]
    if (inherits(child, "shiny.tag")) {
      role <- detect_mcp_role(child)
      if (role$role != "unknown") {
        matching_children <- c(matching_children, i)
      }
    }
  }

  if (length(matching_children) == 0) {
    cli::cli_abort(
      c(
        "Cannot determine MCP role for any element in this tagList.",
        i = "Wrap a specific input or output element with {.fn bindMcp} instead."
      ),
      class = "shinymcp_error_validation"
    )
  }

  if (length(matching_children) > 1 && (!is.null(id) || !is.null(type))) {
    cli::cli_abort(
      c(
        "Cannot apply a single {.arg id} or {.arg type} override to multiple elements in a tagList.",
        i = "Call {.fn bindMcp} on each element separately when you need explicit overrides."
      ),
      class = "shinymcp_error_validation"
    )
  }

  for (i in matching_children) {
    tag[[i]] <- bindMcp(
      tag[[i]],
      id = id,
      type = type,
      ...
    )
  }

  tag
}

#' @rdname bindMcp
#' @export
bindMcp.default <- function(tag, ...) {
  cli::cli_abort(
    c(
      "{.fn bindMcp} does not know how to handle objects of class {.cls {class(tag)}}.",
      i = "Expected an {.cls htmltools} tag from a Shiny input or output function."
    ),
    class = "shinymcp_error_validation"
  )
}


#' Check if a tag already has MCP annotations
#'
#' Checks the tag itself and immediate form-element children for
#' `data-shinymcp-input` or `data-shinymcp-output` attributes.
#'
#' @param tag An [htmltools::tag] object
#' @return Logical
#' @noRd
has_mcp_annotation <- function(tag) {
  # Check the tag itself
  if (!is.null(htmltools::tagGetAttribute(tag, "data-shinymcp-input"))) {
    return(TRUE)
  }
  if (!is.null(htmltools::tagGetAttribute(tag, "data-shinymcp-output"))) {
    return(TRUE)
  }

  # Check children (Shiny wraps form elements in container divs)
  tq <- htmltools::tagQuery(tag)
  for (sel in c("select", "input", "textarea", "button")) {
    found <- tq$find(sel)
    if (found$length() > 0) {
      first <- found$selectedTags()[[1]]
      if (!is.null(htmltools::tagGetAttribute(first, "data-shinymcp-input"))) {
        return(TRUE)
      }
    }
  }

  # Check any child with data-shinymcp-output
  found <- FALSE
  walk_tag_tree(tag, function(child) {
    if (found) {
      return()
    }
    if (!is.null(htmltools::tagGetAttribute(child, "data-shinymcp-output"))) {
      found <<- TRUE
    }
  })

  found
}
