# Error helpers
#
# Every error shinymcp raises inherits from `shinymcp_error`, plus a more
# specific class, so callers can catch them precisely:
#
#   tryCatch(serve(app), shinymcp_error_validation = function(e) ...)

#' Signal a shinymcp error
#'
#' `message` is a cli-formatted string (or character vector of bullets),
#' evaluated in the caller's environment.
#' @noRd
shinymcp_abort <- function(
  message,
  class = NULL,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  cli::cli_abort(
    message,
    class = c(class, "shinymcp_error"),
    ...,
    call = call,
    .envir = .envir
  )
}

#' @noRd
shinymcp_error_parse <- function(
  message,
  path = NULL,
  call = rlang::caller_env()
) {
  shinymcp_abort(
    message,
    class = "shinymcp_error_parse",
    path = path,
    call = call,
    .envir = parent.frame()
  )
}

#' @noRd
shinymcp_error_analysis <- function(message, call = rlang::caller_env()) {
  shinymcp_abort(
    message,
    class = "shinymcp_error_analysis",
    call = call,
    .envir = parent.frame()
  )
}

#' @noRd
shinymcp_error_generation <- function(message, call = rlang::caller_env()) {
  shinymcp_abort(
    message,
    class = "shinymcp_error_generation",
    call = call,
    .envir = parent.frame()
  )
}

#' @noRd
shinymcp_error_resource <- function(
  message,
  uri = NULL,
  call = rlang::caller_env()
) {
  shinymcp_abort(
    message,
    class = "shinymcp_error_resource",
    uri = uri,
    call = call,
    .envir = parent.frame()
  )
}

#' @noRd
shinymcp_error_validation <- function(message, call = rlang::caller_env()) {
  shinymcp_abort(
    message,
    class = "shinymcp_error_validation",
    call = call,
    .envir = parent.frame()
  )
}
