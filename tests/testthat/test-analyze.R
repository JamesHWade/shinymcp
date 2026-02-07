test_that("analyze_reactive_graph produces tool groups", {
  app_dir <- fixture_medium_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)

  expect_s3_class(analysis, "ReactiveAnalysis")
  expect_true(length(analysis$tool_groups) > 0)
})

test_that("tool groups have required fields", {
  app_dir <- fixture_simple_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)

  group <- analysis$tool_groups[[1]]
  expect_true("name" %in% names(group))
  expect_true("input_args" %in% names(group))
  expect_true("output_targets" %in% names(group))
})

test_that("analyze errors on non-IR input", {
  expect_error(
    analyze_reactive_graph(list()),
    class = "shinymcp_error_analysis"
  )
})

test_that("complex app generates warnings", {
  app_dir <- fixture_complex_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)

  # Complex apps may have warnings about patterns
  expect_type(analysis$warnings, "character")
})
