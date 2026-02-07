test_that("generate_mcp_app creates output files", {
  app_dir <- fixture_simple_app()
  out_dir <- tempfile("mcp-out")
  withr::defer({
    unlink(app_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)
  generate_mcp_app(analysis, ir, out_dir)

  expect_true(file.exists(file.path(out_dir, "ui.html")))
  expect_true(file.exists(file.path(out_dir, "tools.R")))
  expect_true(file.exists(file.path(out_dir, "server.R")))
  expect_true(file.exists(file.path(out_dir, "app.R")))
})

test_that("generated HTML contains MCP components", {
  app_dir <- fixture_simple_app()
  out_dir <- tempfile("mcp-out")
  withr::defer({
    unlink(app_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)
  generate_mcp_app(analysis, ir, out_dir)

  html <- readLines(file.path(out_dir, "ui.html"))
  html_text <- paste(html, collapse = "\n")
  expect_match(html_text, "mcp_")
})

test_that("complex app generates CONVERSION_NOTES.md", {
  app_dir <- fixture_complex_app()
  out_dir <- tempfile("mcp-out")
  withr::defer({
    unlink(app_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)
  generate_mcp_app(analysis, ir, out_dir)

  expect_true(file.exists(file.path(out_dir, "CONVERSION_NOTES.md")))
})
