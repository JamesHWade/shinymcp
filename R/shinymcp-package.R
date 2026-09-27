#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom R6 R6Class
#' @importFrom rlang %||%
#' @importFrom stats setNames
## usethis namespace: end
NULL

# The methods of the R6 class made in runtime_session_class() refer to these;
# R6 binds them when an object is created.
utils::globalVariables(c("self", "private", "super"))
