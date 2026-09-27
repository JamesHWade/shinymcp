# stdio transport
#
# The client starts the R process and exchanges newline-delimited JSON-RPC
# messages over its stdin and stdout. Anything else written to stdout would
# corrupt the stream, so output printed by tools is diverted to stderr, where
# clients collect it as logs.

#' @noRd
serve_stdio <- function(server, input = file("stdin"), output = stdout()) {
  cli::cli_inform(
    "shinymcp: serving {.val {vapply(server$apps, function(a) a$name, '')}} over stdio",
    class = "shinymcp_message"
  )
  if (!isOpen(input)) {
    open(input, "r")
  }
  on.exit(close(input), add = TRUE)

  session <- server$new_session()
  context <- list(transport = "stdio", session = session)

  repeat {
    line <- readLines(input, n = 1, warn = FALSE, encoding = "UTF-8")
    if (length(line) == 0) {
      break
    }
    if (!nzchar(trimws(line))) {
      next
    }
    response <- stdio_handle_line(server, line, context)
    if (!is.null(response)) {
      cat(response, "\n", sep = "", file = output)
      flush(output)
    }
  }
  invisible(NULL)
}

#' Handle one line of input and return the JSON to write, or NULL
#' @noRd
stdio_handle_line <- function(server, line, context) {
  message <- tryCatch(from_json(line), error = function(e) NULL)
  if (is.null(message)) {
    return(as.character(to_json(jsonrpc_error(NULL, RPC_PARSE_ERROR, "Parse error"))))
  }
  handle_one <- function(msg) {
    tryCatch(
      with_stdout_diverted(server$handle(msg, context)),
      error = function(e) {
        cli::cli_alert_danger("Internal error: {conditionMessage(e)}")
        jsonrpc_error(msg$id, RPC_INTERNAL_ERROR, paste("Internal error:", conditionMessage(e)))
      }
    )
  }
  response <- if (is.null(names(message)) && length(message) > 0 && is.list(message[[1]])) {
    # A JSON-RPC batch (allowed before protocol version 2025-06-18).
    compact_list(lapply(message, handle_one))
  } else {
    handle_one(message)
  }
  if (is.null(response) || (is.list(response) && length(response) == 0)) {
    return(NULL)
  }
  as.character(to_json(strip_http_status(response)))
}

#' Evaluate with anything printed to stdout sent to stderr instead
#' @noRd
with_stdout_diverted <- function(expr) {
  sink(stderr())
  on.exit(sink(), add = TRUE)
  force(expr)
}

#' @noRd
strip_http_status <- function(x) {
  attr(x, "http_status") <- NULL
  x
}
