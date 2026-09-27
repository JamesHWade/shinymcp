# Helpers for the serving tests: test-protocol.R, test-transport-http.R,
# test-transport-stdio.R, test-endpoint.R and test-preview.R.
#
# Names start with `serving_` so they can't collide with other helpers.

# ---- Fixture apps ----

serving_echo_tool <- function(name = "echo", reply = NULL) {
  list(
    name = name,
    description = "Echo x back.",
    inputSchema = list(
      type = "object",
      properties = list(
        x = list(type = "string", description = "Text to echo.")
      )
    ),
    fun = function(x = "default") list(out = reply %||% x)
  )
}

# An app with a model tool, a failing tool, and a tool only its UI may call.
serving_app <- function(name = "fx", tools = NULL, ...) {
  mcp_app(
    ui = htmltools::tags$div(mcp_text("out")),
    tools = tools %||%
      list(
        serving_echo_tool(),
        list(
          name = "boom",
          description = "Always fails.",
          fun = function() stop("kaboom")
        ),
        list(
          name = "refresh",
          description = "Refresh the view.",
          visibility = "app",
          fun = function() list(out = "refreshed")
        )
      ),
    name = name,
    ...
  )
}

# A tool that records the request context it ran under, via mcp_request().
serving_recorder <- function(name = "context") {
  recorder <- new.env(parent = emptyenv())
  recorder$calls <- 0L
  recorder$context <- NULL
  recorder$tool <- list(
    name = name,
    description = "Record the request context.",
    fun = function() {
      recorder$calls <- recorder$calls + 1L
      recorder$context <- mcp_request()
      list(out = "recorded")
    }
  )
  recorder
}

# ---- JSON-RPC messages ----

serving_rpc <- function(method, params = NULL, id = 1) {
  message <- list(jsonrpc = "2.0", id = id, method = method, params = params)
  if (is.null(id)) {
    message$id <- NULL
  }
  if (is.null(params)) {
    message$params <- NULL
  }
  message
}

serving_ui_capabilities <- function() {
  list(
    extensions = list(
      `io.modelcontextprotocol/ui` = list(
        mimeTypes = list("text/html;profile=mcp-app")
      )
    )
  )
}

serving_initialize <- function(
  ui = TRUE,
  version = "2025-06-18",
  client = list(name = "test-client", version = "1.0.0"),
  id = 1
) {
  serving_rpc(
    "initialize",
    list(
      protocolVersion = version,
      capabilities = if (ui) serving_ui_capabilities() else json_object(),
      clientInfo = client
    ),
    id = id
  )
}

# A request in the stateless 2026-07-28 era: version, client and
# capabilities travel in params._meta.
serving_modern <- function(
  method,
  params = list(),
  id = 1,
  ui = TRUE,
  version = "2026-07-28",
  client = list(name = "test-client", version = "1.0.0")
) {
  meta <- params[["_meta"]] %||% list()
  meta[["io.modelcontextprotocol/protocolVersion"]] <- version
  meta[["io.modelcontextprotocol/clientInfo"]] <- client
  meta[["io.modelcontextprotocol/clientCapabilities"]] <- if (ui) {
    serving_ui_capabilities()
  } else {
    json_object()
  }
  params[["_meta"]] <- meta
  serving_rpc(method, params, id = id)
}

# The headers a modern client mirrors from the body.
serving_modern_headers <- function(message) {
  headers <- list(
    `MCP-Protocol-Version` = message$params[["_meta"]][[
      "io.modelcontextprotocol/protocolVersion"
    ]],
    `Mcp-Method` = message$method
  )
  target <- switch(
    message$method,
    "tools/call" = message$params$name,
    "resources/read" = message$params$uri,
    NULL
  )
  if (!is.null(target)) {
    headers$`Mcp-Name` <- target
  }
  headers
}

serving_json_text <- function(x) {
  as.character(to_json(x))
}

# ---- Fake Rook requests ----

# A Rook input stream: read() consumes the body, rewind() restores it.
serving_rook_input <- function(bytes) {
  state <- new.env(parent = emptyenv())
  state$consumed <- FALSE
  list(
    read = function(l = -1L) {
      if (state$consumed) {
        return(raw())
      }
      state$consumed <- TRUE
      bytes
    },
    rewind = function() {
      state$consumed <- FALSE
      invisible(NULL)
    }
  )
}

# A Rook request environment like the ones httpuv and Shiny pass handlers.
# `headers` uses HTTP names (`Mcp-Session-Id`); `body` is a message list or
# a string.
serving_request <- function(
  body = NULL,
  method = "POST",
  path = "/mcp",
  headers = list()
) {
  req <- new.env(parent = emptyenv())
  req$REQUEST_METHOD <- method
  if (!is.null(path)) {
    req$PATH_INFO <- path
  }
  req$QUERY_STRING <- ""
  for (name in names(headers)) {
    key <- paste0("HTTP_", toupper(gsub("-", "_", name, fixed = TRUE)))
    assign(key, headers[[name]], envir = req)
  }
  if (!is.null(body)) {
    if (!is.character(body)) {
      body <- serving_json_text(body)
    }
    req[["rook.input"]] <- serving_rook_input(charToRaw(enc2utf8(body)))
  }
  req
}

# Parse the JSON body of a Rook response (or of a Shiny httpResponse).
serving_body <- function(response) {
  body <- response$body %||% response$content
  jsonlite::fromJSON(body, simplifyVector = FALSE)
}

# ---- Live servers ----

# Start httpuv on a free loopback port, or skip the test.
serving_start <- function(call) {
  started <- tryCatch(
    start_local_server("127.0.0.1", NULL, list(call = call)),
    error = function(e) NULL
  )
  if (is.null(started)) {
    testthat::skip("Can't start a local httpuv server here.")
  }
  list(
    port = started$port,
    stop = function() httpuv::stopServer(started$server)
  )
}

# Make one HTTP request to a server running in this R process.
#
# httpuv hands requests to R on the main thread, so a blocking client would
# wait forever. This one writes the request on a non-blocking socket and
# keeps servicing httpuv until the whole response (by Content-Length) is in.
serving_http <- function(
  port,
  method = "GET",
  path = "/",
  body = NULL,
  headers = list(),
  timeout = 10
) {
  if (!is.null(body) && !is.character(body)) {
    body <- serving_json_text(body)
  }
  payload <- if (is.null(body)) raw() else charToRaw(enc2utf8(body))
  lines <- c(
    sprintf("%s %s HTTP/1.1", method, path),
    sprintf("Host: 127.0.0.1:%d", port),
    "Connection: close",
    "Accept-Encoding: identity",
    sprintf("Content-Length: %d", length(payload)),
    if (length(headers)) paste0(names(headers), ": ", unlist(headers))
  )
  con <- socketConnection(
    "127.0.0.1",
    port = port,
    blocking = FALSE,
    open = "r+b",
    timeout = timeout
  )
  on.exit(close(con), add = TRUE)
  writeBin(
    c(charToRaw(paste0(paste(lines, collapse = "\r\n"), "\r\n\r\n")), payload),
    con
  )
  flush(con)

  received <- raw()
  deadline <- Sys.time() + timeout
  repeat {
    httpuv::service(0.01)
    chunk <- readBin(con, "raw", 65536L)
    if (length(chunk)) {
      received <- c(received, chunk)
    }
    response <- serving_parse_response(received)
    if (!is.null(response)) {
      return(response)
    }
    if (Sys.time() > deadline) {
      stop(
        "No complete HTTP response from port ",
        port,
        " within ",
        timeout,
        " seconds.",
        call. = FALSE
      )
    }
  }
}

# A complete HTTP/1.1 response as list(status, headers, body), or NULL while
# bytes are still arriving. Header names are lowercase.
serving_parse_response <- function(bytes) {
  end <- grepRaw(charToRaw("\r\n\r\n"), bytes, fixed = TRUE)
  if (length(end) == 0) {
    return(NULL)
  }
  head <- strsplit(rawToChar(bytes[seq_len(end - 1)]), "\r\n", fixed = TRUE)[[
    1
  ]]
  rest <- bytes[-seq_len(end + 3)]
  fields <- head[-1]
  headers <- as.list(trimws(sub("^[^:]*:", "", fields)))
  names(headers) <- tolower(sub(":.*$", "", fields))
  size <- as.integer(headers[["content-length"]] %||% NA)
  if (is.na(size) || length(rest) < size) {
    return(NULL)
  }
  body <- rawToChar(rest[seq_len(size)])
  Encoding(body) <- "UTF-8"
  list(
    status = as.integer(strsplit(head[[1]], " ", fixed = TRUE)[[1]][[2]]),
    headers = headers,
    body = body
  )
}

# ---- Preview pages ----

# The configuration JSON embedded in a preview page.
serving_preview_config <- function(page) {
  pattern <- '<script type="application/json" id="preview-config">(.*?)</script>'
  match <- regmatches(page, regexec(pattern, page, perl = TRUE))[[1]]
  if (length(match) < 2) {
    return(NULL)
  }
  jsonlite::fromJSON(match[[2]], simplifyVector = FALSE)
}
