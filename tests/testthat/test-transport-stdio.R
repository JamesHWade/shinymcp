# The stdio transport (R/transport-stdio.R) and serve() (R/serve.R).
# serve_stdio() takes its input and output connections as arguments, so the
# tests drive it with text connections instead of a real stdin.

line_of <- function(message) {
  serving_json_text(message)
}

# A tool that prints to stdout while it runs.
chatty_tool <- function() {
  list(
    name = "chatty",
    description = "Print while working.",
    fun = function() {
      print("progress from print()")
      cat("progress from cat()\n")
      list(out = "done")
    }
  )
}

# Run serve_stdio() over the given input lines; return the lines it wrote.
run_stdio <- function(server, lines) {
  input <- textConnection(lines)
  output <- textConnection(NULL, "w")
  on.exit(close(output), add = TRUE)
  suppressMessages(serve_stdio(server, input = input, output = output))
  textConnectionValue(output)
}

# ---- stdio_handle_line() ----

test_that("a request line gets one line of JSON back", {
  server <- McpServer$new(serving_app())
  context <- list(transport = "stdio", session = server$new_session())
  expect_equal(
    stdio_handle_line(server, line_of(serving_rpc("ping", id = 1)), context),
    '{"jsonrpc":"2.0","id":1,"result":{}}'
  )
  reply <- stdio_handle_line(
    server,
    line_of(serving_rpc(
      "tools/call",
      list(name = "echo", arguments = list(x = "hi")),
      id = 2
    )),
    context
  )
  expect_false(grepl("\n", reply, fixed = TRUE))
  expect_equal(from_json(reply)$result$structuredContent$out, "hi")
})

test_that("notifications and client responses get no reply", {
  server <- McpServer$new(serving_app())
  context <- list(transport = "stdio", session = server$new_session())
  expect_null(stdio_handle_line(
    server,
    line_of(serving_rpc("notifications/initialized", id = NULL)),
    context
  ))
  expect_null(stdio_handle_line(
    server,
    '{"jsonrpc":"2.0","id":4,"result":{}}',
    context
  ))
})

test_that("a line that isn't JSON gets a parse error", {
  server <- McpServer$new(serving_app())
  for (line in c("{not json", "Content-Length: 42", "nul")) {
    expect_equal(
      stdio_handle_line(server, line, list(transport = "stdio")),
      '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}'
    )
  }
})

test_that("a line holding a JSON scalar or null gets an invalid request error", {
  server <- McpServer$new(serving_app())
  for (line in c("42", '"ping"', "true", "null", " null ")) {
    reply <- from_json(stdio_handle_line(
      server,
      line,
      list(transport = "stdio")
    ))
    expect_equal(reply$error$code, -32600L, label = line)
    expect_true("id" %in% names(reply))
    expect_null(reply$id)
  }
})

test_that("a line is parsed as JSON text, never read as a file path", {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeLines('{"jsonrpc":"2.0","id":"read-from-disk","method":"ping"}', path)
  server <- McpServer$new(serving_app())
  reply <- from_json(stdio_handle_line(server, path, list(transport = "stdio")))
  expect_equal(reply$error$code, -32700L)
})

test_that("a batch line gets an array of replies", {
  server <- McpServer$new(serving_app())
  context <- list(transport = "stdio", session = server$new_session())
  batch <- line_of(list(
    serving_rpc("ping", id = 1),
    serving_rpc("notifications/initialized", id = NULL),
    serving_rpc("no/such/method", id = 2)
  ))
  reply <- from_json(stdio_handle_line(server, batch, context))
  expect_length(reply, 2)
  expect_equal(reply[[1]]$id, 1)
  expect_equal(reply[[2]]$error$code, -32601L)

  notifications <- line_of(list(
    serving_rpc("notifications/initialized", id = NULL),
    serving_rpc("notifications/cancelled", list(requestId = 1), id = NULL)
  ))
  expect_null(stdio_handle_line(server, notifications, context))
})

test_that("initialize in a batch is refused, and as a notification not answered", {
  server <- McpServer$new(serving_app())
  context <- list(transport = "stdio", session = server$new_session())
  batch <- line_of(list(
    serving_initialize(id = 1),
    serving_initialize(id = NULL),
    serving_rpc("ping", id = 2)
  ))
  reply <- from_json(stdio_handle_line(server, batch, context))
  expect_length(reply, 2)
  expect_equal(reply[[1]]$id, 1)
  expect_equal(reply[[1]]$error$code, -32600L)
  expect_equal(reply[[2]]$id, 2)

  alone <- line_of(list(serving_initialize(id = NULL)))
  expect_null(stdio_handle_line(server, alone, context))
})

test_that("each entry of a batch that isn't a message gets its own error", {
  server <- McpServer$new(serving_app())
  context <- list(transport = "stdio", session = server$new_session())
  reply <- from_json(stdio_handle_line(
    server,
    '[5, {"jsonrpc":"2.0","id":1,"method":"ping"}]',
    context
  ))
  expect_length(reply, 2)
  expect_null(reply[[1]]$id)
  expect_equal(reply[[1]]$error$code, -32600L)
  expect_equal(reply[[2]]$id, 1L)
  expect_equal(reply[[2]]$result, setNames(list(), character()))

  reply <- from_json(stdio_handle_line(server, "[1, 2]", context))
  expect_equal(
    vapply(reply, function(r) r$error$code, integer(1)),
    c(-32600L, -32600L)
  )
  # An empty array isn't a batch: one error.
  expect_equal(
    from_json(stdio_handle_line(server, "[]", context))$error$code,
    -32600L
  )
})

test_that("the HTTP status attribute never reaches the JSON", {
  server <- McpServer$new(serving_app())
  context <- list(transport = "stdio")
  # A 400 in the modern era, inside and outside a batch.
  unsupported <- serving_modern("tools/list", version = "2027-01-01")
  single <- stdio_handle_line(server, line_of(unsupported), context)
  batch <- stdio_handle_line(
    server,
    line_of(list(unsupported, serving_rpc("ping", id = 2))),
    context
  )
  for (reply in c(single, batch)) {
    expect_false(grepl("http_status", reply, fixed = TRUE))
    expect_match(reply, '"code":-32022', fixed = TRUE)
  }
})

test_that("output printed by tools goes to stderr, not stdout", {
  server <- McpServer$new(serving_app(tools = list(chatty_tool())))
  line <- line_of(serving_rpc("tools/call", list(name = "chatty"), id = 3))

  stdout <- capture.output(
    stderr <- capture.output(
      reply <- stdio_handle_line(server, line, list(transport = "stdio")),
      type = "message"
    )
  )
  expect_equal(stdout, character())
  expect_equal(stderr, c('[1] "progress from print()"', "progress from cat()"))
  expect_equal(from_json(reply)$result$structuredContent$out, "done")
})

test_that("errors thrown by the server become internal errors", {
  failing <- list(handle = function(message, context) stop("database offline"))
  expect_message(
    reply <- stdio_handle_line(
      failing,
      line_of(serving_rpc("tools/list", id = 9)),
      list()
    ),
    "database offline"
  )
  expect_equal(
    reply,
    '{"jsonrpc":"2.0","id":9,"error":{"code":-32603,"message":"Internal error: database offline"}}'
  )
})

test_that("with_stdout_diverted() restores stdout, even after an error", {
  sinks <- sink.number()
  expect_error(with_stdout_diverted(stop("inside")), "inside")
  expect_equal(sink.number(), sinks)

  stderr <- capture.output(
    value <- with_stdout_diverted({
      cat("to stderr\n")
      "value"
    }),
    type = "message"
  )
  expect_equal(value, "value")
  expect_equal(stderr, "to stderr")
  expect_equal(sink.number(), sinks)
})

test_that("strip_http_status() drops only the status attribute", {
  x <- structure(list(a = 1), http_status = 404L, other = "kept")
  stripped <- strip_http_status(x)
  expect_null(attr(stripped, "http_status"))
  expect_equal(attr(stripped, "other"), "kept")
  expect_equal(stripped$a, 1)
})

# ---- serve_stdio() ----

test_that("serve_stdio() answers each line in order until the input ends", {
  server <- McpServer$new(serving_app())
  lines <- c(
    line_of(serving_rpc("ping", id = 1)),
    "",
    "   ",
    "{bad json",
    line_of(serving_rpc(
      "tools/call",
      list(name = "echo", arguments = list(x = "second")),
      id = 2
    )),
    line_of(serving_rpc("notifications/initialized", id = NULL)),
    line_of(serving_rpc("tools/list", id = 3))
  )
  written <- run_stdio(server, lines)

  expect_length(written, 4)
  replies <- lapply(written, from_json)
  expect_equal(replies[[1]]$id, 1)
  expect_null(replies[[2]]$id)
  expect_equal(replies[[2]]$error$code, -32700L)
  expect_equal(replies[[3]]$id, 2)
  expect_equal(replies[[3]]$result$structuredContent$out, "second")
  expect_equal(replies[[4]]$id, 3)
})

test_that("serve_stdio() returns quietly on empty input and closes it", {
  server <- McpServer$new(serving_app())
  input <- textConnection(character())
  output <- textConnection(NULL, "w")
  on.exit(close(output), add = TRUE)
  expect_message(
    result <- serve_stdio(server, input = input, output = output),
    "fx",
    class = "shinymcp_message"
  )
  expect_null(result)
  expect_equal(textConnectionValue(output), character())
  expect_error(isOpen(input))
})

test_that("serve_stdio() opens an input connection that isn't open yet", {
  path <- tempfile()
  on.exit(unlink(path), add = TRUE)
  writeLines(line_of(serving_rpc("ping", id = 1)), path)
  output <- textConnection(NULL, "w")
  on.exit(close(output), add = TRUE)

  suppressMessages(serve_stdio(
    McpServer$new(serving_app()),
    input = file(path),
    output = output
  ))
  expect_equal(
    textConnectionValue(output),
    '{"jsonrpc":"2.0","id":1,"result":{}}'
  )
})

test_that("serve_stdio() keeps one session for the whole connection", {
  server <- McpServer$new(serving_app())
  lines <- c(
    line_of(serving_initialize(ui = FALSE, version = "2025-03-26")),
    line_of(serving_rpc("notifications/initialized", id = NULL)),
    line_of(serving_rpc("tools/list", id = 2))
  )
  replies <- lapply(run_stdio(server, lines), from_json)
  expect_equal(replies[[1]]$result$protocolVersion, "2025-03-26")
  tools <- replies[[2]]$result$tools
  expect_equal(
    vapply(tools, function(t) t$name, character(1)),
    c("echo", "boom")
  )
  expect_null(tools[[1]][["_meta"]][["ui"]])
})

test_that("serve_stdio() serves modern requests without a handshake", {
  server <- McpServer$new(serving_app())
  replies <- lapply(
    run_stdio(server, line_of(serving_modern("server/discover"))),
    from_json
  )
  expect_equal(replies[[1]]$result$resultType, "complete")
  expect_equal(replies[[1]]$result$supportedVersions[[1]], "2026-07-28")
})

test_that("tools served over stdio see the stdio transport", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))
  run_stdio(server, line_of(serving_rpc("tools/call", list(name = "context"))))
  expect_equal(recorder$context$transport, "stdio")
  expect_null(recorder$context$user)
})

test_that("serve_stdio() keeps stdout clean while tools print", {
  server <- McpServer$new(serving_app(tools = list(chatty_tool())))
  lines <- c(
    line_of(serving_rpc("tools/call", list(name = "chatty"), id = 1)),
    line_of(serving_rpc("ping", id = 2))
  )
  stdout <- capture.output(
    stderr <- capture.output(
      written <- run_stdio(server, lines),
      type = "message"
    )
  )
  expect_equal(stdout, character())
  expect_true(all(
    c('[1] "progress from print()"', "progress from cat()") %in% stderr
  ))
  expect_length(written, 2)
  expect_equal(from_json(written[[1]])$result$structuredContent$out, "done")
  expect_equal(from_json(written[[2]])$id, 2)
})

# ---- serve() ----

test_that("serve() serves stdio by default", {
  served <- NULL
  local_mocked_bindings(
    serve_stdio = function(server, ...) served <<- server,
    serve_http = function(...) stop("serve_http() should not run")
  )
  app <- serving_app()
  serve(app)
  expect_s3_class(served, "McpServer")
  expect_identical(served$apps[[1]], app)
})

test_that("serve() serves a list of apps from one server", {
  served <- NULL
  local_mocked_bindings(serve_stdio = function(server, ...) served <<- server)
  serve(list(
    serving_app("alpha", tools = list(serving_echo_tool("alpha_echo"))),
    serving_app("beta", tools = list(serving_echo_tool("beta_echo")))
  ))
  expect_equal(
    vapply(served$apps, function(a) a$name, character(1)),
    c("alpha", "beta")
  )
})

test_that("serve() serves an app defined in an app.R", {
  dir <- file.path(tempfile(), "from-file")
  dir.create(dir, recursive = TRUE)
  on.exit(unlink(dirname(dir), recursive = TRUE), add = TRUE)
  writeLines(
    c(
      "app <- mcp_app(",
      "  ui = htmltools::tags$div(mcp_text('out')),",
      "  tools = list(list(name = 'hello', description = 'Say hello.', fun = function() list(out = 'hi'))),",
      "  name = 'from-file'",
      ")",
      "serve(app)"
    ),
    file.path(dir, "app.R")
  )
  served <- NULL
  local_mocked_bindings(serve_stdio = function(server, ...) served <<- server)
  serve(dir)
  expect_equal(served$apps[[1]]$name, "from-file")
  expect_true(served$apps[[1]]$has_tool("hello"))
})

test_that("serve() checks its arguments before serving", {
  local_mocked_bindings(
    serve_stdio = function(...) stop("should not be reached"),
    serve_http = function(...) stop("should not be reached")
  )
  expect_error(serve(serving_app(), type = "sse"), "should be one of")
  expect_error(serve(42), class = "shinymcp_error_validation")
  expect_error(serve(list()), class = "shinymcp_error_validation")
  expect_error(
    serve(list(serving_app(), serving_app(tools = list()))),
    class = "shinymcp_error_validation"
  )
})

test_that("serve() serves a Shiny app object", {
  skip_if_not_installed("shiny")
  served <- NULL
  local_mocked_bindings(serve_stdio = function(server, ...) served <<- server)
  serve(shiny::shinyApp(
    shiny::fluidPage(
      shiny::textInput("who", "Who"),
      shiny::textOutput("hello")
    ),
    function(input, output, session) {
      output$hello <- shiny::renderText(input$who)
    }
  ))
  expect_equal(served$apps[[1]]$name, "shiny-app")
})

test_that("serve() warns when an app needs a host that runs its tools", {
  local_mocked_bindings(serve_stdio = function(...) NULL)
  expect_warning(serve(serving_app(trigger = "manual")), "manual")
  expect_no_warning(serve(serving_app(trigger = "submit")))
  expect_no_warning(serve(serving_app(trigger = "change")))
  expect_no_warning(serve(serving_app()))
})

test_that("warn_host_only_trigger() names the app and where it runs", {
  expect_warning(
    warn_host_only_trigger(
      serving_app("manual-app", trigger = "manual"),
      "preview_app()"
    ),
    "manual-app.*preview_app\\(\\)"
  )
})
