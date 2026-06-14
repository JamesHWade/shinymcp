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

  expect_true(file.exists(file.path(out_dir, "ui.R")))
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

  html <- readLines(file.path(out_dir, "ui.R"))
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

test_that("every generated R file is syntactically valid R", {
  fixtures <- list(
    fixture_simple_app,
    fixture_medium_app,
    fixture_complex_app,
    fixture_chained_reactive_app,
    fixture_multi_reactive_deps_app
  )
  for (make_fixture in fixtures) {
    app_dir <- make_fixture()
    out_dir <- tempfile("mcp-out")
    withr::defer({
      unlink(app_dir, recursive = TRUE)
      unlink(out_dir, recursive = TRUE)
    })

    ir <- parse_shiny_app(app_dir)
    analysis <- analyze_reactive_graph(ir)
    generate_mcp_app(analysis, ir, out_dir)

    r_files <- list.files(out_dir, pattern = "\\.R$", full.names = TRUE)
    expect_true(length(r_files) >= 1)
    for (f in r_files) {
      expect_silent(parse(file = f))
    }
  }
})

test_that("extract_arg_code collapses multi-line deparse to one parseable string", {
  # A wide value whose deparse wraps across lines must not leak a character
  # vector into sprintf(), which would recycle it into broken R.
  wide <- list(
    value = str2lang(paste0("c(", paste(1:200, collapse = ", "), ")"))
  )
  code <- extract_arg_code(wide, "value")

  expect_length(code, 1)
  expect_silent(parse(text = sprintf("f(value = %s)", code)))
})

test_that("validate_generated_r aborts on unparseable generated code", {
  good <- tempfile(fileext = ".R")
  bad <- tempfile(fileext = ".R")
  withr::defer(unlink(c(good, bad)))

  writeLines("x <- 1", good)
  writeLines("x <- function( {", bad)

  expect_silent(validate_generated_r(good))
  expect_error(
    validate_generated_r(bad),
    class = "shinymcp_error_generation"
  )
})
