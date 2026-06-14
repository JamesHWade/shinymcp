test_that("tool_definitions surfaces annotation hints in camelCase", {
  app <- McpApp$new(
    ui = htmltools::tags$div(
      `data-shinymcp-output` = "result",
      `data-shinymcp-output-type` = "text"
    ),
    tools = list(list(
      name = "compute",
      description = "Compute a value",
      inputSchema = list(type = "object", properties = list()),
      annotations = list(read_only_hint = TRUE, destructive_hint = FALSE),
      fun = function(...) list(result = "ok")
    )),
    name = "demo"
  )

  d <- app$tool_definitions()[[1]]
  expect_equal(d$annotations$readOnlyHint, TRUE)
  expect_equal(d$annotations$destructiveHint, FALSE)
})

test_that("tool_definitions derives an outputSchema from .output_ids", {
  app <- McpApp$new(
    ui = htmltools::tags$div(
      `data-shinymcp-output` = "result",
      `data-shinymcp-output-type` = "text"
    ),
    tools = list(list(
      name = "compute",
      description = "Compute a value",
      inputSchema = list(type = "object", properties = list()),
      .output_ids = "result",
      fun = function(...) list(result = "ok")
    )),
    name = "demo"
  )

  d <- app$tool_definitions()[[1]]
  expect_false(is.null(d$outputSchema))
  expect_true("result" %in% names(d$outputSchema$properties))
  expect_equal(d$outputSchema$properties$result$type, "string")
})

test_that("normalize_tool_annotations maps snake_case and drops unknown keys", {
  out <- normalize_tool_annotations(list(
    read_only_hint = TRUE,
    open_world_hint = FALSE,
    title = "Demo",
    bogus = "ignored"
  ))

  expect_equal(out$readOnlyHint, TRUE)
  expect_equal(out$openWorldHint, FALSE)
  expect_equal(out$title, "Demo")
  expect_null(out$bogus)
  expect_null(normalize_tool_annotations(list()))
})
