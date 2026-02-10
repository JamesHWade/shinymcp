test_that("preview_host_html renders template with app name", {
  html <- preview_host_html("my-test-app")
  expect_type(html, "character")
  expect_match(html, "my-test-app")
  expect_match(html, "shinymcp preview")
  expect_match(html, "postMessage")
})

test_that("preview_host_html escapes HTML in app name", {
  html <- preview_host_html("<script>alert('xss')</script>")
  expect_false(grepl("<script>alert", html, fixed = TRUE))
  expect_match(html, "&lt;script&gt;")
})

test_that("as_mcp_app returns McpApp unchanged", {
  ui <- htmltools::tags$div("Test")
  app <- McpApp$new(ui = ui, name = "pass-through")
  expect_identical(as_mcp_app(app), app)
})

test_that("as_mcp_app errors for non-existent path", {
  expect_error(as_mcp_app("/no/such/path"), "App file not found")
})

test_that("as_mcp_app errors for non-McpApp input", {
  expect_error(as_mcp_app(42), "must be an.*McpApp")
})

test_that("format_tool_result handles named list (structured)", {
  result <- format_tool_result(list(greeting = "hello", count = "5"))
  expect_named(result, c("content", "structuredContent"))
  expect_equal(result$structuredContent$greeting, "hello")
  expect_equal(result$content[[1]]$type, "text")
})

test_that("format_tool_result handles scalar string", {
  result <- format_tool_result("just text")
  expect_named(result, "content")
  expect_equal(result$content[[1]]$text, "just text")
})

test_that("preview_route returns host page on /", {
  ui <- htmltools::tags$div("Hello")
  app <- McpApp$new(ui = ui, name = "route-test")
  host_html <- "<html>host</html>"
  app_html <- "<html>app</html>"

  req <- list(PATH_INFO = "/", REQUEST_METHOD = "GET")
  resp <- preview_route(req, app, host_html, app_html)
  expect_equal(resp$status, 200L)
  expect_equal(resp$body, host_html)
})

test_that("preview_route returns app HTML on /app.html", {
  ui <- htmltools::tags$div("Hello")
  app <- McpApp$new(ui = ui, name = "route-test")
  host_html <- "<html>host</html>"
  app_html <- "<html>app</html>"

  req <- list(PATH_INFO = "/app.html", REQUEST_METHOD = "GET")
  resp <- preview_route(req, app, host_html, app_html)
  expect_equal(resp$status, 200L)
  expect_equal(resp$body, app_html)
})

test_that("preview_route returns 404 for unknown paths", {
  ui <- htmltools::tags$div("Hello")
  app <- McpApp$new(ui = ui, name = "route-test")

  req <- list(PATH_INFO = "/nope", REQUEST_METHOD = "GET")
  resp <- preview_route(req, app, "", "")
  expect_equal(resp$status, 404L)
})

test_that("preview_app starts and stops server", {
  skip_if_not_installed("httpuv")

  ui <- htmltools::tagList(
    mcp_text_input("name", "Name"),
    mcp_text("output")
  )
  tools <- list(
    list(
      name = "greet",
      fun = function(name = "world") {
        list(output = paste0("Hello, ", name, "!"))
      }
    )
  )
  app <- McpApp$new(ui = ui, tools = tools, name = "preview-test")

  srv <- preview_app(app, launch = FALSE)
  on.exit(srv$stop(), add = TRUE)

  expect_type(srv$url, "character")
  expect_match(srv$url, "^http://")
  expect_type(srv$stop, "closure")

  # Server is running — fetch the host page
  host_resp <- tryCatch(
    {
      con <- url(srv$url, open = "rb")
      on.exit(close(con), add = TRUE)
      rawToChar(readBin(con, raw(), 100000))
    },
    error = function(e) NULL
  )

  skip_if(is.null(host_resp), "Could not connect to preview server")

  expect_match(host_resp, "preview-test")
  expect_match(host_resp, "shinymcp preview")
})
