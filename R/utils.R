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
