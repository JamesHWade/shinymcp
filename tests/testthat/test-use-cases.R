use_cases_file <- function() {
  installed <- system.file(
    "examples",
    "use-cases",
    "apps.R",
    package = "shinymcp"
  )
  if (nzchar(installed)) {
    return(installed)
  }

  file.path(
    testthat::test_path("..", ".."),
    "inst",
    "examples",
    "use-cases",
    "apps.R"
  )
}

test_that("use-case examples build and return formatted MCP results", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("base64enc")

  env <- new.env(parent = globalenv())
  source(use_cases_file(), local = env)

  apps <- env$shinymcp_use_cases()
  expect_named(apps, c("revenue", "experiment", "incident"))

  revenue <- format_tool_result(
    apps$revenue$call_tool("forecast_revenue", list())
  )
  expect_named(revenue$structuredContent, c("summary", "forecast", "arr_plot"))
  expect_match(revenue$structuredContent$summary, "ARR")
  expect_match(revenue$structuredContent$forecast, "<table")

  experiment <- format_tool_result(
    apps$experiment$call_tool("plan_experiment", list())
  )
  expect_named(
    experiment$structuredContent,
    c("summary", "design", "power_plot")
  )
  expect_match(experiment$structuredContent$summary, "Run for about")
  expect_match(experiment$structuredContent$design, "<table")

  incident <- format_tool_result(
    apps$incident$call_tool("triage_incident", list())
  )
  expect_named(incident$structuredContent, c("status", "briefing", "runbook"))
  expect_match(incident$structuredContent$status, "Response target")
  expect_match(incident$structuredContent$runbook, "<table")
})

test_that("use-case examples can be wrapped as shinychat tools", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  env <- new.env(parent = globalenv())
  source(use_cases_file(), local = env)

  revenue_tool <- as_shinychat_tool(
    env$shinymcp_use_case("revenue"),
    summary = function(raw_result) raw_result$summary$value,
    title = "Revenue Scenario Board"
  )

  expect_true(inherits(revenue_tool, "ellmer::ToolDef"))

  result <- revenue_tool(segment = "Enterprise")
  expect_true(inherits(result, "ellmer::ContentToolResult"))
  expect_equal(result@extra$display$title, "Revenue Scenario Board")
  expect_match(result@extra$display$text, "Enterprise scenario")
})
