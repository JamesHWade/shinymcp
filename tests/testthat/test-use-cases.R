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
  expect_true(nzchar(revenue$structuredContent$arr_plot))

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

test_that("incident triage classifies P1, P2, and regulated-data comms correctly", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("base64enc")

  env <- new.env(parent = globalenv())
  source(use_cases_file(), local = env)
  app <- env$shinymcp_use_case("incident")

  # P1: outage severity
  p1 <- app$call_tool(
    "triage_incident",
    list(
      service = "Payments",
      severity = "Outage",
      affected_users = 100
    )
  )
  expect_match(p1$briefing$value, "P1")
  expect_match(p1$status$text, "15 minutes")

  # P1: large user count
  p1_count <- app$call_tool(
    "triage_incident",
    list(
      service = "API",
      severity = "Minor",
      affected_users = 6000
    )
  )
  expect_match(p1_count$briefing$value, "P1")

  # P2: degraded severity
  p2 <- app$call_tool(
    "triage_incident",
    list(
      service = "Login",
      severity = "Degraded",
      affected_users = 100
    )
  )
  expect_match(p2$briefing$value, "P2")
  expect_match(p2$status$text, "30 minutes")

  # P2: regulated data promotes from P3
  p2_regulated <- app$call_tool(
    "triage_incident",
    list(
      service = "Login",
      severity = "Minor",
      affected_users = 10,
      regulated_data = TRUE
    )
  )
  expect_match(p2_regulated$briefing$value, "P2")
  expect_match(p2_regulated$runbook$value$action[[3]], "privacy/legal")
})

test_that("shinymcp_use_case errors on unknown name", {
  skip_if_not_installed("ellmer")

  env <- new.env(parent = globalenv())
  source(use_cases_file(), local = env)

  expect_error(env$shinymcp_use_case("unknown"), "Unknown use case")
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
