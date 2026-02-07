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

  expect_output(print(app), "McpApp")
})
