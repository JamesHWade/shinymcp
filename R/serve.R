# MCP server that combines tool handling with resource handling

#' Serve an MCP App
#'
#' Starts an MCP server that serves the app's tools and ui:// resources.
#'
#' @param app An McpApp object, or a path to a Shiny app (which will be
#'   auto-converted via [convert_app()]).
#' @param type Server transport type: `"stdio"` or `"http"`.
#' @param port Port for HTTP transport (default 8080).
#' @param ... Additional arguments (currently unused).
#' @export
serve <- function(app, type = c("stdio", "http"), port = 8080, ...) {
  type <- match.arg(type)

  # If app is a path string, auto-convert
  if (is.character(app)) {
    app <- convert_app(app)
  }

  if (!inherits(app, "McpApp")) {
    cli::cli_abort(
      "{.arg app} must be an {.cls McpApp} object or a path to a Shiny app."
    )
  }

  # Set up resource registry
  registry <- ResourceRegistry$new()
  registry$register(
    uri = app$resource_uri(),
    name = app$name,
    description = paste("MCP App:", app$name),
    mime_type = "text/html;profile=mcp-app",
    content_fn = function() app$html_resource()
  )

  switch(
    type,
    stdio = serve_stdio(app, registry),
    http = serve_http(app, registry, port)
  )
}


# ---- stdio transport ----

#' Serve MCP over stdio
#'
#' Reads JSON-RPC messages from stdin line by line and writes responses
#' to stdout.
#'
#' @param app An McpApp object
#' @param registry A ResourceRegistry object
#' @noRd
serve_stdio <- function(app, registry) {
  cli::cli_inform("shinymcp: serving over stdio")

  con <- file("stdin", "r")
  on.exit(close(con))

  while (TRUE) {
    line <- readLines(con, n = 1)

    # EOF or empty connection
    if (length(line) == 0) {
      break
    }
    # Skip blank lines
    if (nchar(trimws(line)) == 0) {
      next
    }

    message <- tryCatch(
      from_json(line),
      error = function(e) NULL
    )
    if (is.null(message)) {
      response <- jsonrpc_error(NULL, -32700, "Parse error: invalid JSON")
    } else {
      response <- tryCatch(
        dispatch_message(message, app, registry),
        error = function(e) {
          cli::cli_alert_danger("Internal error: {e$message}")
          jsonrpc_error(message$id, -32603, paste("Internal error:", e$message))
        }
      )
    }

    # Notifications (no id) don't get responses
    if (is.null(response)) {
      next
    }

    response_json <- to_json(response)
    cat(response_json, "\n", sep = "")
    flush(stdout())
  }
}


# ---- HTTP transport ----

#' Serve MCP over HTTP
#'
#' Creates an HTTP server using httpuv that accepts JSON-RPC POST requests.
#'
#' @param app An McpApp object
#' @param registry A ResourceRegistry object
#' @param port Port number
#' @noRd
serve_http <- function(app, registry, port) {
  rlang::check_installed("httpuv", reason = "for HTTP transport")

  cli::cli_inform("shinymcp: serving over HTTP on port {port}")

  httpuv::runServer(
    host = "127.0.0.1",
    port = port,
    app = list(
      call = function(req) {
        # Only accept POST requests
        if (!identical(req$REQUEST_METHOD, "POST")) {
          return(list(
            status = 405L,
            headers = list("Content-Type" = "application/json"),
            body = to_json(jsonrpc_error(NULL, -32600, "Only POST allowed"))
          ))
        }

        body <- paste(req$rook.input$read_lines(), collapse = "\n")

        message <- tryCatch(from_json(body), error = function(e) NULL)
        if (is.null(message)) {
          response <- jsonrpc_error(NULL, -32700, "Parse error: invalid JSON")
        } else {
          response <- tryCatch(
            dispatch_message(message, app, registry),
            error = function(e) {
              cli::cli_alert_danger("Internal error: {e$message}")
              jsonrpc_error(
                message$id,
                -32603,
                paste("Internal error:", e$message)
              )
            }
          )
        }

        # Notifications return 204
        if (is.null(response)) {
          return(list(status = 204L, headers = list(), body = ""))
        }

        list(
          status = 200L,
          headers = list("Content-Type" = "application/json"),
          body = to_json(response)
        )
      }
    )
  )
}


# ---- Message dispatch ----

#' Dispatch a JSON-RPC message to the appropriate handler
#'
#' Tries resource handler first, then tool dispatch, then built-in methods.
#'
#' @param message Parsed JSON-RPC message
#' @param app McpApp object
#' @param registry ResourceRegistry object
#' @return A JSON-RPC response list, or NULL for notifications
#' @noRd
dispatch_message <- function(message, app, registry) {
  method <- message$method

  # Handle notifications (no id field means no response expected)
  if (is.null(message$id) && !is.null(method)) {
    # Process notification side effects if needed
    if (identical(method, "notifications/initialized")) {
      # Client acknowledged initialization; nothing to do
    }
    return(NULL)
  }

  # Built-in protocol methods
  if (identical(method, "initialize")) {
    return(handle_initialize(message, app, registry))
  }

  if (identical(method, "shutdown")) {
    return(jsonrpc_response(message$id, NULL))
  }

  # Try resource handler first
  resource_response <- handle_resource_message(message, registry)
  if (!is.null(resource_response)) {
    return(resource_response)
  }

  # Tool dispatch
  if (identical(method, "tools/list")) {
    return(handle_tools_list(message, app))
  }

  if (identical(method, "tools/call")) {
    return(handle_tools_call(message, app))
  }

  jsonrpc_error(message$id, -32601, paste("Method not found:", method))
}


# ---- Built-in method handlers ----

#' Handle initialize request
#' @param message Parsed JSON-RPC message
#' @param app McpApp object
#' @param registry ResourceRegistry object
#' @noRd
handle_initialize <- function(message, app, registry) {
  empty_obj <- setNames(list(), character(0))

  # Negotiate protocol version: respond with the client's version or our

  # maximum supported version, whichever is lower
  client_version <- message$params$protocolVersion %||% "2024-11-05"
  server_version <- "2025-06-18"
  negotiated <- min(client_version, server_version)

  jsonrpc_response(
    message$id,
    list(
      protocolVersion = negotiated,
      capabilities = list(
        tools = empty_obj,
        resources = empty_obj
      ),
      serverInfo = list(
        name = paste0("shinymcp-", app$name),
        version = as.character(utils::packageVersion("shinymcp"))
      )
    )
  )
}


# ---- Tool handlers ----

#' Handle tools/list request
#' @param message Parsed JSON-RPC message
#' @param app McpApp object
#' @noRd
handle_tools_list <- function(message, app) {
  tools <- app$tool_definitions()
  jsonrpc_response(message$id, list(tools = tools))
}

#' Handle tools/call request
#' @param message Parsed JSON-RPC message
#' @param app McpApp object
#' @noRd
handle_tools_call <- function(message, app) {
  tool_name <- message$params$name
  arguments <- message$params$arguments %||% list()

  if (is.null(tool_name)) {
    return(jsonrpc_error(
      message$id,
      -32602,
      "Missing required parameter: name"
    ))
  }

  tryCatch(
    {
      result <- app$call_tool(tool_name, arguments)

      if (is.list(result) && !is.null(names(result))) {
        # Structured result: extract text parts for content, pass all as
        # structuredContent so the bridge can update multiple outputs
        text_parts <- vapply(result, function(x) {
          if (is.character(x) && nchar(x) < 10000) x else ""
        }, character(1))
        text_summary <- paste(
          text_parts[nzchar(text_parts)],
          collapse = "\n\n"
        )

        jsonrpc_response(
          message$id,
          list(
            content = list(
              list(type = "text", text = text_summary)
            ),
            structuredContent = result
          )
        )
      } else {
        jsonrpc_response(
          message$id,
          list(
            content = list(
              list(type = "text", text = as.character(result))
            )
          )
        )
      }
    },
    error = function(e) {
      jsonrpc_response(
        message$id,
        list(
          content = list(
            list(type = "text", text = paste("Error:", e$message))
          ),
          isError = TRUE
        )
      )
    }
  )
}
