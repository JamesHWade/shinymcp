# Custom error classes for shinymcp

#' Create a parse error
#' @param message Error message
#' @param path Path to the Shiny app that failed to parse
#' @param call The calling environment
#' @noRd
shinymcp_error_parse <- function(
  message,
  path = NULL,
  call = rlang::caller_env()
) {
  rlang::abort(
    message,
    class = "shinymcp_error_parse",
    path = path,
    call = call
  )
}

#' Create an analysis error
#' @param message Error message
#' @param call The calling environment
#' @noRd
shinymcp_error_analysis <- function(message, call = rlang::caller_env()) {
  rlang::abort(
    message,
    class = "shinymcp_error_analysis",
    call = call
  )
}

#' Create a generation error
#' @param message Error message
#' @param call The calling environment
#' @noRd
shinymcp_error_generation <- function(message, call = rlang::caller_env()) {
  rlang::abort(
    message,
    class = "shinymcp_error_generation",
    call = call
  )
}

#' Create a resource error
#' @param message Error message
#' @param uri The resource URI that caused the error
#' @param call The calling environment
#' @noRd
shinymcp_error_resource <- function(
  message,
  uri = NULL,
  call = rlang::caller_env()
) {
  rlang::abort(
    message,
    class = "shinymcp_error_resource",
    uri = uri,
    call = call
  )
}

#' Create a serve error
#' @param message Error message
#' @param call The calling environment
#' @noRd
shinymcp_error_serve <- function(message, call = rlang::caller_env()) {
  rlang::abort(
    message,
    class = "shinymcp_error_serve",
    call = call
  )
}
