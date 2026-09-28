# Streamable HTTP transport
#
# One endpoint (by default `/mcp`) takes JSON-RPC over POST and answers with
# JSON. The handler works with any Rook-style request (httpuv, Shiny,
# plumber): `mcp_http_handler()` returns a function of the request that
# answers MCP requests and returns NULL for anything else.
#
# Security:
# * Browsers attach an `Origin` header. Requests from origins other than the
#   server's own (or loopback, for a local server) are refused with 403, which
#   keeps other websites from driving a local server (DNS rebinding).
# * Allowed cross-origin callers get CORS headers so browser-based hosts can
#   connect.

#' @noRd
mcp_http_handler <- function(
  server,
  path = "/mcp",
  allowed_origins = NULL,
  local = TRUE,
  max_sessions = 256L,
  allowed_hosts = NULL
) {
  sessions <- new.env(parent = emptyenv())
  path <- normalize_endpoint_path(path)

  function(req) {
    req_path <- sub("/+$", "", req$PATH_INFO %||% "")
    if (
      !identical(req_path, path) && !(path == "" && req_path %in% c("", "/"))
    ) {
      return(NULL)
    }
    handle_http_request(
      req,
      server = server,
      sessions = sessions,
      allowed_origins = allowed_origins,
      local = local,
      max_sessions = max_sessions,
      allowed_hosts = allowed_hosts
    )
  }
}

#' @noRd
normalize_endpoint_path <- function(path) {
  path <- sub("/+$", "", path %||% "")
  if (nzchar(path) && !startsWith(path, "/")) {
    path <- paste0("/", path)
  }
  path
}

#' Answer one HTTP request to the MCP endpoint
#' @return A Rook response: `list(status, headers, body)`.
#' @noRd
handle_http_request <- function(
  req,
  server,
  sessions,
  allowed_origins = NULL,
  local = TRUE,
  max_sessions = 256L,
  allowed_hosts = NULL
) {
  method <- toupper(req$REQUEST_METHOD %||% "GET")
  headers <- request_headers(req)
  origin <- headers[["origin"]]

  # A server on this machine answers to loopback names, IP addresses, and
  # the names it was told about. A web page that re-points its own host name
  # at 127.0.0.1 (DNS rebinding) sends that name in Host, and is refused here.
  host <- headers[["host"]]
  if (isTRUE(local) && !is.null(host) && !host_trusted(host, allowed_hosts)) {
    return(http_json(
      403L,
      jsonrpc_error(
        NULL,
        RPC_INVALID_REQUEST,
        paste0(
          "Forbidden host: ",
          host,
          ". Add it to `allowed_hosts` to serve requests for it."
        )
      )
    ))
  }

  cors <- list()
  if (!is.null(origin)) {
    if (
      !origin_allowed(origin, headers, allowed_origins, local, allowed_hosts)
    ) {
      return(http_json(
        403L,
        jsonrpc_error(
          NULL,
          RPC_INVALID_REQUEST,
          paste("Forbidden origin:", origin)
        )
      ))
    }
    cors <- cors_headers(origin)
  }

  # Empty replies use 200, not 204: httpuv gzips even an empty body, and a
  # 204 with a body leaves bytes on a keep-alive connection that browsers
  # then read as a malformed next response.
  if (method == "OPTIONS") {
    requested <- headers[["access-control-request-headers"]]
    return(list(
      status = 200L,
      headers = c(
        cors,
        list(
          `Access-Control-Allow-Methods` = "POST, DELETE, OPTIONS",
          `Access-Control-Allow-Headers` = requested %||%
            "Content-Type, Accept, Authorization, MCP-Protocol-Version, Mcp-Session-Id, Mcp-Method, Mcp-Name",
          `Access-Control-Max-Age` = "86400"
        )
      ),
      body = ""
    ))
  }

  if (method == "DELETE") {
    session_id <- headers[["mcp-session-id"]]
    if (known_session(sessions, session_id)) {
      rm(list = session_id, envir = sessions)
      return(list(status = 200L, headers = cors, body = ""))
    }
    return(http_json(
      404L,
      jsonrpc_error(NULL, RPC_INVALID_REQUEST, "Session not found"),
      cors
    ))
  }

  if (method != "POST") {
    # No server-to-client stream: shinymcp never sends unsolicited messages.
    return(list(
      status = 405L,
      headers = c(
        cors,
        list(
          Allow = "POST, DELETE, OPTIONS",
          `Content-Type` = "application/json"
        )
      ),
      body = as.character(to_json(jsonrpc_error(
        NULL,
        RPC_INVALID_REQUEST,
        "Method not allowed"
      )))
    ))
  }

  body <- read_request_body(req)
  message <- tryCatch(from_json(body), error = function(e) e)
  if (inherits(message, "error")) {
    return(http_json(
      400L,
      jsonrpc_error(NULL, RPC_PARSE_ERROR, "Parse error: invalid JSON"),
      cors
    ))
  }
  if (!is.list(message)) {
    return(http_json(
      400L,
      jsonrpc_error(
        NULL,
        RPC_INVALID_REQUEST,
        "Invalid Request: expected a JSON-RPC message"
      ),
      cors
    ))
  }

  viewer <- connect_user(headers)
  transport <- list(
    transport = "http",
    headers = headers,
    user = viewer$user,
    groups = viewer$groups
  )

  if (is_json_batch(message)) {
    responses <- compact_list(lapply(message, function(msg) {
      batch_refusal(msg) %||%
        http_dispatch(
          msg,
          server,
          sessions,
          headers,
          transport,
          max_sessions
        )$response
    }))
    if (length(responses) == 0) {
      return(list(status = 202L, headers = cors, body = ""))
    }
    return(http_json(200L, lapply(responses, strip_http_status), cors))
  }

  outcome <- http_dispatch(
    message,
    server,
    sessions,
    headers,
    transport,
    max_sessions
  )
  if (is.null(outcome$response)) {
    return(list(status = 202L, headers = c(cors, outcome$headers), body = ""))
  }
  status <- attr(outcome$response, "http_status") %||% 200L
  http_json(status, outcome$response, c(cors, outcome$headers))
}

#' Validate and dispatch one message
#'
#' @return A list with `response` (or NULL), optional `status`, and extra
#'   response `headers`.
#' @noRd
http_dispatch <- function(
  message,
  server,
  sessions,
  headers,
  transport,
  max_sessions
) {
  if (!is.list(message) || is.null(names(message))) {
    return(list(
      response = jsonrpc_error(
        NULL,
        RPC_INVALID_REQUEST,
        "Invalid Request",
        status = 400L
      )
    ))
  }
  meta_version <- meta_protocol_version(message)
  is_initialize <- identical(message[["method"]], "initialize")

  if (!is.null(meta_version) && !is_initialize) {
    # Modern request: validate the mirrored headers, then serve statelessly.
    problem <- check_modern_headers(message, headers)
    if (!is.null(problem)) {
      return(list(
        response = jsonrpc_error(
          message[["id"]] %||% NULL,
          RPC_HEADER_MISMATCH,
          problem,
          status = 400L
        )
      ))
    }
    return(list(response = server$handle(message, transport)))
  }

  # Legacy request.
  header_version <- headers[["mcp-protocol-version"]]
  if (
    !is.null(header_version) && !header_version %in% SHINYMCP_PROTOCOL_VERSIONS
  ) {
    return(list(
      response = jsonrpc_error(
        message[["id"]] %||% NULL,
        RPC_INVALID_REQUEST,
        paste("Unsupported MCP-Protocol-Version:", header_version),
        data = list(
          supported = I(SHINYMCP_PROTOCOL_VERSIONS),
          requested = header_version
        ),
        status = 400L
      )
    ))
  }

  session_id <- headers[["mcp-session-id"]]
  extra_headers <- list()
  if (is_initialize) {
    session_id <- unique_id("mcp")
    session <- server$new_session()
    sessions[[session_id]] <- session
    prune_http_sessions(sessions, max_sessions)
    extra_headers[["Mcp-Session-Id"]] <- session_id
  } else if (!is.null(session_id)) {
    if (!known_session(sessions, session_id)) {
      # The client must start a new session.
      return(list(
        response = jsonrpc_error(
          message[["id"]] %||% NULL,
          RPC_INVALID_REQUEST,
          "Session not found",
          status = 404L
        )
      ))
    }
    session <- sessions[[session_id]]
  } else {
    # Clients that never initialize (or drop the header) are served leniently.
    session <- server$new_session()
  }

  transport$session <- session
  session$last_used <- as.numeric(Sys.time())
  list(response = server$handle(message, transport), headers = extra_headers)
}

#' The protocol version a request names in `_meta`, or NULL
#'
#' Read before the server checks the message, so params or `_meta` that
#' aren't objects, and a version that isn't a string, count as naming none;
#' the server refuses them.
#' @noRd
meta_protocol_version <- function(message) {
  params <- message[["params"]]
  meta <- if (is_json_object(params)) params[["_meta"]]
  version <- if (is_json_object(meta)) meta[[META_PROTOCOL_VERSION]]
  if (is_string(version)) version
}

#' Is a session id one this server handed out and still holds?
#' @noRd
known_session <- function(sessions, session_id) {
  is.character(session_id) &&
    length(session_id) == 1 &&
    nzchar(session_id) &&
    exists(session_id, envir = sessions, inherits = FALSE)
}

#' Check modern request headers against the body
#'
#' @return NULL when valid, otherwise a message for the HeaderMismatch error.
#' @noRd
check_modern_headers <- function(message, headers) {
  version <- meta_protocol_version(message)
  header_version <- headers[["mcp-protocol-version"]]
  if (is.null(header_version)) {
    return("Header mismatch: MCP-Protocol-Version header is required.")
  }
  if (!identical(header_version, version)) {
    return(sprintf(
      "Header mismatch: MCP-Protocol-Version header '%s' does not match body value '%s'.",
      header_version,
      version
    ))
  }
  if (is.null(message[["id"]])) {
    # Header rules for notifications are not defined by this revision.
    return(NULL)
  }
  # Headers mirror strings in the body. A method, or a name, that isn't one
  # is left for the server to refuse, as an invalid request or params.
  if (!is_string(message[["method"]])) {
    return(NULL)
  }
  header_method <- headers[["mcp-method"]]
  if (is.null(header_method)) {
    return("Header mismatch: Mcp-Method header is required.")
  }
  if (!identical(header_method, message[["method"]])) {
    return(sprintf(
      "Header mismatch: Mcp-Method header '%s' does not match body value '%s'.",
      header_method,
      message[["method"]]
    ))
  }
  target <- switch(
    message[["method"]],
    "tools/call" = ,
    "prompts/get" = message[["params"]][["name"]],
    "resources/read" = message[["params"]][["uri"]],
    NULL
  )
  if (is_string(target)) {
    header_name <- headers[["mcp-name"]]
    if (is.null(header_name)) {
      return("Header mismatch: Mcp-Name header is required.")
    }
    decoded <- decode_header_value(header_name)
    if (is.null(decoded)) {
      return("Header mismatch: Mcp-Name header is not a valid encoded value.")
    }
    if (!identical(decoded, target)) {
      return(sprintf(
        "Header mismatch: Mcp-Name header '%s' does not match body value '%s'.",
        decoded,
        target
      ))
    }
  }
  NULL
}

#' Decode a header value that may use the `=?base64?...?=` sentinel
#' @noRd
decode_header_value <- function(value) {
  if (startsWith(value, "=?base64?") && endsWith(value, "?=")) {
    encoded <- substr(value, 10, nchar(value) - 2)
    decoded <- tryCatch(
      rawToChar(jsonlite::base64_dec(encoded)),
      error = function(e) NULL
    )
    if (!is.null(decoded)) {
      Encoding(decoded) <- "UTF-8"
    }
    return(decoded)
  }
  value
}

#' Is a browser origin allowed to call this server?
#'
#' Allowed: origins listed in `allowed_origins` (or `"*"`); the server's own
#' origin, judged from the Host header or, behind a proxy, the forwarded
#' host or Posit Connect's app URL; and for a server bound to loopback, any
#' loopback origin (local development hosts on another port). A local
#' server counts a name as its own only if `host_trusted()`: a page that
#' re-points its own name at 127.0.0.1 sends matching Origin and Host
#' headers.
#' @noRd
origin_allowed <- function(
  origin,
  headers,
  allowed_origins = NULL,
  local = TRUE,
  allowed_hosts = NULL
) {
  if ("*" %in% allowed_origins || origin %in% allowed_origins) {
    return(TRUE)
  }
  if (identical(origin, "null")) {
    return(FALSE)
  }
  origin_host <- tolower(sub("^[a-z][a-z0-9+.-]*://", "", tolower(origin)))
  origin_host <- sub("/.*$", "", origin_host)
  own_hosts <- tolower(c(
    headers[["host"]],
    headers[["x-forwarded-host"]],
    url_host(headers[["rstudio-connect-app-base-url"]])
  ))
  own_hosts <- unlist(strsplit(own_hosts, ",\\s*"))
  if (isTRUE(local)) {
    own_hosts <- Filter(function(h) host_trusted(h, allowed_hosts), own_hosts)
  }
  if (origin_host %in% own_hosts) {
    return(TRUE)
  }
  if (isTRUE(local) && is_loopback_host(origin_host)) {
    return(TRUE)
  }
  FALSE
}

#' Can a local server answer requests for this Host?
#'
#' Loopback names, IP addresses, and `allowed_hosts`. DNS rebinding needs a
#' domain name, so a host given as an address is safe.
#' @noRd
host_trusted <- function(host, allowed_hosts = NULL) {
  is_loopback_host(host) ||
    is_ip_literal(host) ||
    host_allowed(host, allowed_hosts)
}

#' @noRd
is_ip_literal <- function(host) {
  host <- tolower(host)
  if (grepl("^\\[", host)) {
    return(grepl("^\\[[0-9a-f:.]+\\](:[0-9]*)?$", host))
  }
  grepl("^[0-9]{1,3}(\\.[0-9]{1,3}){3}(:[0-9]*)?$", host)
}

#' Is a Host header one of the allowed host names?
#'
#' Entries may name a port ("apps.example.com:8443") or not, in which case
#' any port matches.
#' @noRd
host_allowed <- function(host, allowed_hosts) {
  if (length(allowed_hosts) == 0) {
    return(FALSE)
  }
  host <- tolower(host)
  allowed <- tolower(allowed_hosts)
  "*" %in%
    allowed ||
    host %in% allowed ||
    sub(":[0-9]*$", "", host) %in% allowed
}

#' Is a host (with or without a port) this machine's loopback interface?
#' @noRd
is_loopback_host <- function(host) {
  host <- tolower(host)
  bare <- if (grepl("^\\[", host)) {
    sub("^(\\[[^]]*\\]).*$", "\\1", host)
  } else {
    sub(":[0-9]*$", "", host)
  }
  bare %in% c("localhost", "[::1]") || grepl("^127(\\.[0-9]{1,3}){3}$", bare)
}

#' @noRd
url_host <- function(url) {
  if (is.null(url) || !nzchar(url)) {
    return(NULL)
  }
  host <- sub("^[a-z][a-z0-9+.-]*://", "", tolower(url))
  sub("/.*$", "", host)
}

#' @noRd
cors_headers <- function(origin) {
  list(
    `Access-Control-Allow-Origin` = origin,
    `Access-Control-Expose-Headers` = "Mcp-Session-Id",
    Vary = "Origin"
  )
}

#' Request headers from a Rook environment, with lowercase dashed names
#' @noRd
request_headers <- function(req) {
  if (is.environment(req)) {
    keys <- ls(req, all.names = TRUE)
  } else {
    keys <- names(req)
  }
  keys <- keys[startsWith(keys, "HTTP_")]
  out <- lapply(keys, function(k) {
    v <- req[[k]]
    if (is.character(v)) v[[1]] else NULL
  })
  names(out) <- tolower(gsub("_", "-", sub("^HTTP_", "", keys)))
  compact_list(out)
}

#' @noRd
read_request_body <- function(req) {
  input <- req$rook.input
  if (is.null(input)) {
    return("")
  }
  if (is.function(input$rewind)) {
    try(input$rewind(), silent = TRUE)
  }
  raw <- input$read()
  if (is.raw(raw)) {
    body <- rawToChar(raw)
  } else {
    body <- paste(raw, collapse = "\n")
  }
  Encoding(body) <- "UTF-8"
  body
}

#' @noRd
http_json <- function(status, body, headers = list()) {
  list(
    status = as.integer(status),
    headers = c(headers, list(`Content-Type` = "application/json")),
    body = as.character(to_json(strip_http_status(body)))
  )
}

#' Evict the least recently used legacy sessions beyond the cap
#' @noRd
prune_http_sessions <- function(sessions, max_sessions = 256L) {
  ids <- ls(sessions)
  if (length(ids) <= max_sessions) {
    return(invisible(NULL))
  }
  last <- vapply(
    ids,
    function(id) sessions[[id]]$last_used %||% sessions[[id]]$created,
    numeric(1)
  )
  drop <- ids[order(last)][seq_len(length(ids) - max_sessions)]
  rm(list = drop, envir = sessions)
  invisible(NULL)
}

#' The Posit Connect user making a request, if any
#'
#' Connect passes the signed-in viewer to content in the
#' `RStudio-Connect-Credentials` header as JSON.
#' @noRd
connect_user <- function(headers) {
  none <- list(user = NULL, groups = NULL)
  # Only Posit Connect sets this header, and it replaces one a client sends.
  # Anywhere else a client could claim to be anyone.
  if (!on_posit_connect()) {
    return(none)
  }
  creds <- headers[["rstudio-connect-credentials"]]
  if (is.null(creds) || !nzchar(creds)) {
    return(none)
  }
  parsed <- tryCatch(from_json(creds), error = function(e) NULL)
  if (!is_json_object(parsed)) {
    return(none)
  }
  list(
    user = if (is_string(parsed$user)) parsed$user,
    groups = if (length(parsed$groups)) as.character(unlist(parsed$groups))
  )
}

#' Run an MCP server over HTTP with httpuv
#' @noRd
serve_http <- function(
  server,
  host = "127.0.0.1",
  port = 8080,
  path = "/mcp",
  allowed_origins = NULL,
  allowed_hosts = NULL
) {
  rlang::check_installed("httpuv", reason = "to serve MCP over HTTP.")
  local <- is_loopback_host(host) || identical(host, "::1")
  handler <- mcp_http_handler(
    server,
    path = path,
    allowed_origins = allowed_origins,
    local = local,
    allowed_hosts = allowed_hosts
  )
  app <- list(
    call = function(req) {
      response <- tryCatch(
        handler(req),
        error = function(e) {
          cli::cli_alert_danger("Internal error: {conditionMessage(e)}")
          http_json(
            500L,
            jsonrpc_error(NULL, RPC_INTERNAL_ERROR, conditionMessage(e))
          )
        }
      )
      response %||%
        list(
          status = 404L,
          headers = list(`Content-Type` = "text/plain"),
          body = paste0("Not found. The MCP endpoint is ", path, ".")
        )
    }
  )
  url <- sprintf(
    "http://%s:%d%s",
    if (grepl(":", host)) paste0("[", host, "]") else host,
    port,
    path
  )
  cli::cli_inform(
    c(
      "i" = "shinymcp: serving MCP at {.url {url}}",
      " " = "Press Ctrl+C to stop."
    ),
    class = "shinymcp_message"
  )
  httpuv::runServer(host = host, port = port, app = app)
}
