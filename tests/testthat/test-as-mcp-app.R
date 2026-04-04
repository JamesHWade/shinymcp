# Tests for as_mcp_app() and mcp_tool_module()

# ---- as_mcp_app.shiny.appobj ----

test_that("as_mcp_app converts a simple shinyApp", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("x", "X:", c("a", "b")),
    shiny::textOutput("result")
  )
  server <- function(input, output, session) {
    output$result <- shiny::renderText({
      paste("You chose:", input$x)
    })
  }
  app <- shiny::shinyApp(ui, server)
  mcp <- as_mcp_app(app, name = "test-app", selective = FALSE)
  expect_s3_class(mcp, "McpApp")
  expect_equal(mcp$name, "test-app")
})

test_that("as_mcp_app respects bindMcp annotations in selective mode", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("x", "X:", c("a", "b")) |> bindMcp(),
    shiny::numericInput("n", "N:", 10),
    shiny::textOutput("result") |> bindMcp()
  )
  server <- function(input, output, session) {
    output$result <- shiny::renderText(input$x)
  }
  app <- shiny::shinyApp(ui, server)
  mcp <- as_mcp_app(app, name = "selective-app")

  # Should auto-detect selective = TRUE because bindMcp annotations exist
  tools <- mcp$tool_definitions()
  expect_true(length(tools) > 0)
})

test_that("as_mcp_app uses explicit tools when provided", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("x", "X:", c("a", "b")),
    shiny::textOutput("result")
  )
  server <- function(input, output, session) {
    output$result <- shiny::renderText(input$x)
  }
  explicit_tool <- list(
    name = "my_tool",
    description = "A custom tool",
    fun = function(x = "a") list(result = x),
    inputSchema = list(
      type = "object",
      properties = list(x = list(type = "string"))
    )
  )
  app <- shiny::shinyApp(ui, server)
  mcp <- as_mcp_app(app, name = "explicit-tools", tools = list(explicit_tool))

  tool_defs <- mcp$tool_definitions()
  expect_equal(length(tool_defs), 1)
  expect_equal(tool_defs[[1]]$name, "my_tool")
  expect_match(mcp$html_resource(), 'data-shinymcp-input="x"')
  expect_match(mcp$html_resource(), 'data-shinymcp-output="result"')
})

test_that("as_mcp_app.McpApp is identity", {
  ui <- htmltools::tags$div("hello")
  app <- McpApp$new(ui = ui, tools = list(), name = "identity")
  result <- as_mcp_app(app)
  expect_identical(result, app)
})

test_that("as_mcp_app.default errors on bad input", {
  expect_error(as_mcp_app(42), class = "shinymcp_error_validation")
})

test_that("as_mcp_app converts a path containing a standard shiny app", {
  skip_if_not_installed("shiny")

  app_dir <- tempfile("shinymcp-path-app-")
  dir.create(app_dir)
  on.exit(unlink(app_dir, recursive = TRUE), add = TRUE)

  writeLines(
    c(
      "library(shiny)",
      "ui <- fluidPage(",
      "  selectInput(\"x\", \"X:\", c(\"a\", \"b\")),",
      "  textOutput(\"result\")",
      ")",
      "server <- function(input, output, session) {",
      "  output$result <- renderText(input$x)",
      "}",
      "shinyApp(ui, server)"
    ),
    file.path(app_dir, "app.R")
  )

  mcp <- as_mcp_app(app_dir, name = "path-app", selective = FALSE)
  expect_s3_class(mcp, "McpApp")
  expect_equal(mcp$name, "path-app")
})

test_that("as_mcp_app sources path-based apps relative to app directory", {
  skip_if_not_installed("shiny")

  app_dir <- tempfile("shinymcp-relative-app-")
  dir.create(app_dir)
  on.exit(unlink(app_dir, recursive = TRUE), add = TRUE)

  writeLines(
    c(
      "get_choices <- function() c(\"a\", \"b\")"
    ),
    file.path(app_dir, "helpers.R")
  )

  writeLines(
    c(
      "library(shiny)",
      "source(\"helpers.R\")",
      "ui <- fluidPage(",
      "  selectInput(\"x\", \"X:\", get_choices()),",
      "  textOutput(\"result\")",
      ")",
      "server <- function(input, output, session) {",
      "  output$result <- renderText(input$x)",
      "}",
      "shinyApp(ui, server)"
    ),
    file.path(app_dir, "app.R")
  )

  mcp <- as_mcp_app(app_dir, name = "relative-path-app", selective = FALSE)
  expect_s3_class(mcp, "McpApp")
  expect_equal(mcp$name, "relative-path-app")
})


# ---- mcp_tool_module ----

test_that("mcp_tool_module creates McpApp from module with handler", {
  skip_if_not_installed("shiny")
  mod_ui <- function(id) {
    ns <- shiny::NS(id)
    htmltools::tagList(
      shiny::selectInput(ns("choice"), "Pick:", c("a", "b")),
      shiny::textOutput(ns("result"))
    )
  }
  mod_server <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      output$result <- shiny::renderText(input$choice)
    })
  }
  handler <- function(choice = "a") {
    list(result = paste("Chose:", choice))
  }

  app <- mcp_tool_module(
    mod_ui,
    mod_server,
    name = "test-module",
    description = "A test module",
    handler = handler
  )

  expect_s3_class(app, "McpApp")
  expect_equal(app$name, "test-module")

  # Should have one tool
  tool_defs <- app$tool_definitions()
  expect_equal(length(tool_defs), 1)
  expect_equal(tool_defs[[1]]$name, "test-module")

  # Should be able to call the tool
  result <- app$call_tool("test-module", list(choice = "b"))
  expect_equal(result$result, "Chose: b")
})

test_that("mcp_tool_module creates stub when no handler provided", {
  skip_if_not_installed("shiny")
  mod_ui <- function(id) {
    ns <- shiny::NS(id)
    htmltools::tagList(
      shiny::selectInput(ns("x"), "X:", c("a", "b")),
      shiny::textOutput(ns("out"))
    )
  }
  mod_server <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      output$out <- shiny::renderText(input$x)
    })
  }

  app <- mcp_tool_module(
    mod_ui,
    mod_server,
    name = "stub-module",
    description = "Module with stub handler"
  )

  expect_s3_class(app, "McpApp")
  # Tool should exist but handler is a stub
  tool_defs <- app$tool_definitions()
  expect_equal(length(tool_defs), 1)
  expect_named(tool_defs[[1]]$inputSchema$properties, "x")

  result <- app$call_tool("stub-module", list(x = "a"))
  expect_true("out" %in% names(result))
})

test_that("mcp_tool_module validates inputs", {
  expect_error(
    mcp_tool_module("not a function", identity, name = "x", description = "x"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_tool_module(identity, "not a function", name = "x", description = "x"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_tool_module(identity, identity, name = "", description = "x"),
    class = "shinymcp_error_validation"
  )
})

test_that("mcp_tool_module annotates module UI for JS bridge", {
  skip_if_not_installed("shiny")
  mod_ui <- function(id) {
    ns <- shiny::NS(id)
    htmltools::tagList(
      shiny::selectInput(ns("dataset"), "Data:", c("mtcars", "iris")),
      shiny::plotOutput(ns("plot"))
    )
  }
  mod_server <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      output$plot <- shiny::renderPlot(plot(1))
    })
  }

  app <- mcp_tool_module(
    mod_ui,
    mod_server,
    name = "annotated-mod",
    description = "Test",
    handler = function(dataset = "mtcars") list(plot = "base64...")
  )

  # Check the HTML resource has MCP annotations

  html <- app$html_resource()
  expect_match(html, 'data-shinymcp-input="dataset"')
  expect_match(html, 'data-shinymcp-output="plot"')
})

test_that("mcp_tool_module annotates date inputs without inner ids", {
  skip_if_not_installed("shiny")
  mod_ui <- function(id) {
    ns <- shiny::NS(id)
    htmltools::tagList(
      shiny::dateInput(ns("when"), "When:"),
      shiny::textOutput(ns("result"))
    )
  }
  mod_server <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      output$result <- shiny::renderText(input$when)
    })
  }

  app <- mcp_tool_module(
    mod_ui,
    mod_server,
    name = "date-mod",
    description = "Test date annotation",
    handler = function(when = "2024-01-01") list(result = when)
  )

  html <- app$html_resource()
  expect_match(html, 'data-shinymcp-input="when"')
})

test_that("mcp_tool_module annotates direct action buttons", {
  skip_if_not_installed("shiny")
  mod_ui <- function(id) {
    ns <- shiny::NS(id)
    htmltools::tagList(
      shiny::actionButton(ns("go"), "Go"),
      shiny::textOutput(ns("result"))
    )
  }
  mod_server <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      output$result <- shiny::renderText(input$go)
    })
  }

  app <- mcp_tool_module(
    mod_ui,
    mod_server,
    name = "action-mod",
    description = "Test action button annotation",
    handler = function(go = 1) list(result = as.character(go))
  )

  html <- app$html_resource()
  expect_match(html, 'data-shinymcp-input="go"')
})

test_that("mcp_tool_module stores module metadata", {
  skip_if_not_installed("shiny")
  mod_ui <- function(id) {
    ns <- shiny::NS(id)
    shiny::textInput(ns("x"), "X:")
  }
  mod_server <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {})
  }

  app <- mcp_tool_module(
    mod_ui,
    mod_server,
    name = "meta-test",
    description = "Test",
    handler = function() list()
  )

  # Module metadata stored on tool for Round 2
  tools <- app$mcp_tools()
  expect_true(length(tools) > 0)
})
