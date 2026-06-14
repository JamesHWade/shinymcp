test_that("hello-mcp-minimal previews without error", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("ellmer")
  dir <- system.file("examples", "hello-mcp-minimal", package = "shinymcp")
  skip_if(dir == "", "example not installed")
  srv <- preview_app(dir, launch = FALSE)
  on.exit(srv$stop(), add = TRUE)
  expect_match(srv$url, "^http://127\\.0\\.0\\.1:")
})

test_that("serve-to-client server script builds the expected app", {
  skip_if_not_installed("ellmer")
  path <- system.file(
    "examples",
    "serve-to-client",
    "serve.R",
    package = "shinymcp"
  )
  skip_if(path == "", "example not installed")
  env <- new.env()
  env$serve <- function(app, ...) app # stub so stdio loop never starts
  sys.source(path, envir = env)
  expect_s3_class(env$app, "McpApp")
  expect_identical(env$app$name, "shinymcp-demo")
})

test_that("embed-in-shiny sources into a shiny app object", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("ellmer")
  skip_if_not_installed("bslib")
  path <- system.file(
    "examples",
    "embed-in-shiny",
    "app.R",
    package = "shinymcp"
  )
  skip_if(path == "", "example not installed")
  env <- new.env()
  captured <- new.env()
  env$shinyApp <- function(ui, server, ...) {
    captured$built <- TRUE
    structure(list(), class = "shiny.appobj")
  }
  sys.source(path, envir = env)
  expect_true(isTRUE(captured$built))
})
