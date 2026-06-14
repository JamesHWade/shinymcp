test_that("scaffold_tool_outputs handles vector-valued arguments", {
  # Multi-select / slider-range / checkbox-group inputs deliver length > 1
  # values; the scaffold tool body must format them without aborting.
  group <- list(
    name = "explore",
    output_targets = list(list(id = "result", type = "text"))
  )

  out <- scaffold_tool_outputs(
    group,
    list(choices = c("a", "b", "c"), n = 5L)
  )

  expect_named(out, "result")
  expect_s3_class(out[["result"]], "shinymcp_result")
})

test_that("scaffold_tool_outputs still handles scalar arguments", {
  group <- list(
    name = "explore",
    output_targets = list(list(id = "result", type = "text"))
  )

  out <- scaffold_tool_outputs(group, list(x = "hello"))

  expect_named(out, "result")
})

test_that("convert_app produces a usable UI for a simple app (no silent degrade)", {
  skip_if_not_installed("ellmer")

  app_dir <- fixture_simple_app()
  out_dir <- tempfile("mcp-convert")
  withr::defer({
    unlink(app_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })

  app <- convert_app(app_dir, output_dir = out_dir)

  expect_s3_class(app, "McpApp")
  html <- app$html_resource()
  expect_false(grepl("Conversion produced no UI", html, fixed = TRUE))
  # The single reactive group must materialize into a tool, not be dropped.
  expect_gte(length(app$tool_definitions()), 1)
})
