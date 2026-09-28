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
    return(as.character(to_json(jsonrpc_error(
      NULL,
      RPC_PARSE_ERROR,
      "Parse error"
    ))))
  }
  handle_one <- function(msg) {
    tryCatch(
      with_stdout_diverted(server$handle(msg, context)),
      error = function(e) {
        cli::cli_alert_danger("Internal error: {conditionMessage(e)}")
        jsonrpc_error(
          request_id(msg),
          RPC_INTERNAL_ERROR,
          paste("Internal error:", conditionMessage(e))
        )
      }
    )
  }
  response <- if (is_json_batch(message)) {
    # A JSON-RPC batch (allowed before protocol version 2025-06-18).
    compact_list(lapply(message, function(msg) {
      batch_refusal(msg) %||% handle_one(msg)
    }))
  } else {
    handle_one(message)
  }
  if (is.null(response) || (is.list(response) && length(response) == 0)) {
    return(NULL)
  }
  as.character(to_json(strip_http_status(response)))
}

#' Is a parsed message a JSON-RPC batch?
#'
#' Any array but an empty one: each entry that isn't a message gets an
#' error of its own, as JSON-RPC 2.0 asks.
#' @noRd
is_json_batch <- function(message) {
  is.list(message) && is.null(names(message)) && length(message) > 0
}

#' The error for a batched message that must be sent on its own, or NULL
#' @noRd
batch_refusal <- function(msg) {
  if (
    is.list(msg) && !is.null(names(msg)) && identical(msg$method, "initialize")
  ) {
    jsonrpc_error(
      request_id(msg),
      RPC_INVALID_REQUEST,
      "Invalid Request: initialize can't be sent in a batch.",
      status = 400L
    )
  }
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
