# preview_app() and its host page (R/preview.R).

# Start a preview without opening a browser, or skip where no local server
# can be started.
start_preview <- function(...) {
  tryCatch(
    suppressMessages(preview_app(..., launch = FALSE)),
    shinymcp_error = function(e) {
      if (
        grepl(
          "Couldn't start a local server",
          conditionMessage(e),
          fixed = TRUE
        )
      ) {
        skip("Can't start a local httpuv server here.")
      }
      stop(e)
    }
  )
}

noop_app <- list(call = function(req) {
  list(status = 200L, headers = list(), body = "ok")
})

# ---- fill_template() ----

test_that("fill_template() replaces each placeholder with its value", {
  expect_equal(
    fill_template(
      "<h1>{{TITLE}}</h1><p>{{BODY_TEXT}}</p>{{TITLE}}",
      list(TITLE = "Hi", BODY_TEXT = "there")
    ),
    "<h1>Hi</h1><p>there</p>Hi"
  )
  expect_equal(fill_template("a\n{{X}}\nb", list(X = "line")), "a\nline\nb")
})

test_that("fill_template() never rescans text it inserted", {
  template <- "<title>{{TITLE}}</title><script>{{CONFIG}}</script>"
  filled <- fill_template(
    template,
    list(TITLE = "Beware {{CONFIG}}", CONFIG = "{\"a\":1}")
  )
  expect_equal(
    filled,
    "<title>Beware {{CONFIG}}</title><script>{\"a\":1}</script>"
  )

  filled <- fill_template("{{A}}{{B}}", list(A = "{{B}}", B = "{{A}}"))
  expect_equal(filled, "{{B}}{{A}}")
})

test_that("fill_template() inserts values literally", {
  values <- list(X = "\\1 $1 \\\\ & \\U{{", Y = "été ✓")
  expect_equal(
    fill_template("[{{X}}] [{{Y}}]", values),
    paste0("[", values$X, "] [", values$Y, "]")
  )
})

test_that("fill_template() leaves unknown and malformed placeholders alone", {
  expect_equal(
    fill_template("{{MISSING}} {{X}}", list(X = "x")),
    "{{MISSING}} x"
  )
  expect_equal(
    fill_template("{{lower}} {{ X }} {X} {{X1}}", list(X = "x", lower = "y")),
    "{{lower}} {{ X }} {X} {{X1}}"
  )
  expect_equal(
    fill_template("no placeholders", list(X = "x")),
    "no placeholders"
  )
  expect_equal(fill_template("", list(X = "x")), "")
})

# ---- preview_page() ----

test_that("preview_page() fills the template and embeds the host script", {
  server <- McpServer$new(serving_app(title = "Echo"))
  page <- preview_page(server, "echo")

  expect_match(page, "^<!DOCTYPE html>")
  expect_false(grepl("{{", page, fixed = TRUE))
  expect_match(page, "<title>Echo · shinymcp preview</title>", fixed = TRUE)
  expect_match(page, '<h1 id="title">Echo</h1>', fixed = TRUE)
  host_js <- escape_inline_close(
    read_package_file("js", "shinymcp-host.js"),
    "script"
  )
  expect_true(grepl(host_js, page, fixed = TRUE))
})

test_that("preview_page() embeds the preview configuration", {
  server <- McpServer$new(serving_app(title = "Echo"))
  config <- serving_preview_config(preview_page(server, "echo", list(x = "hi")))

  expect_equal(config$title, "Echo")
  expect_equal(config$endpoint, "mcp")
  expect_equal(config$entryTool, "echo")
  expect_equal(config$arguments, list(x = "hi"))
  expect_equal(config$protocolVersion, "2026-07-28")
  expect_equal(config$appsProtocolVersion, "2026-01-26")
  expect_equal(config$version, as.character(utils::packageVersion("shinymcp")))
})

test_that("preview_page() sends empty arguments as an object", {
  server <- McpServer$new(serving_app())
  page <- preview_page(server, "echo")
  expect_match(page, '"arguments":{}', fixed = TRUE)
  expect_equal(
    serving_preview_config(page)$arguments,
    setNames(list(), character())
  )
})

test_that("preview_page() without an entry tool says so", {
  server <- McpServer$new(serving_app(tools = list()))
  page <- preview_page(server)
  expect_match(page, '"entryTool":null', fixed = TRUE)
  config <- serving_preview_config(page)
  expect_true("entryTool" %in% names(config))
  expect_null(config$entryTool)
})

test_that("preview_page() titles the page after the app, or shinymcp for several", {
  untitled <- McpServer$new(serving_app("my-app"))
  expect_equal(serving_preview_config(preview_page(untitled))$title, "my-app")

  several <- McpServer$new(list(
    serving_app(
      "alpha",
      tools = list(serving_echo_tool("alpha_echo")),
      title = "Alpha"
    ),
    serving_app(
      "beta",
      tools = list(serving_echo_tool("beta_echo")),
      title = "Beta"
    )
  ))
  page <- preview_page(several, "beta_echo")
  expect_equal(serving_preview_config(page)$title, "shinymcp")
  expect_match(page, '<h1 id="title">shinymcp</h1>', fixed = TRUE)
})

test_that("preview_page() escapes the title in HTML and in the configuration", {
  server <- McpServer$new(serving_app(title = "Q&A <b>bold</b>"))
  page <- preview_page(server, "echo")
  escaped <- "Q&amp;A &lt;b&gt;bold&lt;/b&gt;"
  expect_match(
    page,
    paste0("<title>", escaped, " · shinymcp preview</title>"),
    fixed = TRUE
  )
  expect_match(page, paste0('<h1 id="title">', escaped, "</h1>"), fixed = TRUE)
  expect_equal(serving_preview_config(page)$title, "Q&A <b>bold</b>")
})

test_that("a title can't close the configuration's script element", {
  title <- "</script><script>alert(1)</script>"
  server <- McpServer$new(serving_app(title = title))
  page <- preview_page(server, "echo", list(x = "</script>"))

  expect_false(grepl("</script><script>alert(1)", page, fixed = TRUE))
  config <- serving_preview_config(page)
  expect_equal(config$title, title)
  expect_equal(config$arguments$x, "</script>")
})

test_that("configuration text containing <!-- stays valid JSON", {
  server <- McpServer$new(serving_app(title = "Notes <!-- draft -->"))
  page <- preview_page(server, "echo")
  expect_false(grepl("<!--", page, fixed = TRUE))
  expect_equal(serving_preview_config(page)$title, "Notes <!-- draft -->")
})

# ---- start_local_server() ----

test_that("start_local_server() listens on the port it is given", {
  skip_if_not_installed("httpuv")
  port <- httpuv::randomPort()
  started <- tryCatch(
    start_local_server("127.0.0.1", port, noop_app),
    error = function(e) NULL
  )
  skip_if(is.null(started), "Can't start a local httpuv server here.")
  on.exit(httpuv::stopServer(started$server), add = TRUE)
  expect_equal(started$port, port)
  expect_equal(serving_http(port, "GET", "/")$body, "ok")
})

test_that("start_local_server() picks a free port when none is given", {
  skip_if_not_installed("httpuv")
  started <- tryCatch(
    start_local_server("127.0.0.1", NULL, noop_app),
    error = function(e) NULL
  )
  skip_if(is.null(started), "Can't start a local httpuv server here.")
  on.exit(httpuv::stopServer(started$server), add = TRUE)
  expect_true(started$port >= 1024 && started$port <= 65535)
  expect_equal(serving_http(started$port, "GET", "/")$status, 200L)
})

test_that("start_local_server() falls back to other ports when one is taken", {
  skip_if_not_installed("httpuv")
  real_start <- httpuv::startServer
  attempts <- integer()
  local_mocked_bindings(
    randomPort = function(...) 4242L,
    startServer = function(host, port, app, ...) {
      attempts <<- c(attempts, port)
      if (length(attempts) == 1) {
        stop("Failed to create server")
      }
      real_start(host, port, app, ...)
    },
    .package = "httpuv"
  )
  started <- tryCatch(
    start_local_server("127.0.0.1", NULL, noop_app),
    error = function(e) NULL
  )
  skip_if(is.null(started), "Can't start a local httpuv server here.")
  on.exit(httpuv::stopServer(started$server), add = TRUE)

  expect_equal(attempts[[1]], 4242L)
  expect_gte(length(attempts), 2)
  expect_equal(started$port, attempts[[length(attempts)]])
  expect_true(started$port >= 3000 && started$port <= 9000)
})

test_that("start_local_server() falls back when httpuv can't suggest a port", {
  skip_if_not_installed("httpuv")
  local_mocked_bindings(
    randomPort = function(...) stop("no ports"),
    .package = "httpuv"
  )
  started <- tryCatch(
    start_local_server("127.0.0.1", NULL, noop_app),
    error = function(e) NULL
  )
  skip_if(is.null(started), "Can't start a local httpuv server here.")
  on.exit(httpuv::stopServer(started$server), add = TRUE)
  expect_true(started$port >= 3000 && started$port <= 9000)
})

test_that("start_local_server() reports the last failure when no port works", {
  skip_if_not_installed("httpuv")
  attempts <- 0L
  local_mocked_bindings(
    startServer = function(...) {
      attempts <<- attempts + 1L
      stop("Failed to create server")
    },
    .package = "httpuv"
  )
  expect_error(
    start_local_server("127.0.0.1", 8123, noop_app),
    "Couldn't start a local server.*Failed to create server",
    class = "shinymcp_error"
  )
  # A port that was asked for is the only one tried.
  expect_equal(attempts, 1L)

  expect_error(
    start_local_server("127.0.0.1", NULL, noop_app),
    class = "shinymcp_error"
  )
  expect_gt(attempts, 2L)
})

test_that("start_local_server() fails cleanly on a port that is in use", {
  skip_if_not_installed("httpuv")
  busy <- tryCatch(
    start_local_server("127.0.0.1", NULL, noop_app),
    error = function(e) NULL
  )
  skip_if(is.null(busy), "Can't start a local httpuv server here.")
  on.exit(httpuv::stopServer(busy$server), add = TRUE)
  expect_error(
    start_local_server("127.0.0.1", busy$port, noop_app),
    class = "shinymcp_error"
  )
})

# ---- preview_app() ----

test_that("preview_app() serves the host page and the app's MCP endpoint", {
  skip_if_not_installed("httpuv")
  preview <- start_preview(
    serving_app(title = "Echo Preview"),
    arguments = list(x = "hi")
  )
  on.exit(preview$stop(), add = TRUE)

  expect_named(preview, c("url", "port", "stop"))
  expect_equal(preview$url, sprintf("http://127.0.0.1:%d/", preview$port))
  expect_true(is.function(preview$stop))

  page <- serving_http(preview$port, "GET", "/")
  expect_equal(page$status, 200L)
  expect_equal(page$headers[["content-type"]], "text/html; charset=utf-8")
  expect_equal(page$headers[["cache-control"]], "no-store")
  expect_match(
    page$body,
    "<title>Echo Preview · shinymcp preview</title>",
    fixed = TRUE
  )
  config <- serving_preview_config(page$body)
  expect_equal(config$entryTool, "echo")
  expect_equal(config$arguments, list(x = "hi"))

  expect_equal(serving_http(preview$port, "GET", "/index.html")$body, page$body)

  message <- serving_modern(
    "tools/call",
    list(name = "echo", arguments = list(x = "previewed"))
  )
  call <- serving_http(
    preview$port,
    "POST",
    "/mcp",
    message,
    c(
      serving_modern_headers(message),
      list(`Content-Type` = "application/json")
    )
  )
  expect_equal(call$status, 200L)
  expect_equal(
    jsonlite::fromJSON(call$body)$result$structuredContent$out,
    "previewed"
  )

  init <- serving_http(preview$port, "POST", "/mcp", serving_initialize())
  expect_match(init$headers[["mcp-session-id"]], "^mcp-")

  missing <- serving_http(preview$port, "GET", "/nope")
  expect_equal(missing$status, 404L)
  expect_equal(missing$body, "Not found")
})

test_that("preview_app() announces its URL", {
  skip_if_not_installed("httpuv")
  preview <- NULL
  expect_message(
    preview <- tryCatch(
      preview_app(serving_app(), launch = FALSE),
      shinymcp_error = function(e) NULL
    ),
    "Previewing at",
    class = "shinymcp_message"
  )
  skip_if(is.null(preview), "Can't start a local httpuv server here.")
  preview$stop()
})

test_that("preview_app() stop() frees the port", {
  skip_if_not_installed("httpuv")
  preview <- start_preview(serving_app())
  preview$stop()
  again <- tryCatch(
    httpuv::startServer("127.0.0.1", preview$port, noop_app),
    error = function(e) NULL
  )
  expect_false(is.null(again))
  if (!is.null(again)) {
    httpuv::stopServer(again)
  }
})

test_that("preview_app() listens on the port it is given", {
  skip_if_not_installed("httpuv")
  port <- httpuv::randomPort()
  preview <- start_preview(serving_app(), port = port)
  on.exit(preview$stop(), add = TRUE)
  expect_equal(preview$port, port)
  expect_equal(preview$url, sprintf("http://127.0.0.1:%d/", port))
})

test_that("preview_app() opens the entry tool the model would call first", {
  skip_if_not_installed("httpuv")
  app <- serving_app(
    tools = list(
      list(
        name = "app_only",
        description = "UI only.",
        visibility = "app",
        fun = function() list(out = "a")
      ),
      serving_echo_tool("first_for_model"),
      serving_echo_tool("second_for_model")
    )
  )
  preview <- start_preview(app)
  on.exit(preview$stop(), add = TRUE)
  config <- serving_preview_config(serving_http(preview$port, "GET", "/")$body)
  expect_equal(config$entryTool, "first_for_model")
  expect_equal(config$arguments, setNames(list(), character()))
})

test_that("preview_app() can open another tool first", {
  skip_if_not_installed("httpuv")
  preview <- start_preview(
    serving_app(),
    tool = "boom",
    arguments = list(reason = "testing")
  )
  on.exit(preview$stop(), add = TRUE)
  config <- serving_preview_config(serving_http(preview$port, "GET", "/")$body)
  expect_equal(config$entryTool, "boom")
  expect_equal(config$arguments, list(reason = "testing"))
})

test_that("preview_app() opens a browser when asked", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("withr")
  opened <- NULL
  withr::local_options(browser = function(url) opened <<- url)
  preview <- tryCatch(
    suppressMessages(preview_app(serving_app(), launch = TRUE)),
    shinymcp_error = function(e) NULL
  )
  skip_if(is.null(preview), "Can't start a local httpuv server here.")
  on.exit(preview$stop(), add = TRUE)
  expect_equal(opened, preview$url)
})

test_that("preview_app() warns when an app needs a host that runs its tools", {
  skip_if_not_installed("httpuv")
  expect_warning(
    preview <- start_preview(serving_app(trigger = "manual")),
    "manual"
  )
  on.exit(preview$stop(), add = TRUE)
  expect_equal(serving_http(preview$port, "GET", "/")$status, 200L)
})

test_that("preview_app() answers 500 when the MCP handler fails", {
  skip_if_not_installed("httpuv")
  local_mocked_bindings(mcp_http_handler = function(...) {
    function(req) stop("handler exploded")
  })
  preview <- start_preview(serving_app())
  on.exit(preview$stop(), add = TRUE)

  response <- serving_http(preview$port, "POST", "/mcp", serving_rpc("ping"))
  expect_equal(response$status, 500L)
  expect_equal(response$headers[["content-type"]], "text/plain")
  expect_equal(response$body, "Internal server error: handler exploded")
  # The page itself doesn't go through the handler.
  expect_equal(serving_http(preview$port, "GET", "/")$status, 200L)
})

test_that("preview_app() rejects things that aren't apps", {
  skip_if_not_installed("httpuv")
  expect_error(
    preview_app(42, launch = FALSE),
    class = "shinymcp_error_validation"
  )
})
