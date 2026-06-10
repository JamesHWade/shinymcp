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

  warn_host_only_trigger(app, "serve()")

  # Set up resource registry
  registry <- ResourceRegistry$new()
  registry$register(
    uri = app$resource_uri(),
    name = app$name,
    description = paste("MCP App:", app$name),
    mime_type = SHINYMCP_UI_MIME_TYPE,
    content_fn = function() app$html_resource(),
    meta = app$resource_meta()
  )

  # Register any extra resources declared via mcp_app(resources = )
  for (res in app$extra_resources()) {
    registry$register(
      uri = res$uri,
      name = res$name,
      description = res$description,
      mime_type = res$mime_type,
      content_fn = res$content_fn,
      meta = res$meta
    )
  }

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

  session <- new_mcp_session()
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
        dispatch_message(message, app, registry, session),
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

  sessions <- new.env(parent = emptyenv())

  httpuv::runServer(
    host = "127.0.0.1",
    port = port,
    app = list(
      call = function(req) {
        handle_http_request(req, app, registry, sessions)
      }
    )
  )
}

#' Handle a single MCP-over-HTTP request
#'
#' Implements basic streamable-HTTP session management: the server assigns
#' an `Mcp-Session-Id` on `initialize` and keys per-client session state
#' (protocol version, UI capability) by that header on subsequent requests,
#' so multiple clients don't clobber each other's capability negotiation.
#' Clients that never send the header share a fallback session, preserving
#' the old single-client behavior. `DELETE` terminates a session.
#'
#' @param req A Rook request object.
#' @param app McpApp object
#' @param registry ResourceRegistry object
#' @param sessions Environment mapping session id -> session state
#' @return A Rook response list.
#' @noRd
handle_http_request <- function(req, app, registry, sessions) {
  http_method <- req$REQUEST_METHOD
  client_sid <- req$HTTP_MCP_SESSION_ID

  if (identical(http_method, "DELETE")) {
    if (!is.null(client_sid) && !is.null(sessions[[client_sid]])) {
      rm(list = client_sid, envir = sessions)
    }
    return(list(status = 204L, headers = list(), body = ""))
  }

  if (!identical(http_method, "POST")) {
    return(list(
      status = 405L,
      headers = list("Content-Type" = "application/json"),
      body = to_json(jsonrpc_error(NULL, -32600, "Only POST allowed"))
    ))
  }

  body <- paste(req$rook.input$read_lines(), collapse = "\n")

  message <- tryCatch(from_json(body), error = function(e) NULL)
  is_initialize <- !is.null(message) && identical(message$method, "initialize")

  # Unknown session id on a non-initialize request: per the streamable-HTTP
  # spec the server responds 404 so the client re-initializes. This also
  # stops arbitrary header values from minting sessions.
  if (
    !is.null(client_sid) &&
      !is_initialize &&
      is.null(sessions[[client_sid]])
  ) {
    return(list(
      status = 404L,
      headers = list("Content-Type" = "application/json"),
      body = to_json(jsonrpc_error(NULL, -32001, "Session not found"))
    ))
  }

  # Resolve the session: explicit header wins; initialize without a header
  # starts a fresh session and gets its id back in the response headers.
  sid <- client_sid %||%
    (if (is_initialize) unique_id("mcp-session") else "__default__")
  session <- sessions[[sid]]
  if (is.null(session)) {
    session <- new_mcp_session()
    sessions[[sid]] <- session
    prune_http_sessions(sessions)
  }

  # Header-less initialize: also alias this session as "__default__" so a
  # client that never echoes the Mcp-Session-Id header still talks to the
  # session that holds its negotiated capabilities (single-client case;
  # concurrent header-less clients are inherently ambiguous).
  if (is_initialize && is.null(client_sid)) {
    sessions[["__default__"]] <- session
  }

  if (is.null(message)) {
    response <- jsonrpc_error(NULL, -32700, "Parse error: invalid JSON")
  } else {
    response <- tryCatch(
      dispatch_message(message, app, registry, session),
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

  headers <- list("Content-Type" = "application/json")
  if (is_initialize) {
    headers[["Mcp-Session-Id"]] <- sid
  }

  list(
    status = 200L,
    headers = headers,
    body = to_json(response)
  )
}


# ---- Message dispatch ----

#' Create per-connection MCP session state
#'
#' Tracks what the client declared during `initialize`, most importantly
#' whether it advertised the MCP Apps UI extension capability.
#'
#' @return A mutable environment.
#' @noRd
new_mcp_session <- function() {
  session <- new.env(parent = emptyenv())
  # Lenient default: clients that skip initialize still get UI metadata.
  session$client_supports_ui <- TRUE
  session$protocol_version <- SHINYMCP_PROTOCOL_VERSION
  session$created <- as.numeric(Sys.time())
  session
}

#' Maximum live HTTP sessions before the oldest are evicted
#' @noRd
SHINYMCP_MAX_HTTP_SESSIONS <- 64L

#' Evict the oldest HTTP sessions beyond the cap
#'
#' Keeps the session store bounded on long-running HTTP servers. The
#' `"__default__"` fallback session is never evicted.
#'
#' @param sessions Environment mapping session id -> session state.
#' @param max_sessions Cap on non-default sessions.
#' @noRd
prune_http_sessions <- function(
  sessions,
  max_sessions = SHINYMCP_MAX_HTTP_SESSIONS
) {
  ids <- setdiff(ls(sessions), "__default__")
  if (length(ids) <= max_sessions) {
    return(invisible(NULL))
  }
  created <- vapply(ids, function(id) sessions[[id]]$created, numeric(1))
  drop <- ids[order(created)][seq_len(length(ids) - max_sessions)]
  rm(list = drop, envir = sessions)
  invisible(NULL)
}

#' Warn when an app declares a host-only trigger mode
#'
#' `"submit"` and `"manual"` rely on the Apply button shinymcp's bundled
#' Shiny host renders; in MCP clients and `preview_app()` nothing ever
#' triggers the tools after the initial call, so outputs silently freeze.
#'
#' @param app An McpApp.
#' @param where Label for the serving context, used in the message.
#' @noRd
warn_host_only_trigger <- function(app, where) {
  trigger <- app$interaction_defaults()$trigger
  if (isTRUE(trigger %in% c("submit", "manual"))) {
    cli::cli_warn(c(
      "This app declares {.code trigger = \"{trigger}\"}, which only works inside shinymcp's Shiny host (it provides the Apply/Run button).",
      "i" = "In {where} outputs will populate once and then never update on input changes. Use {.val debounce} or {.val change} instead."
    ))
  }
}

#' Dispatch a JSON-RPC message to the appropriate handler
#'
#' Tries resource handler first, then tool dispatch, then built-in methods.
#'
#' @param message Parsed JSON-RPC message
#' @param app McpApp object
#' @param registry ResourceRegistry object
#' @param session Per-connection session state from [new_mcp_session()]
#' @return A JSON-RPC response list, or NULL for notifications
#' @noRd
dispatch_message <- function(
  message,
  app,
  registry,
  session = new_mcp_session()
) {
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
    return(handle_initialize(message, app, registry, session))
  }

  if (identical(method, "ping")) {
    return(jsonrpc_response(message$id, setNames(list(), character(0))))
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
    return(handle_tools_list(message, app, session))
  }

  if (identical(method, "tools/call")) {
    return(handle_tools_call(message, app))
  }

  jsonrpc_error(message$id, -32601, paste("Method not found:", method))
}


# ---- Built-in method handlers ----

#' Handle initialize request
#'
#' Negotiates the protocol version and records whether the client advertised
#' the MCP Apps UI extension (`io.modelcontextprotocol/ui`). When the client
#' did not, tools are still served but without UI metadata so they degrade
#' gracefully to text-only operation.
#'
#' @param message Parsed JSON-RPC message
#' @param app McpApp object
#' @param registry ResourceRegistry object
#' @param session Per-connection session state
#' @noRd
handle_initialize <- function(
  message,
  app,
  registry,
  session = new_mcp_session()
) {
  empty_obj <- setNames(list(), character(0))

  negotiated <- negotiate_protocol_version(message$params$protocolVersion)
  session$protocol_version <- negotiated
  session$client_supports_ui <- client_supports_mcp_apps(message$params)

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
#'
#' UI metadata (`_meta.ui`) is included only when the client advertised the
#' MCP Apps extension capability during initialize (or never initialized,
#' in which case we default to including it).
#'
#' @param message Parsed JSON-RPC message
#' @param app McpApp object
#' @param session Per-connection session state
#' @noRd
handle_tools_list <- function(message, app, session = new_mcp_session()) {
  tools <- app$tool_definitions(
    include_ui_meta = isTRUE(session$client_supports_ui)
  )
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
      jsonrpc_response(message$id, format_tool_result(result))
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
