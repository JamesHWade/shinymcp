# Internal utilities for shinymcp

#' Read a package file from inst/
#' @param ... Path components relative to inst/
#' @noRd
system_file <- function(...) {
  system.file(..., package = "shinymcp", mustWork = TRUE)
}

#' Generate a unique ID
#' @param prefix Optional prefix
#' @noRd
unique_id <- function(prefix = "shinymcp") {
  paste0(
    prefix,
    "-",
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "-",
    sample(1000:9999, 1)
  )
}

#' Convert an R object to JSON
#' @param x Object to convert
#' @param pretty Whether to pretty-print
#' @noRd
to_json <- function(x, pretty = FALSE) {
  jsonlite::toJSON(x, auto_unbox = TRUE, pretty = pretty, null = "null")
}

#' Parse JSON string
#' @param x JSON string
#' @noRd
from_json <- function(x) {
  jsonlite::fromJSON(x, simplifyVector = FALSE)
}

#' Encode content as base64
#' @param raw_content Raw bytes to encode
#' @noRd
base64_encode <- function(raw_content) {
  rlang::check_installed("base64enc", reason = "for base64 encoding")
  base64enc::base64encode(raw_content)
}

#' Check if an object is an ellmer ToolDef (S7)
#' @param x Object to check
#' @noRd
is_ellmer_tool <- function(x) {
  inherits(x, "ellmer::ToolDef")
}

#' Get the name of a tool (ellmer S7 or plain list)
#' @param tool A tool object
#' @noRd
tool_name <- function(tool) {
  if (is_ellmer_tool(tool)) {
    tool@name %||% "unnamed"
  } else if (is.list(tool)) {
    tool$name %||% "unnamed"
  } else {
    "unnamed"
  }
}

#' Build a JSON-ready input schema from an ellmer TypeObject
#' @param arguments An ellmer TypeObject (tool@@arguments)
#' @noRd
type_object_to_schema <- function(arguments) {
  props <- arguments@properties
  schema <- list(
    type = "object",
    properties = lapply(props, function(p) {
      compact_list(list(
        type = p@type,
        description = if (nzchar(p@description %||% "")) p@description
      ))
    })
  )
  required <- names(props)[vapply(
    props,
    function(p) isTRUE(p@required),
    logical(1)
  )]
  if (length(required) > 0) {
    schema$required <- as.list(required)
  }
  schema
}

#' Remove NULL entries from a list
#' @param x A list
#' @noRd
compact_list <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}
