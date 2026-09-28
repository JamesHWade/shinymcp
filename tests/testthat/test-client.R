# A client for remote MCP servers (R/client.R)

client_server <- function() {
  McpServer$new(serving_app(name = "fx"))
}

request_bodies <- function(requests) {
  lapply(requests, function(r) {
    if (is.null(r$body)) NULL else jsonlite::parse_json(rawToChar(r$body))
  })
}

# ---- Construction ----

test_that("mcp_client() checks its arguments and names the server by URL", {
  client <- mcp_client("https://connect.example.com/content/abc/mcp/")
  expect_s3_class(client, "McpClient")
  expect_equal(client$name, "connect.example.com/content/abc/mcp")
  expect_equal(client$timeout, 60)
  expect_null(client$protocol_version())

  expect_equal(
    mcp_client("http://127.0.0.1:8080/mcp?x=1", name = "local")$name,
    "local"
  )
  expect_error(mcp_client("ftp://x/mcp"), class = "shinymcp_error_validation")
  expect_error(mcp_client("/mcp"), class = "shinymcp_error_validation")
  expect_error(
    mcp_client("https://x/mcp", headers = 1),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_client("https://x/mcp", timeout = 0),
    class = "shinymcp_error_validation"
  )
})

test_that("the client prints its server", {
  fx <- serving_client(client_server())
  expect_output(print(fx$client), "<McpClient> 127.0.0.1/mcp")
  fx$client$tools()
  expect_output(print(fx$client), "Protocol 2026-07-28")
})

# ---- The stateless protocol ----

test_that("a stateless server is discovered and each request carries its metadata", {
  fx <- serving_client(client_server(), name = "fx")
  client <- fx$client

  tools <- client$tools()
  expect_equal(client$protocol_version(), "2026-07-28")
  expect_equal(client$server_info()$name, "shinymcp-fx")
  expect_equal(
    vapply(tools, `[[`, "", "name"),
    c("echo", "boom", "refresh")
  )
  # _meta survives: the tool declares its page and who may call it.
  expect_equal(tools[[1]][["_meta"]]$ui$resourceUri, "ui://fx")
  expect_equal(unlist(tools[[3]][["_meta"]]$ui$visibility), "app")

  result <- client$call_tool("echo", list(x = "hi"))
  expect_equal(result$structuredContent, list(out = "hi"))
  expect_equal(result$resultType, "complete")

  requests <- fx$requests()
  bodies <- request_bodies(requests)
  expect_equal(
    vapply(bodies, `[[`, "", "method"),
    c("server/discover", "tools/list", "tools/call")
  )
  call <- bodies[[3]]
  meta <- call$params[["_meta"]]
  expect_equal(meta[["io.modelcontextprotocol/protocolVersion"]], "2026-07-28")
  expect_equal(meta[["io.modelcontextprotocol/clientInfo"]]$name, "shinymcp")
  expect_equal(
    unlist(
      meta[["io.modelcontextprotocol/clientCapabilities"]]$extensions[[
        "io.modelcontextprotocol/ui"
      ]]$mimeTypes
    ),
    "text/html;profile=mcp-app"
  )
  headers <- requests[[3]]$headers
  expect_equal(headers$`MCP-Protocol-Version`, "2026-07-28")
  expect_equal(headers$`Mcp-Method`, "tools/call")
  expect_equal(headers$`Mcp-Name`, "echo")
  expect_equal(headers$Accept, "application/json, text/event-stream")
})

test_that("resources are read with their metadata", {
  app <- serving_app(
    name = "fx",
    csp = list(connect_domains = "https://api.example.com")
  )
  fx <- serving_client(McpServer$new(app))

  result <- fx$client$read_resource("ui://fx")
  contents <- result$contents[[1]]
  expect_equal(contents$uri, "ui://fx")
  expect_equal(contents$mimeType, "text/html;profile=mcp-app")
  expect_equal(contents$text, app$html_resource())
  expect_equal(
    unlist(contents[["_meta"]]$ui$csp$connectDomains),
    "https://api.example.com"
  )
  headers <- fx$requests()[[2]]$headers
  expect_equal(headers$`Mcp-Name`, "ui://fx")
})

test_that("names that aren't ASCII travel base64-encoded in headers", {
  expect_equal(encode_header_value("echo"), "echo")
  encoded <- encode_header_value("écho")
  expect_match(encoded, "^=\\?base64\\?.*\\?=$")
  decoded <- rawToChar(jsonlite::base64_dec(sub(
    "^=\\?base64\\?(.*)\\?=$",
    "\\1",
    encoded
  )))
  Encoding(decoded) <- "UTF-8"
  expect_equal(decoded, "écho")
})

# ---- The handshake ----

test_that("a server without discovery gets the handshake, and its session is kept", {
  fx <- serving_client(client_server(), legacy = TRUE)
  client <- fx$client

  result <- client$call_tool("echo", list(x = "old"))
  expect_equal(result$structuredContent, list(out = "old"))
  expect_equal(client$protocol_version(), "2025-11-25")
  expect_equal(client$server_info()$name, "shinymcp-fx")

  requests <- fx$requests()
  bodies <- request_bodies(requests)
  expect_equal(
    vapply(bodies, `[[`, "", "method"),
    c(
      "server/discover",
      "initialize",
      "notifications/initialized",
      "tools/call"
    )
  )
  init <- bodies[[2]]
  expect_equal(init$params$protocolVersion, "2025-11-25")
  expect_equal(init$params$clientInfo$name, "shinymcp")
  expect_false(is.null(
    init$params$capabilities$extensions[["io.modelcontextprotocol/ui"]]
  ))
  # Requests after the handshake name the session and version, not _meta.
  headers <- requests[[4]]$headers
  expect_match(headers$`Mcp-Session-Id`, ".+")
  expect_equal(headers$`MCP-Protocol-Version`, "2025-11-25")
  expect_null(bodies[[4]]$params[["_meta"]])
  expect_null(bodies[[3]]$id)
})

test_that("a session the server forgot is started again, once", {
  fx <- serving_client(client_server(), legacy = TRUE)
  client <- fx$client
  client$call_tool("echo", list(x = "a"))
  first <- fx$requests()[[4]]$headers$`Mcp-Session-Id`

  fx$expire()
  result <- client$call_tool("echo", list(x = "b"))
  expect_equal(result$structuredContent, list(out = "b"))

  methods <- vapply(request_bodies(fx$requests()), `[[`, "", "method")
  expect_equal(
    methods[5:9],
    c(
      "tools/call",
      "server/discover",
      "initialize",
      "notifications/initialized",
      "tools/call"
    )
  )
  second <- fx$requests()[[9]]$headers$`Mcp-Session-Id`
  expect_false(identical(first, second))
})

test_that("close() ends the session", {
  fx <- serving_client(client_server(), legacy = TRUE)
  fx$client$call_tool("echo", list(x = "a"))
  session <- fx$requests()[[4]]$headers$`Mcp-Session-Id`

  fx$client$close()
  last <- fx$requests()[[length(fx$requests())]]
  expect_equal(last$method, "DELETE")
  expect_equal(last$headers$`Mcp-Session-Id`, session)
  expect_null(fx$client$protocol_version())
})

# ---- Responses ----

test_that("answers in server-sent events are read, past notifications", {
  for (legacy in c(FALSE, TRUE)) {
    fx <- serving_client(client_server(), legacy = legacy, sse = TRUE)
    result <- fx$client$call_tool("echo", list(x = "streamed"))
    expect_equal(result$structuredContent, list(out = "streamed"))
  }
})

test_that("errors are raised with the server's message; send() returns them", {
  fx <- serving_client(client_server())
  client <- fx$client

  err <- expect_error(client$call_tool("nope"), class = "shinymcp_error_client")
  expect_match(conditionMessage(err), "tools/call.+failed")
  expect_match(conditionMessage(err), "Unknown tool: nope")
  expect_equal(err$rpc_error$code, RPC_INVALID_PARAMS)

  # A tool that fails is a result, not an error.
  expect_true(client$call_tool("boom")$isError)

  response <- client$send(list(
    jsonrpc = "2.0",
    id = "page-7",
    method = "tools/call",
    params = list(name = "nope")
  ))
  expect_equal(response$id, "page-7")
  expect_equal(response$error$code, RPC_INVALID_PARAMS)
})

test_that("HTTP errors without a JSON-RPC body are errors", {
  response <- read_client_response(
    list(
      status = 502L,
      headers = list(`content-type` = "text/html"),
      body = "<h1>Bad gateway</h1>"
    ),
    "c-1"
  )
  expect_equal(response$id, "c-1")
  expect_equal(response$error$code, RPC_INTERNAL_ERROR)
  expect_equal(
    response$error$message,
    "The server answered with HTTP status 502."
  )

  # An error the server couldn't tie to the request still reaches it.
  response <- read_client_response(
    list(
      status = 400L,
      headers = list(`content-type` = "application/json"),
      body = '{"jsonrpc":"2.0","id":null,"error":{"code":-32020,"message":"Header mismatch"}}'
    ),
    "c-2"
  )
  expect_equal(response$id, "c-2")
  expect_equal(response$error$code, -32020L)
})

test_that("a server that can't be reached is an error that names it", {
  client <- McpClient$new(
    "http://127.0.0.1:1/mcp",
    transport = function(request, async = FALSE, timeout = 60) {
      stop("Connection refused")
    }
  )
  expect_error(
    client$tools(),
    "Couldn't reach the MCP server",
    class = "shinymcp_error_client"
  )
})

# ---- Headers and caching ----

test_that("headers are sent with every request, and may be a function", {
  n <- 0
  fx <- serving_client(
    client_server(),
    headers = function() {
      n <<- n + 1
      list(Authorization = paste("Key", n), `X-Trace` = c("a", "b"))
    }
  )
  fx$client$tools()

  headers <- lapply(fx$requests(), `[[`, "headers")
  expect_equal(headers[[1]]$Authorization, "Key 1")
  expect_equal(headers[[2]]$Authorization, "Key 2")
  expect_equal(headers[[2]]$`X-Trace`, "a, b")

  bad <- serving_client(client_server(), headers = list("no name"))
  expect_error(bad$client$tools(), "must be named")
})

test_that("the tool list is kept for as long as the server allows", {
  fx <- serving_client(client_server())
  fx$client$tools()
  fx$client$tools()
  methods <- vapply(request_bodies(fx$requests()), `[[`, "", "method")
  expect_equal(sum(methods == "tools/list"), 1)

  fx$client$tools(refresh = TRUE)
  methods <- vapply(request_bodies(fx$requests()), `[[`, "", "method")
  expect_equal(sum(methods == "tools/list"), 2)
})

# ---- Asynchronous requests ----

test_that("async requests resolve, connecting once", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  fx <- serving_client(client_server(), legacy = TRUE)
  client <- fx$client
  results <- list()
  promises::then(client$call_tool_async("echo", list(x = "a")), function(r) {
    results$a <<- r$structuredContent$out
  })
  promises::then(client$call_tool_async("echo", list(x = "b")), function(r) {
    results$b <<- r$structuredContent$out
  })
  promises::then(client$tools_async(), function(tools) {
    results$tools <<- length(tools)
  })
  failed <- NULL
  promises::catch(client$call_tool_async("nope"), function(e) failed <<- e)
  helper_drain()

  expect_equal(results, list(a = "a", b = "b", tools = 3L))
  expect_s3_class(failed, "shinymcp_error_client")
  methods <- vapply(request_bodies(fx$requests()), `[[`, "", "method")
  expect_equal(sum(methods == "initialize"), 1)
})

test_that("async requests to a server that can't be reached reject", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  client <- McpClient$new(
    "http://127.0.0.1:1/mcp",
    transport = function(request, async = FALSE, timeout = 60) {
      promises::promise_reject(simpleError("Connection refused"))
    }
  )
  failed <- NULL
  promises::catch(client$tools_async(), function(e) failed <<- e)
  helper_drain()
  expect_s3_class(failed, "shinymcp_error_client")
  expect_match(conditionMessage(failed), "Couldn't reach")
})

test_that("every async method checks for promises before using it", {
  skip_if_not_installed("promises")
  client <- serving_client(client_server())$client
  # A kept tool list, so tools_async() could answer without a request.
  client$tools()
  # Where promises isn't installed, any use of it fails before the check.
  local_mocked_bindings(
    then = function(...) stop("promises was used before the check"),
    promise_resolve = function(...) stop("promises was used before the check"),
    .package = "promises"
  )
  checked <- character()
  local_mocked_bindings(
    check_installed = function(pkg, ...) {
      checked <<- c(checked, pkg)
      rlang::abort("promises is missing", class = "test_missing")
    },
    .package = "rlang"
  )
  expect_error(client$tools_async(), class = "test_missing")
  expect_error(client$tools_async(refresh = TRUE), class = "test_missing")
  expect_error(client$call_tool_async("echo"), class = "test_missing")
  expect_error(client$read_resource_async("ui://fx"), class = "test_missing")
  expect_error(client$request_async("ping"), class = "test_missing")
  expect_error(
    client$send_async(client_message("ping")),
    class = "test_missing"
  )
  expect_equal(checked, rep("promises", 6))
})

test_that("the client works over real HTTP", {
  skip_on_cran()
  skip_if_not_installed("httpuv")
  skip_if_not_installed("httr2")
  skip_if_not_installed("later")
  handler <- mcp_http_handler(client_server(), local = TRUE)
  started <- start_local_server(
    "127.0.0.1",
    NULL,
    list(call = function(req) handler(req))
  )
  on.exit(httpuv::stopServer(started$server), add = TRUE)
  client <- mcp_client(sprintf("http://127.0.0.1:%d/mcp", started$port))

  result <- NULL
  promises::then(
    client$call_tool_async("echo", list(x = "over http")),
    function(r) {
      result <<- r
    }
  )
  end <- Sys.time() + 10
  while (is.null(result) && Sys.time() < end) {
    later::run_now(0.05)
  }
  expect_equal(result$structuredContent, list(out = "over http"))
  expect_equal(client$protocol_version(), "2026-07-28")
})

test_that("async requests to a server that never answers time out", {
  skip_on_cran()
  skip_if_not_installed("httpuv")
  skip_if_not_installed("httr2")
  skip_if_not_installed("later")
  # A socket that takes connections and never answers them.
  port <- httpuv::randomPort()
  silent <- serverSocket(port)
  on.exit(close(silent), add = TRUE)
  client <- mcp_client(sprintf("http://127.0.0.1:%d/mcp", port), timeout = 1)

  failed <- NULL
  promises::catch(client$tools_async(), function(e) failed <<- e)
  start <- Sys.time()
  while (is.null(failed) && Sys.time() < start + 30) {
    later::run_now(0.1)
  }
  expect_s3_class(failed, "shinymcp_error_client")
  expect_match(conditionMessage(failed), "Timeout was reached")
  # Discovery, then the handshake: two timeouts, and the pool's check.
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 10)
})
