test_that("McpApp creates successfully", {
  ui <- htmltools::tagList(
    htmltools::tags$div("Hello")
  )
  app <- McpApp$new(ui = ui, name = "test-app")

  expect_s3_class(app, "McpApp")
  expect_equal(app$name, "test-app")
  expect_equal(app$resource_uri(), "ui://test-app")
})

test_that("McpApp generates HTML resource", {
  ui <- htmltools::tagList(
    htmltools::tags$div("Test content")
  )
  app <- McpApp$new(ui = ui, name = "test-app")
  html <- app$html_resource()

  expect_type(html, "character")
  expect_match(html, "<!DOCTYPE html>")
  expect_match(html, "Test content")
  expect_match(html, "shinymcp-config")
})

test_that("McpApp annotates tools with metadata", {
  ui <- htmltools::tags$div("Test")
  tools <- list(
    list(name = "tool1", description = "A tool")
  )
  app <- McpApp$new(ui = ui, tools = tools, name = "test-app")
  annotated <- app$mcp_tools()

  expect_true(length(annotated) == 1)
})

test_that("mcp_app convenience function works", {
  ui <- htmltools::tags$div("Hello")
  app <- mcp_app(ui, name = "my-app")

  expect_s3_class(app, "McpApp")
  expect_equal(app$name, "my-app")
})

test_that("McpApp print method works", {
  ui <- htmltools::tags$div("Hello")
  app <- McpApp$new(ui = ui, name = "print-test")

  expect_no_error(print(app))
})

test_that("McpApp handles ellmer S7 tools", {
  ui <- htmltools::tags$div("Hello")
  tools <- list(
    ellmer::tool(
      fun = function(x = "a") x,
      name = "echo",
      description = "Echo the input",
      arguments = list(x = ellmer::type_string("Value to echo"))
    )
  )
  app <- McpApp$new(ui = ui, tools = tools, name = "s7-test")

  # tool_definitions returns proper schema
  defs <- app$tool_definitions()
  expect_equal(length(defs), 1)
  expect_equal(defs[[1]]$name, "echo")
  expect_equal(defs[[1]]$description, "Echo the input")
  expect_equal(defs[[1]]$inputSchema$type, "object")
  expect_equal(defs[[1]]$inputSchema$properties$x$type, "string")

  # call_tool dispatches correctly
  result <- app$call_tool("echo", list(x = "hello"))
  expect_equal(result, "hello")
})

test_that("McpApp call_tool errors for unknown tool", {
  ui <- htmltools::tags$div("Hello")
  app <- McpApp$new(ui = ui, tools = list(), name = "empty")

  expect_error(
    app$call_tool("nonexistent"),
    class = "shinymcp_error_tool_not_found"
  )
})
