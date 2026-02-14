# bindMcp() — pipe operator for annotating Shiny elements for MCP exposure
#
# Stamps data-shinymcp-* attributes on Shiny input/output tags so the
# JS bridge and McpApp can discover them. Works as a pipe:
#   selectInput("x", "X", choices) |> bindMcp()

#' Mark a Shiny UI element for MCP exposure
#'
#' Annotates a Shiny input or output tag with `data-shinymcp-*` attributes
#' so it can be discovered by the MCP JS bridge. Auto-detects whether the
#' tag is an input or output by inspecting Shiny's class conventions.
#'
#' Use this as a pipe on standard Shiny UI elements:
#' ```r
#' selectInput("x", "X", c("a", "b")) |> bindMcp()
#' plotOutput("plot") |> bindMcp()
#' ```
#'
#' `bindMcp()` is idempotent: calling it on an element that already has
#' `data-shinymcp-input` or `data-shinymcp-output` attributes is a no-op.
#'
#' @param tag A [shiny.tag][htmltools::tag] or [shiny.tag.list][htmltools::tagList]
#'   produced by a Shiny input or output function.
#' @param id Override the input/output ID. If `NULL` (default), the ID is
#'   auto-detected from the tag structure.
#' @param type Override the output type (`"text"`, `"html"`, `"plot"`, or
#'   `"table"`). Only used for outputs. If `NULL`, auto-detected.
#' @param description Optional human-readable description of this element's
#'   role. Stored as metadata for tool generation.
#' @param ... Reserved for future use.
#' @return The modified [htmltools::tag] with MCP attributes stamped.
#' @export
bindMcp <- function(tag, ...) {
  UseMethod("bindMcp")
}

#' @rdname bindMcp
#' @export
bindMcp.shiny.tag <- function(tag, id = NULL, type = NULL,
                              description = NULL, ...) {
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

  cli::cli_abort(
    c(
      "Cannot determine MCP role for this element.",
      i = "Ensure this is a Shiny input or output, or provide {.arg id} and {.arg type}."
    ),
    class = "shinymcp_error_validation"
  )
}

#' @rdname bindMcp
#' @export
bindMcp.shiny.tag.list <- function(tag, id = NULL, type = NULL,
                                   description = NULL, ...) {
  # For tagLists, try to find a single input/output tag inside and annotate it
  for (i in seq_along(tag)) {
    child <- tag[[i]]
    if (inherits(child, "shiny.tag")) {
      role <- detect_mcp_role(child)
      if (role$role != "unknown") {
        tag[[i]] <- bindMcp(child, id = id, type = type,
                            description = description, ...)
        return(tag)
      }
    }
  }

  cli::cli_abort(
    c(
      "Cannot determine MCP role for any element in this tagList.",
      i = "Wrap a specific input or output element with {.fn bindMcp} instead."
    ),
    class = "shinymcp_error_validation"
  )
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
    if (found) return()
    if (!is.null(htmltools::tagGetAttribute(child, "data-shinymcp-output"))) {
      found <<- TRUE
    }
  })

  found
}
