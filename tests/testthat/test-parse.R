test_that("parse_shiny_app extracts inputs from simple app", {
  app_dir <- fixture_simple_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  expect_s3_class(ir, "ShinyAppIR")
  expect_length(ir$inputs, 1)
  expect_equal(ir$inputs[[1]]$id, "x")
  expect_equal(ir$inputs[[1]]$type, "select")
})

test_that("parse_shiny_app extracts outputs from simple app", {
  app_dir <- fixture_simple_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  expect_length(ir$outputs, 1)
  expect_equal(ir$outputs[[1]]$id, "result")
  expect_equal(ir$outputs[[1]]$type, "text")
})

test_that("parse_shiny_app classifies simple app complexity", {
  app_dir <- fixture_simple_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  expect_equal(ir$complexity, "simple")
})

test_that("parse_shiny_app handles medium complexity", {
  app_dir <- fixture_medium_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  expect_length(ir$inputs, 2)
  expect_length(ir$outputs, 2)
  expect_true(length(ir$reactives) > 0)
  expect_equal(ir$complexity, "medium")
})

test_that("parse_shiny_app handles split ui.R/server.R apps", {
  app_dir <- fixture_split_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  expect_length(ir$inputs, 1)
  expect_equal(ir$inputs[[1]]$type, "text")
})

test_that("parse_shiny_app errors on invalid path", {
  expect_error(
    parse_shiny_app(tempfile()),
    class = "shinymcp_error_parse"
  )
})
