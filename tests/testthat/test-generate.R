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
  expect_true(file.exists(file.path(out_dir, "app.R")))
  expect_false(file.exists(file.path(out_dir, "server.R")))
})

test_that("the drafted app.R runs when Rscript starts it elsewhere", {
  app_dir <- fixture_simple_app()
  out_dir <- tempfile("mcp-out")
  withr::defer({
    unlink(app_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })
  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)
  generate_mcp_app(analysis, ir, out_dir)

  withr::local_dir(withr::local_tempdir())
  script <- normalizePath(file.path(out_dir, "app.R"))
  env <- new.env()
  # As `Rscript /full/path/app.R` runs it, from another directory.
  env$commandArgs <- function(...) {
    c("R", "--no-echo", "--no-restore", paste0("--file=", script))
  }
  env$interactive <- function() FALSE
  env$serve <- function(app, ...) invisible(app)
  source(script, local = env)

  expect_s3_class(env$app, "McpApp")
  expect_identical(normalizePath(getwd()), normalizePath(out_dir))
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

test_that("generated tools.R sources and its tools are invocable", {
  skip_if_not_installed("ellmer")

  app_dir <- fixture_simple_app()
  out_dir <- tempfile("mcp-out")
  withr::defer({
    unlink(app_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)
  generate_mcp_app(analysis, ir, out_dir)

  env <- new.env(parent = globalenv())
  source(file.path(out_dir, "tools.R"), local = env)

  expect_true(exists("tools", envir = env))
  tools <- get("tools", envir = env)
  expect_gte(length(tools), 1)

  # The draft runs, and returns a list named by the group's outputs.
  result <- do.call(tools[[1]], list(x = "a"))
  expect_named(result, "result")
})

test_that("generated tool bodies carry the original render logic as a comment", {
  app_dir <- fixture_simple_app()
  out_dir <- tempfile("mcp-out")
  withr::defer({
    unlink(app_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)
  generate_mcp_app(analysis, ir, out_dir)

  tools_code <- paste(
    readLines(file.path(out_dir, "tools.R")),
    collapse = "\n"
  )
  expect_match(tools_code, "# From the Shiny app:", fixed = TRUE)
  expect_match(tools_code, "output$result <- renderText", fixed = TRUE)
  expect_match(tools_code, "You chose:")
})

test_that("generate_tools output is stable for the simple app", {
  app_dir <- fixture_simple_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)

  expect_snapshot(cat(generate_tools(analysis$tool_groups, ir$reactives)))
})

test_that("drafted tools carry the reactive expressions they use", {
  app_dir <- fixture_chained_reactive_app()
  withr::defer(unlink(app_dir, recursive = TRUE))
  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)
  code <- generate_tools(analysis$tool_groups, ir$reactives)
  for (r in ir$reactives) {
    expect_match(code, paste0(r$name, " <- reactive("), fixed = TRUE)
  }
})

test_that("drafted arguments are typed, with the app's defaults", {
  inp <- function(type, label, args) {
    list(id = "x", type = type, label = label, args = args)
  }
  sel <- draft_argument(inp(
    "select",
    "Dataset:",
    list(choices = quote(c("a", "b")), selected = "b")
  ))
  expect_identical(
    sel$type,
    'ellmer::type_enum(c("a", "b"), "Dataset", required = FALSE)'
  )
  expect_identical(sel$default, '"b"')

  first <- draft_argument(inp(
    "select",
    "Pick",
    list(choices = quote(c("a", "b")))
  ))
  expect_identical(first$default, '"a"')

  num <- draft_argument(inp("numeric", "Observations:", list(value = 10)))
  expect_identical(
    num$type,
    'ellmer::type_number("Observations", required = FALSE)'
  )
  expect_identical(num$default, "10")

  free <- draft_argument(inp(
    "select",
    "Column",
    list(choices = quote(names(data)))
  ))
  expect_identical(free$type, 'ellmer::type_string("Column")')
  expect_null(free$default)

  flag <- draft_argument(inp("checkbox", "Smooth", list()))
  expect_identical(flag$default, "FALSE")
})
