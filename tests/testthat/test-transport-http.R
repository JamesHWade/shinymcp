# The Streamable HTTP transport (R/transport-http.R). Most tests call the
# handler with fake Rook requests; one makes real requests through httpuv.

new_handler <- function(app = serving_app(), ...) {
  mcp_http_handler(McpServer$new(app), ...)
}

# Answer one request with a server and a session store the test can inspect.
send <- function(message, server, sessions, headers = list(), ...) {
  handle_http_request(
    serving_request(message, headers = headers),
    server,
    sessions,
    ...
  )
}

new_sessions <- function() {
  new.env(parent = emptyenv())
}

open_session <- function(server, sessions, ui = TRUE) {
  response <- send(serving_initialize(ui = ui), server, sessions)
  response$headers[["Mcp-Session-Id"]]
}

# ---- Routing ----

test_that("the handler answers only its endpoint path", {
  handler <- new_handler()
  ping <- serving_rpc("ping")

  expect_equal(handler(serving_request(ping, path = "/mcp"))$status, 200L)
  expect_equal(handler(serving_request(ping, path = "/mcp/"))$status, 200L)
  for (path in list(
    "/",
    "",
    "/other",
    "/mcpx",
    "/mcp/extra",
    "/api/mcp",
    NULL
  )) {
    expect_null(handler(serving_request(ping, path = path)))
  }
})

test_that("endpoint paths are normalized", {
  expect_equal(normalize_endpoint_path("/mcp"), "/mcp")
  expect_equal(normalize_endpoint_path("mcp"), "/mcp")
  expect_equal(normalize_endpoint_path("/api/mcp//"), "/api/mcp")
  expect_equal(normalize_endpoint_path("/"), "")
  expect_equal(normalize_endpoint_path(""), "")
  expect_equal(normalize_endpoint_path(NULL), "")

  handler <- new_handler(path = "api/mcp/")
  expect_equal(
    handler(serving_request(serving_rpc("ping"), path = "/api/mcp"))$status,
    200L
  )
  expect_null(handler(serving_request(serving_rpc("ping"), path = "/mcp")))
})

test_that("an empty path serves MCP at the root", {
  handler <- new_handler(path = "/")
  expect_equal(
    handler(serving_request(serving_rpc("ping"), path = "/"))$status,
    200L
  )
  expect_equal(
    handler(serving_request(serving_rpc("ping"), path = ""))$status,
    200L
  )
  expect_null(handler(serving_request(serving_rpc("ping"), path = "/mcp")))
})

# ---- Legacy sessions ----

test_that("initialize starts a session and returns its id", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  response <- send(serving_initialize(version = "2025-06-18"), server, sessions)

  expect_equal(response$status, 200L)
  expect_equal(response$headers[["Content-Type"]], "application/json")
  id <- response$headers[["Mcp-Session-Id"]]
  expect_match(id, "^mcp-[0-9a-f]{16}$")
  expect_equal(ls(sessions), id)
  expect_true(sessions[[id]]$initialized)
  expect_equal(sessions[[id]]$protocol_version, "2025-06-18")
  expect_equal(serving_body(response)$result$protocolVersion, "2025-06-18")
})

test_that("an initialize that fails leaves no session behind", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  for (body in c(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":5}',
    '{"jsonrpc":"2.0","id":null,"method":"initialize","params":{}}'
  )) {
    response <- send(body, server, sessions)
    expect_false(is.null(serving_body(response)$error), info = body)
    expect_null(response$headers[["Mcp-Session-Id"]])
  }
  expect_length(ls(sessions), 0)
})

test_that("each session keeps the capabilities its client declared", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  with_ui <- open_session(server, sessions, ui = TRUE)
  without_ui <- open_session(server, sessions, ui = FALSE)
  expect_false(identical(with_ui, without_ui))

  list_tools <- function(id) {
    body <- serving_body(send(
      serving_rpc("tools/list", id = 2),
      server,
      sessions,
      list(`Mcp-Session-Id` = id)
    ))
    vapply(body$result$tools, function(t) t$name, character(1))
  }
  expect_equal(list_tools(with_ui), c("echo", "boom", "refresh"))
  expect_equal(list_tools(without_ui), c("echo", "boom"))
})

test_that("requests on an open session don't start another", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  id <- open_session(server, sessions)
  response <- send(
    serving_rpc("tools/list", id = 2),
    server,
    sessions,
    list(`Mcp-Session-Id` = id)
  )
  expect_equal(response$status, 200L)
  expect_null(response$headers[["Mcp-Session-Id"]])
  expect_equal(ls(sessions), id)
})

test_that("a legacy request refreshes its session's last use", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  id <- open_session(server, sessions)
  sessions[[id]]$last_used <- 0
  send(
    serving_rpc("ping", id = 2),
    server,
    sessions,
    list(`Mcp-Session-Id` = id)
  )
  expect_gt(sessions[[id]]$last_used, 0)
})

test_that("an unknown session id gets 404 and starts no session", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  response <- send(
    serving_rpc("tools/list", id = 7),
    server,
    sessions,
    list(`Mcp-Session-Id` = "mcp-made-up")
  )

  expect_equal(response$status, 404L)
  body <- serving_body(response)
  expect_equal(body$id, 7)
  expect_equal(body$error$code, -32600L)
  expect_equal(body$error$message, "Session not found")
  expect_length(ls(sessions), 0)
})

test_that("requests without a session id are served leniently", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  response <- send(serving_rpc("tools/list"), server, sessions)

  expect_equal(response$status, 200L)
  tools <- serving_body(response)$result$tools
  # As a client with MCP Apps support: every tool, with the nested ui block.
  expect_length(tools, 3)
  expect_equal(tools[[1]][["_meta"]][["ui"]]$resourceUri, "ui://fx")
  expect_length(ls(sessions), 0)
})

test_that("DELETE ends a session", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  id <- open_session(server, sessions)

  deleted <- handle_http_request(
    serving_request(method = "DELETE", headers = list(`Mcp-Session-Id` = id)),
    server,
    sessions
  )
  expect_equal(deleted$status, 200L)
  expect_equal(deleted$body, "")
  expect_length(ls(sessions), 0)

  stale <- send(
    serving_rpc("ping", id = 2),
    server,
    sessions,
    list(`Mcp-Session-Id` = id)
  )
  expect_equal(stale$status, 404L)
})

test_that("DELETE of an unknown or missing session gets 404", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  for (headers in list(list(`Mcp-Session-Id` = "mcp-made-up"), list())) {
    response <- handle_http_request(
      serving_request(method = "DELETE", headers = headers),
      server,
      sessions
    )
    expect_equal(response$status, 404L)
    expect_equal(response$headers[["Content-Type"]], "application/json")
    expect_equal(serving_body(response)$error$message, "Session not found")
  }
})

test_that("an empty Mcp-Session-Id header is treated as an unknown session", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  empty <- list(`Mcp-Session-Id` = "")
  expect_equal(send(serving_rpc("ping"), server, sessions, empty)$status, 404L)
  deleted <- handle_http_request(
    serving_request(method = "DELETE", headers = empty),
    server,
    sessions
  )
  expect_equal(deleted$status, 404L)
})

test_that("sessions beyond the cap are evicted, least recently used first", {
  server <- McpServer$new(serving_app())
  sessions <- new_sessions()
  first <- open_session(server, sessions)
  second <- open_session(server, sessions)
  # The first session was used more recently than the second.
  sessions[[first]]$last_used <- 2
  sessions[[second]]$last_used <- 1

  response <- send(serving_initialize(), server, sessions, max_sessions = 2L)
  third <- response$headers[["Mcp-Session-Id"]]
  expect_setequal(ls(sessions), c(first, third))
  expect_equal(
    send(
      serving_rpc("ping"),
      server,
      sessions,
      list(`Mcp-Session-Id` = second)
    )$status,
    404L
  )
  expect_equal(
    send(
      serving_rpc("ping"),
      server,
      sessions,
      list(`Mcp-Session-Id` = first)
    )$status,
    200L
  )
})

test_that("mcp_http_handler() caps its session store", {
  handler <- new_handler(max_sessions = 1L)
  first <- handler(serving_request(serving_initialize()))$headers[[
    "Mcp-Session-Id"
  ]]
  second <- handler(serving_request(serving_initialize()))$headers[[
    "Mcp-Session-Id"
  ]]
  ping <- function(id) {
    handler(serving_request(
      serving_rpc("ping"),
      headers = list(`Mcp-Session-Id` = id)
    ))$status
  }
  expect_equal(ping(second), 200L)
  expect_equal(ping(first), 404L)
})

test_that("prune_http_sessions() keeps the most recently used sessions", {
  sessions <- new_sessions()
  for (i in 1:5) {
    session <- new_mcp_session()
    session$created <- i
    sessions[[paste0("s", i)]] <- session
  }
  # Last use counts over creation time.
  sessions$s1$last_used <- 10

  prune_http_sessions(sessions, max_sessions = 3)
  expect_setequal(ls(sessions), c("s1", "s4", "s5"))
})

test_that("prune_http_sessions() leaves a store under the cap alone", {
  sessions <- new_sessions()
  sessions$a <- new_mcp_session()
  sessions$b <- new_mcp_session()
  expect_null(prune_http_sessions(sessions, max_sessions = 2))
  expect_setequal(ls(sessions), c("a", "b"))
})

# ---- Methods and bodies ----

test_that("GET and other methods get 405 with an Allow header", {
  handler <- new_handler()
  for (method in c("GET", "PUT", "PATCH", "HEAD")) {
    response <- handler(serving_request(method = method))
    expect_equal(response$status, 405L)
    expect_equal(response$headers$Allow, "POST, DELETE, OPTIONS")
    expect_equal(response$headers[["Content-Type"]], "application/json")
    body <- serving_body(response)
    expect_equal(body$error$code, -32600L)
    expect_equal(body$error$message, "Method not allowed")
  }
  # A request without a method is taken as GET.
  req <- serving_request(serving_rpc("ping"))
  rm("REQUEST_METHOD", envir = req)
  expect_equal(handler(req)$status, 405L)
})

test_that("request methods are case-insensitive", {
  handler <- new_handler()
  expect_equal(
    handler(serving_request(serving_rpc("ping"), method = "post"))$status,
    200L
  )
})

test_that("OPTIONS preflight answers 200 with CORS headers", {
  handler <- new_handler(path = "/mcp")
  response <- handler(serving_request(
    method = "OPTIONS",
    headers = list(
      Origin = "http://localhost:5173",
      `Access-Control-Request-Method` = "POST",
      `Access-Control-Request-Headers` = "content-type, mcp-protocol-version, x-custom"
    )
  ))

  # 200, not 204: see the comment in handle_http_request() about httpuv gzip.
  expect_equal(response$status, 200L)
  expect_equal(response$body, "")
  headers <- response$headers
  expect_equal(
    headers[["Access-Control-Allow-Origin"]],
    "http://localhost:5173"
  )
  expect_equal(
    headers[["Access-Control-Allow-Methods"]],
    "POST, DELETE, OPTIONS"
  )
  expect_equal(
    headers[["Access-Control-Allow-Headers"]],
    "content-type, mcp-protocol-version, x-custom"
  )
  expect_equal(headers[["Access-Control-Max-Age"]], "86400")
  expect_equal(headers[["Access-Control-Expose-Headers"]], "Mcp-Session-Id")
  expect_equal(headers$Vary, "Origin")
})

test_that("OPTIONS without requested headers allows the MCP headers", {
  handler <- new_handler()
  response <- handler(serving_request(method = "OPTIONS"))
  expect_equal(response$status, 200L)
  allowed <- strsplit(
    response$headers[["Access-Control-Allow-Headers"]],
    ",\\s*"
  )[[1]]
  expect_true(all(
    c(
      "Content-Type",
      "MCP-Protocol-Version",
      "Mcp-Session-Id",
      "Mcp-Method",
      "Mcp-Name"
    ) %in%
      allowed
  ))
  # No Origin, no CORS headers.
  expect_null(response$headers[["Access-Control-Allow-Origin"]])
})

test_that("a notification gets 202 with an empty body", {
  handler <- new_handler()
  response <- handler(serving_request(serving_rpc(
    "notifications/initialized",
    id = NULL
  )))
  expect_equal(response$status, 202L)
  expect_equal(response$body, "")
})

test_that("a batch gets one response per request, in order", {
  handler <- new_handler()
  batch <- list(
    serving_rpc("ping", id = 1),
    serving_rpc("notifications/initialized", id = NULL),
    serving_rpc(
      "tools/call",
      list(name = "echo", arguments = list(x = "batched")),
      id = 2
    ),
    serving_rpc("no/such/method", id = 3)
  )
  response <- handler(serving_request(batch))

  expect_equal(response$status, 200L)
  body <- serving_body(response)
  expect_length(body, 3)
  expect_equal(vapply(body, function(r) r$id, numeric(1)), c(1, 2, 3))
  expect_equal(body[[2]]$result$structuredContent$out, "batched")
  expect_equal(body[[3]]$error$code, -32601L)
})

test_that("a batch of notifications gets 202 and no body", {
  handler <- new_handler()
  batch <- list(
    serving_rpc("notifications/initialized", id = NULL),
    serving_rpc("notifications/cancelled", list(requestId = 1), id = NULL)
  )
  response <- handler(serving_request(batch))
  expect_equal(response$status, 202L)
  expect_equal(response$body, "")
})

test_that("an entry in a batch that isn't a message gets its own error", {
  handler <- new_handler()
  response <- handler(serving_request(
    '[{"jsonrpc":"2.0","id":1,"method":"ping"}, 5]'
  ))
  expect_equal(response$status, 200L)
  body <- serving_body(response)
  expect_length(body, 2)
  expect_equal(body[[1]]$result, setNames(list(), character()))
  expect_null(body[[2]]$id)
  expect_equal(body[[2]]$error$code, -32600L)

  # Whatever comes first: an array of anything is a batch.
  response <- handler(serving_request(
    '[5, {"jsonrpc":"2.0","id":1,"method":"ping"}]'
  ))
  expect_equal(response$status, 200L)
  body <- serving_body(response)
  expect_length(body, 2)
  expect_equal(body[[1]]$error$code, -32600L)
  expect_equal(body[[2]]$id, 1L)
  expect_equal(body[[2]]$result, setNames(list(), character()))

  body <- serving_body(handler(serving_request("[1, 2]")))
  expect_length(body, 2)
  expect_equal(
    vapply(body, function(r) r$error$code, integer(1)),
    c(-32600L, -32600L)
  )
})

test_that("a body that isn't JSON gets 400 with a parse error", {
  handler <- new_handler()
  for (body in c("{not json", "", "   ")) {
    response <- handler(serving_request(body))
    expect_equal(response$status, 400L)
    parsed <- serving_body(response)
    expect_null(parsed$id)
    expect_equal(parsed$error$code, -32700L)
  }
  # No body at all.
  response <- handler(serving_request())
  expect_equal(response$status, 400L)
  expect_equal(serving_body(response)$error$code, -32700L)
})

test_that("JSON that isn't a JSON-RPC message is rejected with 400", {
  handler <- new_handler()
  for (body in c(
    "42",
    '"ping"',
    "[]",
    '{"id": 1, "method": "ping"}'
  )) {
    response <- handler(serving_request(body))
    expect_equal(response$status, 400L, info = body)
    expect_true(
      serving_body(response)$error$code %in% c(-32700L, -32600L),
      info = body
    )
  }
})

test_that("params that aren't an object get invalid params, not an internal error", {
  handler <- new_handler()
  for (body in c(
    '{"jsonrpc":"2.0","id":1,"method":"ping","params":5}',
    '{"jsonrpc":"2.0","id":1,"method":"ping","params":"x"}',
    '{"jsonrpc":"2.0","id":1,"method":"ping","params":[1]}',
    '{"jsonrpc":"2.0","id":1,"method":"ping","params":{"_meta":5}}'
  )) {
    response <- handler(serving_request(body))
    expect_equal(response$status, 400L, info = body)
    expect_equal(serving_body(response)$error$code, -32602L, info = body)
  }
})

test_that("a protocol version in _meta that isn't a string gets invalid params", {
  handler <- new_handler()
  headers <- list(`MCP-Protocol-Version` = "2026-07-28", `Mcp-Method` = "ping")
  for (version in c('{"v":"2026-07-28"}', '["2026-07-28"]', "20260728")) {
    body <- sprintf(
      '{"jsonrpc":"2.0","id":1,"method":"ping","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":%s}}}',
      version
    )
    response <- handler(serving_request(body, headers = headers))
    expect_equal(response$status, 400L, info = version)
    expect_equal(serving_body(response)$error$code, -32602L, info = version)
  }
})

test_that("a method or name that isn't a string is refused, not a header mismatch", {
  handler <- new_handler()
  meta <- '"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}'
  cases <- list(
    list(
      body = sprintf(
        '{"jsonrpc":"2.0","id":1,"method":{},"params":{%s}}',
        meta
      ),
      method = "ping",
      code = -32600L,
      status = 400L
    ),
    list(
      body = sprintf('{"jsonrpc":"2.0","id":1,"method":5,"params":{%s}}', meta),
      method = "5",
      code = -32600L,
      status = 400L
    ),
    list(
      body = sprintf(
        '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":{"x":1},%s}}',
        meta
      ),
      method = "tools/call",
      code = -32602L
    )
  )
  for (case in cases) {
    headers <- list(
      `MCP-Protocol-Version` = "2026-07-28",
      `Mcp-Method` = case$method,
      `Mcp-Name` = "x"
    )
    response <- handler(serving_request(case$body, headers = headers))
    error <- serving_body(response)$error
    if (!is.null(case$status)) {
      expect_equal(response$status, case$status, info = case$body)
    }
    expect_equal(error$code, case$code, info = case$body)
    expect_true(is.character(error$message) && length(error$message) == 1)
  }
})

test_that("a request body is parsed as JSON text, never read as a file path", {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeLines('{"jsonrpc":"2.0","id":"read-from-disk","method":"ping"}', path)
  handler <- new_handler()
  response <- handler(serving_request(path))
  expect_equal(response$status, 400L)
  expect_equal(serving_body(response)$error$code, -32700L)
})

test_that("the request body is rewound before it is read", {
  handler <- new_handler()
  req <- serving_request(serving_rpc("ping", id = 5))
  # Another handler read the body first.
  req[["rook.input"]]$read()
  response <- handler(req)
  expect_equal(response$status, 200L)
  expect_equal(serving_body(response)$id, 5)
})

test_that("bodies read as lines of text are accepted", {
  handler <- new_handler()
  req <- serving_request(path = "/mcp")
  req[["rook.input"]] <- list(read = function(...) {
    c('{"jsonrpc":"2.0",', '"id":6,"method":"ping"}')
  })
  response <- handler(req)
  expect_equal(response$status, 200L)
  expect_equal(serving_body(response)$id, 6)
})

test_that("UTF-8 request bodies round trip", {
  handler <- new_handler()
  text <- "héllo ✓ 世界"
  response <- handler(serving_request(serving_rpc(
    "tools/call",
    list(name = "echo", arguments = list(x = text))
  )))
  expect_equal(response$status, 200L)
  expect_identical(serving_body(response)$result$structuredContent$out, text)
})

# ---- Protocol version headers ----

test_that("legacy requests with an unsupported MCP-Protocol-Version header get 400", {
  handler <- new_handler()
  response <- handler(serving_request(
    serving_rpc("tools/list", id = 4),
    headers = list(`MCP-Protocol-Version` = "1999-01-01")
  ))
  expect_equal(response$status, 400L)
  body <- serving_body(response)
  expect_equal(body$id, 4)
  expect_equal(body$error$code, -32600L)
  expect_equal(
    body$error$message,
    "Unsupported MCP-Protocol-Version: 1999-01-01"
  )
  expect_equal(body$error$data$requested, "1999-01-01")
  expect_equal(unlist(body$error$data$supported), SHINYMCP_PROTOCOL_VERSIONS)
})

test_that("legacy requests with a supported MCP-Protocol-Version header are served", {
  handler <- new_handler()
  for (version in SHINYMCP_PROTOCOL_VERSIONS) {
    response <- handler(serving_request(
      serving_rpc("ping"),
      headers = list(`MCP-Protocol-Version` = version)
    ))
    expect_equal(response$status, 200L, info = version)
  }
})

test_that("modern requests with matching headers are served without a session", {
  handler <- new_handler()
  message <- serving_modern(
    "tools/call",
    list(name = "echo", arguments = list(x = "stateless"))
  )
  response <- handler(serving_request(
    message,
    headers = serving_modern_headers(message)
  ))

  expect_equal(response$status, 200L)
  expect_null(response$headers[["Mcp-Session-Id"]])
  result <- serving_body(response)$result
  expect_equal(result$structuredContent$out, "stateless")
  expect_equal(result$resultType, "complete")
})

test_that("modern requests ignore legacy session ids", {
  handler <- new_handler()
  message <- serving_modern("tools/list")
  headers <- c(
    serving_modern_headers(message),
    list(`Mcp-Session-Id` = "mcp-long-gone")
  )
  expect_equal(
    handler(serving_request(message, headers = headers))$status,
    200L
  )
})

expect_header_mismatch <- function(response, pattern) {
  expect_equal(response$status, 400L)
  body <- serving_body(response)
  expect_equal(body$error$code, -32020L)
  expect_match(body$error$message, pattern, fixed = TRUE)
  invisible(body)
}

test_that("modern requests need an MCP-Protocol-Version header that matches the body", {
  handler <- new_handler()
  message <- serving_modern("tools/list", id = 8)
  headers <- serving_modern_headers(message)

  missing <- headers
  missing[["MCP-Protocol-Version"]] <- NULL
  body <- expect_header_mismatch(
    handler(serving_request(message, headers = missing)),
    "MCP-Protocol-Version header is required"
  )
  expect_equal(body$id, 8)

  different <- headers
  different[["MCP-Protocol-Version"]] <- "2025-06-18"
  expect_header_mismatch(
    handler(serving_request(message, headers = different)),
    "MCP-Protocol-Version header '2025-06-18' does not match body value '2026-07-28'"
  )
})

test_that("modern requests need an Mcp-Method header that matches the body", {
  handler <- new_handler()
  message <- serving_modern("tools/list")
  headers <- serving_modern_headers(message)

  missing <- headers
  missing[["Mcp-Method"]] <- NULL
  expect_header_mismatch(
    handler(serving_request(message, headers = missing)),
    "Mcp-Method header is required"
  )

  different <- headers
  different[["Mcp-Method"]] <- "resources/list"
  expect_header_mismatch(
    handler(serving_request(message, headers = different)),
    "Mcp-Method header 'resources/list' does not match body value 'tools/list'"
  )
})

test_that("tools/call needs an Mcp-Name header that matches the tool", {
  handler <- new_handler()
  message <- serving_modern("tools/call", list(name = "echo"))
  headers <- serving_modern_headers(message)
  expect_equal(headers[["Mcp-Name"]], "echo")
  expect_equal(
    handler(serving_request(message, headers = headers))$status,
    200L
  )

  missing <- headers
  missing[["Mcp-Name"]] <- NULL
  expect_header_mismatch(
    handler(serving_request(message, headers = missing)),
    "Mcp-Name header is required"
  )

  different <- headers
  different[["Mcp-Name"]] <- "boom"
  expect_header_mismatch(
    handler(serving_request(message, headers = different)),
    "Mcp-Name header 'boom' does not match body value 'echo'"
  )
})

test_that("resources/read needs an Mcp-Name header that matches the URI", {
  handler <- new_handler()
  message <- serving_modern("resources/read", list(uri = "ui://fx"))
  headers <- serving_modern_headers(message)
  expect_equal(
    handler(serving_request(message, headers = headers))$status,
    200L
  )

  different <- headers
  different[["Mcp-Name"]] <- "ui://other"
  expect_header_mismatch(
    handler(serving_request(message, headers = different)),
    "does not match body value 'ui://fx'"
  )
})

test_that("Mcp-Name can carry non-ASCII names base64-encoded", {
  uri <- "ui://fx/données"
  app <- serving_app(resources = setNames(list("bonjour"), uri))
  handler <- new_handler(app)
  message <- serving_modern("resources/read", list(uri = uri))
  headers <- serving_modern_headers(message)
  headers[["Mcp-Name"]] <- paste0(
    "=?base64?",
    jsonlite::base64_enc(charToRaw(enc2utf8(uri))),
    "?="
  )

  response <- handler(serving_request(message, headers = headers))
  expect_equal(response$status, 200L)
  expect_equal(serving_body(response)$result$contents[[1]]$text, "bonjour")

  headers[["Mcp-Name"]] <- paste0(
    "=?base64?",
    jsonlite::base64_enc(charToRaw("ui://fx/other")),
    "?="
  )
  expect_header_mismatch(
    handler(serving_request(message, headers = headers)),
    "does not match"
  )
})

test_that("an Mcp-Name that doesn't decode is a header mismatch", {
  handler <- new_handler()
  message <- serving_modern("tools/call", list(name = "echo"))
  headers <- serving_modern_headers(message)
  # Decodes to "a\0b", which can't be a string.
  headers[["Mcp-Name"]] <- "=?base64?YQBi?="
  expect_header_mismatch(
    handler(serving_request(message, headers = headers)),
    "Mcp-Name header is not a valid encoded value"
  )
})

test_that("decode_header_value() decodes the base64 sentinel and passes other values through", {
  expect_equal(decode_header_value("echo"), "echo")
  expect_equal(decode_header_value("=?base64?ZWNobw==?="), "echo")
  expect_equal(decode_header_value("=?base64?ZWNobw=="), "=?base64?ZWNobw==")
  expect_equal(decode_header_value("ZWNobw==?="), "ZWNobw==?=")

  text <- "données ✓"
  decoded <- decode_header_value(paste0(
    "=?base64?",
    jsonlite::base64_enc(charToRaw(enc2utf8(text))),
    "?="
  ))
  expect_identical(decoded, text)
  expect_equal(Encoding(decoded), "UTF-8")

  expect_null(decode_header_value("=?base64?YQBi?="))
})

test_that("methods without a named target need no Mcp-Name", {
  handler <- new_handler()
  for (method in c("tools/list", "resources/list", "ping", "server/discover")) {
    message <- serving_modern(method)
    headers <- serving_modern_headers(message)
    expect_null(headers[["Mcp-Name"]])
    expect_equal(
      handler(serving_request(message, headers = headers))$status,
      200L,
      info = method
    )
  }
})

test_that("modern notifications need only the protocol version header", {
  handler <- new_handler()
  message <- serving_modern("notifications/initialized", id = NULL)
  response <- handler(serving_request(
    message,
    headers = list(`MCP-Protocol-Version` = "2026-07-28")
  ))
  expect_equal(response$status, 202L)
  expect_equal(response$body, "")

  response <- handler(serving_request(message))
  expect_header_mismatch(response, "MCP-Protocol-Version header is required")
})

test_that("modern requests with an unsupported version get 400 with the supported list", {
  handler <- new_handler()
  message <- serving_modern("tools/list", version = "2027-01-01")
  response <- handler(serving_request(
    message,
    headers = serving_modern_headers(message)
  ))
  expect_equal(response$status, 400L)
  body <- serving_body(response)
  expect_equal(body$error$code, -32022L)
  expect_equal(body$error$data$requested, "2027-01-01")
  expect_equal(unlist(body$error$data$supported), SHINYMCP_PROTOCOL_VERSIONS)
})

test_that("unknown modern methods get 404", {
  handler <- new_handler()
  message <- serving_modern("tools/destroy")
  response <- handler(serving_request(
    message,
    headers = serving_modern_headers(message)
  ))
  expect_equal(response$status, 404L)
  expect_equal(serving_body(response)$error$code, -32601L)
})

# ---- Origins and CORS ----

test_that("requests without an Origin header are allowed and get no CORS headers", {
  handler <- new_handler(local = FALSE)
  response <- handler(serving_request(
    serving_rpc("ping"),
    headers = list(Host = "mcp.example.com")
  ))
  expect_equal(response$status, 200L)
  expect_null(response$headers[["Access-Control-Allow-Origin"]])
})

test_that("browsers on the server's own origin are allowed", {
  expect_true(origin_allowed(
    "https://mcp.example.com",
    list(host = "mcp.example.com"),
    local = FALSE
  ))
  expect_true(origin_allowed(
    "http://localhost:8080",
    list(host = "localhost:8080"),
    local = FALSE
  ))
  expect_true(origin_allowed(
    "HTTPS://MCP.Example.COM",
    list(host = "mcp.example.com"),
    local = FALSE
  ))
  expect_false(origin_allowed(
    "https://mcp.example.com:8443",
    list(host = "mcp.example.com"),
    local = FALSE
  ))

  handler <- new_handler(local = FALSE)
  response <- handler(serving_request(
    serving_rpc("ping"),
    headers = list(Origin = "https://mcp.example.com", Host = "mcp.example.com")
  ))
  expect_equal(response$status, 200L)
  expect_equal(
    response$headers[["Access-Control-Allow-Origin"]],
    "https://mcp.example.com"
  )
  expect_equal(
    response$headers[["Access-Control-Expose-Headers"]],
    "Mcp-Session-Id"
  )
  expect_equal(response$headers$Vary, "Origin")
})

test_that("behind a proxy, the own origin comes from forwarded headers", {
  expect_true(origin_allowed(
    "https://public.example.com",
    list(host = "10.0.0.5:3939", `x-forwarded-host` = "public.example.com"),
    local = FALSE
  ))
  expect_true(origin_allowed(
    "https://b.example.com",
    list(
      host = "internal",
      `x-forwarded-host` = "a.example.com, b.example.com"
    ),
    local = FALSE
  ))
  expect_true(origin_allowed(
    "https://connect.example.com",
    list(
      host = "127.0.0.1:12345",
      `rstudio-connect-app-base-url` = "https://connect.example.com/content/abc/"
    ),
    local = FALSE
  ))
  expect_false(origin_allowed(
    "https://elsewhere.example.com",
    list(
      host = "127.0.0.1:12345",
      `rstudio-connect-app-base-url` = "https://connect.example.com/content/abc/"
    ),
    local = FALSE
  ))
})

test_that("url_host() extracts the host and port of a URL", {
  expect_equal(
    url_host("https://connect.example.com/content/abc/"),
    "connect.example.com"
  )
  expect_equal(url_host("HTTP://Localhost:3939"), "localhost:3939")
  expect_null(url_host(NULL))
  expect_null(url_host(""))
})

test_that("loopback origins are allowed only for a local server", {
  loopback <- c(
    "http://localhost:5173",
    "http://localhost",
    "http://127.0.0.1:9999",
    "http://127.1.2.3:80",
    "http://[::1]:8080"
  )
  for (origin in loopback) {
    expect_true(
      origin_allowed(origin, list(host = "127.0.0.1:8080"), local = TRUE),
      info = origin
    )
    expect_false(
      origin_allowed(origin, list(host = "mcp.example.com"), local = FALSE),
      info = origin
    )
  }
})

test_that("lookalike hosts don't pass as loopback", {
  headers <- list(host = "127.0.0.1:8080")
  expect_false(origin_allowed(
    "http://localhost.evil.example",
    headers,
    local = TRUE
  ))
  expect_false(origin_allowed(
    "http://evil.example/localhost",
    headers,
    local = TRUE
  ))
  expect_false(origin_allowed(
    "http://notlocalhost:8080",
    headers,
    local = TRUE
  ))
  expect_false(origin_allowed("http://1127.0.0.1", headers, local = TRUE))
})

test_that("hostnames that merely start with 127. are not loopback", {
  expect_false(origin_allowed(
    "http://127.0.0.1.evil.example",
    list(host = "127.0.0.1:8080"),
    local = TRUE
  ))
  expect_false(origin_allowed(
    "http://127.evil.example:8080",
    list(host = "127.0.0.1:8080"),
    local = TRUE
  ))
})

test_that("a local server answers requests for IP addresses and allowed hosts", {
  handler <- new_handler()
  ping <- function(host, ...) {
    handler(serving_request(
      serving_rpc("ping"),
      headers = list(Host = host)
    ))$status
  }
  expect_equal(ping("192.168.1.20:8080"), 200L)
  expect_equal(ping("[fe80::1]:8080"), 200L)
  expect_equal(ping("1.2.3.4.nip.io:8080"), 403L)
  expect_equal(ping("mybox.local:8080"), 403L)

  allowing <- new_handler(allowed_hosts = "mybox.local")
  response <- allowing(serving_request(
    serving_rpc("ping"),
    headers = list(
      Host = "mybox.local:8080",
      Origin = "http://mybox.local:8080"
    )
  ))
  expect_equal(response$status, 200L)
})

test_that("a local server refuses DNS-rebinding requests", {
  # The attacker's name now resolves to 127.0.0.1, so the page is same-origin
  # with the server and the browser sends matching Origin and Host headers.
  expect_false(origin_allowed(
    "http://rebind.evil.example:8080",
    list(host = "rebind.evil.example:8080"),
    local = TRUE
  ))
})

test_that("the null origin is refused", {
  expect_false(origin_allowed(
    "null",
    list(host = "127.0.0.1:8080"),
    local = TRUE
  ))
  handler <- new_handler()
  response <- handler(serving_request(
    serving_rpc("ping"),
    headers = list(Origin = "null")
  ))
  expect_equal(response$status, 403L)
})

test_that("allowed_origins adds origins, and * allows any", {
  headers <- list(host = "mcp.example.com")
  expect_true(origin_allowed(
    "https://chat.example.com",
    headers,
    "https://chat.example.com",
    local = FALSE
  ))
  expect_true(origin_allowed(
    "https://b.example",
    headers,
    c("https://a.example", "https://b.example"),
    local = FALSE
  ))
  expect_false(origin_allowed(
    "https://chat.example.com.evil",
    headers,
    "https://chat.example.com",
    local = FALSE
  ))
  expect_true(origin_allowed(
    "https://anything.example",
    headers,
    "*",
    local = FALSE
  ))
  expect_true(origin_allowed("null", headers, "*", local = FALSE))

  handler <- new_handler(
    allowed_origins = "https://chat.example.com",
    local = FALSE
  )
  response <- handler(serving_request(
    serving_rpc("ping"),
    headers = list(
      Origin = "https://chat.example.com",
      Host = "mcp.example.com"
    )
  ))
  expect_equal(response$status, 200L)
  expect_equal(
    response$headers[["Access-Control-Allow-Origin"]],
    "https://chat.example.com"
  )
})

test_that("forbidden origins get 403 before anything else runs", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))
  sessions <- new_sessions()
  id <- open_session(server, sessions)
  evil <- list(Origin = "https://evil.example", Host = "127.0.0.1:8080")

  call <- handle_http_request(
    serving_request(
      serving_rpc("tools/call", list(name = "context")),
      headers = evil
    ),
    server,
    sessions
  )
  expect_equal(call$status, 403L)
  expect_null(call$headers[["Access-Control-Allow-Origin"]])
  body <- serving_body(call)
  expect_equal(body$error$code, -32600L)
  expect_equal(body$error$message, "Forbidden origin: https://evil.example")
  expect_equal(recorder$calls, 0L)

  preflight <- handle_http_request(
    serving_request(method = "OPTIONS", headers = evil),
    server,
    sessions
  )
  expect_equal(preflight$status, 403L)

  delete <- handle_http_request(
    serving_request(
      method = "DELETE",
      headers = c(evil, list(`Mcp-Session-Id` = id))
    ),
    server,
    sessions
  )
  expect_equal(delete$status, 403L)
  expect_equal(ls(sessions), id)
})

test_that("cors_headers() echoes the origin and exposes the session header", {
  expect_equal(
    cors_headers("https://chat.example.com"),
    list(
      `Access-Control-Allow-Origin` = "https://chat.example.com",
      `Access-Control-Expose-Headers` = "Mcp-Session-Id",
      Vary = "Origin"
    )
  )
})

# ---- Posit Connect users ----

test_that("connect_user() reads Posit Connect's credentials header", {
  withr::local_envvar(RSTUDIO_PRODUCT = "CONNECT")
  creds <- function(json) list(`rstudio-connect-credentials` = json)
  expect_equal(
    connect_user(creds('{"user":"ada","groups":["eng","ops"]}')),
    list(user = "ada", groups = c("eng", "ops"))
  )
  expect_equal(
    connect_user(creds('{"user":"ada","groups":["eng"]}'))$groups,
    "eng"
  )
  expect_equal(
    connect_user(creds('{"user":"ada","groups":[]}')),
    list(user = "ada", groups = NULL)
  )
  expect_equal(
    connect_user(creds('{"user":"ada"}')),
    list(user = "ada", groups = NULL)
  )
})

test_that("connect_user() ignores a missing, empty or malformed header", {
  nobody <- list(user = NULL, groups = NULL)
  expect_equal(connect_user(list()), nobody)
  expect_equal(connect_user(list(`rstudio-connect-credentials` = "")), nobody)
  expect_equal(
    connect_user(list(`rstudio-connect-credentials` = "{not json")),
    nobody
  )
  expect_equal(connect_user(list(`rstudio-connect-credentials` = "{}")), nobody)
})

test_that("the signed-in Connect user reaches tools through mcp_request()", {
  skip_if_not_installed("withr")
  withr::local_envvar(RSTUDIO_PRODUCT = "CONNECT")
  recorder <- serving_recorder()
  handler <- new_handler(serving_app(tools = list(recorder$tool)))
  handler(serving_request(
    serving_rpc("tools/call", list(name = "context")),
    headers = list(
      `RStudio-Connect-Credentials` = '{"user":"ada","groups":["eng","ops"]}',
      `X-Request-Id` = "req-42"
    )
  ))

  seen <- recorder$context
  expect_equal(seen$transport, "http")
  expect_equal(seen$user, "ada")
  expect_equal(seen$groups, c("eng", "ops"))
  expect_equal(seen$headers[["x-request-id"]], "req-42")
})

test_that("off Posit Connect, a client can't claim to be a Connect user", {
  skip_if_not_installed("withr")
  withr::local_envvar(
    RSTUDIO_PRODUCT = NA,
    CONNECT_SERVER = NA,
    R_CONFIG_ACTIVE = NA
  )
  recorder <- serving_recorder()
  handler <- new_handler(serving_app(tools = list(recorder$tool)))
  handler(serving_request(
    serving_rpc("tools/call", list(name = "context")),
    headers = list(
      `RStudio-Connect-Credentials` = '{"user":"admin","groups":["admins"]}'
    )
  ))
  expect_null(recorder$context$user)
  expect_null(recorder$context$groups)
})

test_that("a credentials header that isn't a JSON object doesn't break the request", {
  handler <- new_handler()
  response <- handler(serving_request(
    serving_rpc("ping"),
    headers = list(`RStudio-Connect-Credentials` = "5")
  ))
  expect_equal(response$status, 200L)
})

# ---- Helpers ----

test_that("request_headers() collects HTTP_* fields with lowercase dashed names", {
  req <- serving_request(
    headers = list(`Mcp-Session-Id` = "abc", `X-Forwarded-Host` = "a.example")
  )
  req$HTTP_NUMBER <- 5
  req$CONTENT_TYPE <- "application/json"
  headers <- request_headers(req)
  expect_equal(headers[["mcp-session-id"]], "abc")
  expect_equal(headers[["x-forwarded-host"]], "a.example")
  expect_null(headers[["number"]])
  expect_null(headers[["content-type"]])

  expect_equal(
    request_headers(list(
      REQUEST_METHOD = "POST",
      HTTP_HOST = c("a", "b"),
      HTTP_MCP_METHOD = "ping"
    )),
    list(host = "a", `mcp-method` = "ping")
  )
})

test_that("http_json() writes a JSON response without the status attribute", {
  response <- http_json(
    404L,
    jsonrpc_error(1, -32601L, "Nope", status = 404L),
    list(Vary = "Origin")
  )
  expect_equal(response$status, 404L)
  expect_equal(
    response$headers,
    list(Vary = "Origin", `Content-Type` = "application/json")
  )
  expect_equal(
    response$body,
    '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Nope"}}'
  )
})

# ---- serve(type = "http") and serve_http() ----

test_that("serve(type = 'http') passes the listening options on", {
  captured <- NULL
  local_mocked_bindings(serve_http = function(server, ...) {
    captured <<- c(list(server = server), list(...))
    invisible(NULL)
  })
  serve(
    serving_app(),
    type = "http",
    port = 9123,
    host = "0.0.0.0",
    path = "/rpc",
    allowed_origins = "https://chat.example.com"
  )
  expect_s3_class(captured$server, "McpServer")
  expect_equal(captured$host, "0.0.0.0")
  expect_equal(captured$port, 9123)
  expect_equal(captured$path, "/rpc")
  expect_equal(captured$allowed_origins, "https://chat.example.com")
})

test_that("serve_http() runs httpuv with a handler for the endpoint", {
  skip_if_not_installed("httpuv")
  captured <- NULL
  local_mocked_bindings(
    runServer = function(host, port, app, ...) {
      captured <<- list(host = host, port = port, app = app)
      invisible(NULL)
    },
    .package = "httpuv"
  )
  expect_message(
    serve_http(
      McpServer$new(serving_app()),
      host = "127.0.0.1",
      port = 8123,
      path = "/rpc"
    ),
    "http://127.0.0.1:8123/rpc",
    fixed = TRUE,
    class = "shinymcp_message"
  )
  expect_equal(captured$host, "127.0.0.1")
  expect_equal(captured$port, 8123)

  ok <- captured$app$call(serving_request(serving_rpc("ping"), path = "/rpc"))
  expect_equal(ok$status, 200L)
  expect_equal(serving_body(ok)$result, setNames(list(), character()))

  missing <- captured$app$call(serving_request(method = "GET", path = "/"))
  expect_equal(missing$status, 404L)
  expect_equal(missing$headers[["Content-Type"]], "text/plain")
  expect_equal(missing$body, "Not found. The MCP endpoint is /rpc.")
})

test_that("serve_http() turns handler errors into a 500 JSON-RPC error", {
  skip_if_not_installed("httpuv")
  captured <- NULL
  local_mocked_bindings(
    runServer = function(host, port, app, ...) captured <<- app,
    .package = "httpuv"
  )
  suppressMessages(serve_http(McpServer$new(serving_app())))
  req <- serving_request(path = "/mcp")
  req[["rook.input"]] <- list(read = function(...) stop("disk on fire"))

  expect_message(response <- captured$call(req), "disk on fire")
  expect_equal(response$status, 500L)
  body <- serving_body(response)
  expect_null(body$id)
  expect_equal(body$error$code, -32603L)
  expect_equal(body$error$message, "disk on fire")
})

test_that("serve_http() treats only loopback hosts as local", {
  skip_if_not_installed("httpuv")
  captured <- list()
  local_mocked_bindings(
    runServer = function(host, port, app, ...) captured[[host]] <<- app,
    .package = "httpuv"
  )
  server <- McpServer$new(serving_app())
  suppressMessages({
    serve_http(server, host = "127.0.0.1")
    serve_http(server, host = "0.0.0.0")
  })
  expect_message(
    serve_http(server, host = "::1", port = 8080),
    "http://[::1]:8080/mcp",
    fixed = TRUE
  )

  # A page from a local dev server calls the MCP server. A loopback server
  # accepts it; a server on all interfaces, reached by its LAN address,
  # doesn't treat localhost origins as its own.
  from_dev_server <- function(app, host) {
    app$call(serving_request(
      serving_rpc("ping"),
      headers = list(Origin = "http://localhost:5173", Host = host)
    ))$status
  }
  expect_equal(from_dev_server(captured[["127.0.0.1"]], "127.0.0.1:8080"), 200L)
  expect_equal(from_dev_server(captured[["::1"]], "[::1]:8080"), 200L)
  expect_equal(
    from_dev_server(captured[["0.0.0.0"]], "192.168.1.20:8080"),
    403L
  )
  # A loopback server refuses requests for other host names (DNS rebinding).
  expect_equal(
    from_dev_server(captured[["127.0.0.1"]], "rebind.evil.example:8080"),
    403L
  )
})

# ---- A real round trip ----

test_that("the handler answers real HTTP requests through httpuv", {
  skip_if_not_installed("httpuv")
  handler <- new_handler()
  live <- serving_start(function(req) {
    handler(req) %||%
      list(
        status = 404L,
        headers = list(`Content-Type` = "text/plain"),
        body = "Not found"
      )
  })
  on.exit(live$stop(), add = TRUE)
  origin <- sprintf("http://127.0.0.1:%d", live$port)
  json <- list(`Content-Type` = "application/json", Origin = origin)

  init <- serving_http(
    live$port,
    "POST",
    "/mcp",
    serving_initialize(ui = FALSE),
    json
  )
  expect_equal(init$status, 200L)
  expect_match(init$headers[["content-type"]], "application/json", fixed = TRUE)
  expect_equal(init$headers[["access-control-allow-origin"]], origin)
  id <- init$headers[["mcp-session-id"]]
  expect_match(id, "^mcp-")
  expect_equal(
    jsonlite::fromJSON(init$body)$result$protocolVersion,
    "2025-06-18"
  )

  session <- c(json, list(`Mcp-Session-Id` = id))
  listed <- serving_http(
    live$port,
    "POST",
    "/mcp",
    serving_rpc("tools/list", id = 2),
    session
  )
  tools <- jsonlite::fromJSON(listed$body, simplifyVector = FALSE)$result$tools
  expect_equal(
    vapply(tools, function(t) t$name, character(1)),
    c("echo", "boom")
  )

  call <- serving_http(
    live$port,
    "POST",
    "/mcp",
    serving_rpc(
      "tools/call",
      list(name = "echo", arguments = list(x = "over the wire")),
      id = 3
    ),
    session
  )
  expect_equal(call$status, 200L)
  expect_equal(
    jsonlite::fromJSON(call$body)$result$structuredContent$out,
    "over the wire"
  )

  note <- serving_http(
    live$port,
    "POST",
    "/mcp",
    serving_rpc("notifications/initialized", id = NULL),
    session
  )
  expect_equal(note$status, 202L)

  expect_equal(
    serving_http(live$port, "DELETE", "/mcp", headers = session)$status,
    200L
  )
  expect_equal(
    serving_http(
      live$port,
      "POST",
      "/mcp",
      serving_rpc("ping"),
      session
    )$status,
    404L
  )
  expect_equal(serving_http(live$port, "GET", "/mcp")$status, 405L)
  expect_equal(serving_http(live$port, "GET", "/elsewhere")$status, 404L)
  expect_equal(
    serving_http(
      live$port,
      "POST",
      "/mcp",
      serving_rpc("ping"),
      list(Origin = "https://evil.example")
    )$status,
    403L
  )
})
