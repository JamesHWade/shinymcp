# as_mcp_app() (R/as-mcp-app.R)

cars_ui <- function() {
  shiny::fluidPage(
    shiny::selectInput("cyl", "Cylinders", c("4", "6", "8")),
    shiny::textOutput("count")
  )
}

cars_server <- function(input, output, session) {
  output$count <- shiny::renderText(
    paste(sum(mtcars$cyl == as.numeric(input$cyl)), "cars")
  )
}

write_app_file <- function(dir, lines, file = "app.R") {
  writeLines(lines, file.path(dir, file))
  dir
}

# ---- Shiny app objects ----

test_that("a Shiny app becomes an McpApp that runs its server function", {
  skip_if_not_installed("shiny")
  app <- as_mcp_app(shiny::shinyApp(cars_ui(), cars_server), name = "cars")
  expect_s3_class(app, "McpApp")
  expect_identical(app$name, "cars")
  expect_identical(app$version, "0.1.0")
  expect_s3_class(app$runtime(), "ShinyRuntime")
  expect_named(app$tools(), c("cars", "cars_view"))

  res <- app$run_tool("cars", list(cyl = "6"))
  expect_identical(res$structuredContent$outputs$count, "7 cars")
})

test_that("the page is the app's own UI with the runtime bridge", {
  skip_if_not_installed("shiny")
  app <- as_mcp_app(shiny::shinyApp(cars_ui(), cars_server), name = "cars")
  html <- app$html_resource()
  expect_match(html, '<select id="cyl"', fixed = TRUE)
  expect_match(html, 'id="count"', fixed = TRUE)
  config <- jsonlite::fromJSON(
    regmatches(
      html,
      regexpr(
        '(?<=<script id="shinymcp-config" type="application/json">).*?(?=</script>)',
        html,
        perl = TRUE
      )
    ),
    simplifyVector = FALSE
  )
  expect_identical(config$mode, "shiny")
  expect_identical(
    config$runtime,
    list(viewTool = "cars_view", entryTool = "cars")
  )
})

test_that("an app from mcp_endpoint() gives back the MCP App it carries", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(
    shiny::shinyApp(cars_ui(), cars_server),
    name = "cars"
  )
  app <- as_mcp_app(endpoint, name = "ignored")
  expect_identical(app, endpoint$mcpServer$apps[[1]])
  expect_identical(app$name, "cars")
})

test_that("names, titles, descriptions and versions are passed through", {
  skip_if_not_installed("shiny")
  app <- as_mcp_app(
    shiny::shinyApp(cars_ui(), cars_server),
    name = "cars",
    title = "Car counter",
    description = "Count cars by cylinders.",
    version = "2.0.0"
  )
  expect_identical(app$title, "Car counter")
  expect_identical(app$description, "Count cars by cylinders.")
  expect_identical(app$version, "2.0.0")
  tools <- app$tools()
  expect_identical(tools$cars$title, "Car counter")
  expect_identical(tools$cars$description, "Count cars by cylinders.")
  expect_match(
    tools$cars_view$description,
    "Used by the Car counter app",
    fixed = TRUE
  )
})

test_that("the app is named 'shiny-app' by default", {
  skip_if_not_installed("shiny")
  app <- as_mcp_app(shiny::shinyApp(cars_ui(), cars_server))
  expect_identical(app$name, "shiny-app")
  expect_named(app$tools(), c("shiny-app", "shiny-app_view"))
})

test_that("tool names are sanitized versions of the app name unless given", {
  skip_if_not_installed("shiny")
  app <- as_mcp_app(
    shiny::shinyApp(cars_ui(), cars_server),
    name = "My Cars! (v2)"
  )
  expect_named(app$tools(), c("My_Cars_v2", "My_Cars_v2_view"))
  # The app keeps the name it was given.
  expect_identical(app$name, "My Cars! (v2)")

  named <- as_mcp_app(
    shiny::shinyApp(cars_ui(), cars_server),
    name = "cars",
    tool_name = "count_cars"
  )
  expect_named(named$tools(), c("count_cars", "count_cars_view"))
  expect_identical(named$runtime()$bridge_config()$entryTool, "count_cars")

  expect_identical(sanitize_name("a.b c"), "a_b_c")
  expect_identical(sanitize_name("__x__"), "x")
  expect_identical(sanitize_name("!!!"), "app")
  expect_identical(nchar(sanitize_name(strrep("a", 100))), 64L)
  expect_identical(sanitize_name("ok-name_1"), "ok-name_1")
})

test_that("the default description is written from the inputs and outputs", {
  skip_if_not_installed("shiny")
  app <- as_mcp_app(
    shiny::shinyApp(cars_ui(), cars_server),
    name = "cars",
    title = "Car counter"
  )
  description <- app$tools()$cars$description
  expect_identical(
    description,
    paste(
      "Show the interactive Car counter app in the conversation.",
      "Arguments set the app's inputs (cyl); omitted ones keep their defaults.",
      "The result reports what the app shows (count).",
      "The user can keep adjusting the app after it opens."
    )
  )
})

test_that("arguments in `...` reach mcp_app()", {
  skip_if_not_installed("shiny")
  app <- as_mcp_app(
    shiny::shinyApp(cars_ui(), cars_server),
    name = "cars",
    prefers_border = TRUE,
    csp = list(connect_domains = "https://example.org")
  )
  meta <- app$resource_meta()
  expect_true(meta$ui$prefersBorder)
  expect_identical(unclass(meta$ui$csp$connectDomains), "https://example.org")
})

test_that("images = FALSE keeps plots out of the model's result", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::plotOutput("plot"))
  server <- function(input, output, session) {
    output$plot <- shiny::renderPlot(plot(1:3))
  }
  app <- as_mcp_app(shiny::shinyApp(ui, server), name = "plots", images = FALSE)
  res <- app$run_tool("plots", list())
  expect_identical(
    vapply(res$content, function(block) block$type, character(1)),
    "text"
  )
})

test_that("extra tools sit next to the runtime's tools", {
  skip_if_not_installed("shiny")
  helper <- list(
    name = "cylinder_counts",
    description = "Count cars per cylinder.",
    fun = function() as.list(table(mtcars$cyl))
  )
  app <- as_mcp_app(
    shiny::shinyApp(cars_ui(), cars_server),
    name = "cars",
    tools = list(helper)
  )
  expect_s3_class(app$runtime(), "ShinyRuntime")
  expect_named(app$tools(), c("cars", "cars_view", "cylinder_counts"))
  expect_identical(app$call_tool("cylinder_counts")[["4"]], 11L)
})

# ---- Selective exposure (bindMcp()) ----

test_that("once anything is marked, only marked inputs and outputs reach the model", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("x", "X", c("a", "b")) |> bindMcp(),
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("shown") |> bindMcp(),
    shiny::textOutput("hidden")
  )
  server <- function(input, output, session) {
    output$shown <- shiny::renderText(paste("x is", input$x))
    output$hidden <- shiny::renderText(paste("n is", input$n))
  }
  app <- as_mcp_app(shiny::shinyApp(ui, server), name = "sel")
  expect_identical(app$runtime()$model_inputs, "x")
  expect_identical(app$runtime()$model_outputs, "shown")
  expect_named(app$tools()$sel$input_schema$properties, c("x", "view"))

  res <- app$run_tool("sel", list(x = "b", n = 5))
  expect_match(
    res$content[[1]]$text,
    "Ignored unknown arguments: n.",
    fixed = TRUE
  )
  expect_identical(res$structuredContent$outputs, list(shown = "x is b"))
  expect_identical(res$structuredContent$inputs, list(x = "b"))
  # The user still sees the whole app.
  expect_identical(
    res[["_meta"]][["shinymcp/view"]]$outputs$hidden$value,
    "n is 1"
  )
})

test_that("marking only an output exposes no inputs", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("x", "X", c("a", "b")),
    shiny::textOutput("shown") |> bindMcp()
  )
  app <- as_mcp_app(
    shiny::shinyApp(ui, function(input, output) NULL),
    name = "sel"
  )
  expect_length(app$runtime()$model_inputs, 0)
  expect_identical(app$runtime()$model_outputs, "shown")
})

test_that("selective = FALSE exposes every input the model can set", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("x", "X", c("a", "b")) |> bindMcp(),
    shiny::numericInput("n", "N", 1),
    shiny::passwordInput("pw", "Password"),
    shiny::actionButton("go", "Go"),
    shiny::textOutput("shown") |> bindMcp(),
    shiny::textOutput("hidden")
  )
  app <- as_mcp_app(
    shiny::shinyApp(ui, function(input, output) NULL),
    name = "all",
    selective = FALSE
  )
  expect_identical(app$runtime()$model_inputs, c("x", "n"))
  expect_identical(app$runtime()$model_outputs, c("shown", "hidden"))
})

test_that("selective = TRUE with nothing marked exposes nothing", {
  skip_if_not_installed("shiny")
  app <- as_mcp_app(
    shiny::shinyApp(cars_ui(), cars_server),
    name = "none",
    selective = TRUE
  )
  expect_length(app$runtime()$model_inputs, 0)
  expect_length(app$runtime()$model_outputs, 0)
  expect_named(app$tools()$none$input_schema$properties, "view")
})

test_that("passwords and files are never exposed; buttons only when marked", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::passwordInput("pw", "Password") |> bindMcp(),
    shiny::fileInput("upload", "Upload") |> bindMcp(),
    shiny::actionButton("go", "Go") |> bindMcp(),
    shiny::actionButton("reset", "Reset"),
    shiny::textInput("note", "Note") |> bindMcp()
  )
  app <- suppressWarnings(
    as_mcp_app(
      shiny::shinyApp(ui, function(input, output) NULL),
      name = "secure"
    )
  )
  expect_setequal(app$runtime()$model_inputs, c("go", "note"))

  unmarked <- suppressWarnings(as_mcp_app(
    shiny::shinyApp(ui, function(input, output) NULL),
    name = "secure",
    selective = FALSE
  ))
  # Without marks, buttons aren't pressed by the model either.
  expect_identical(unmarked$runtime()$model_inputs, "note")
})

test_that("marked radio buttons, checkbox groups and date inputs become arguments", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::radioButtons("size", "Size", c("s", "m", "l")) |> bindMcp(),
    shiny::checkboxGroupInput("extras", "Extras", c("a", "b")) |> bindMcp(),
    shiny::dateInput("when", "When", "2024-01-01") |> bindMcp(),
    shiny::dateRangeInput("span", "Span", "2024-01-01", "2024-01-31") |>
      bindMcp(),
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("summary") |> bindMcp()
  )
  server <- function(input, output, session) {
    output$summary <- shiny::renderText(paste(
      input$size,
      paste(input$extras, collapse = "+"),
      format(input$when),
      paste(format(input$span), collapse = "..")
    ))
  }
  app <- as_mcp_app(shiny::shinyApp(ui, server), name = "groups")
  expect_identical(
    app$runtime()$model_inputs,
    c("size", "extras", "when", "span")
  )
  props <- app$tools()$groups$input_schema$properties
  expect_identical(unclass(props$size$enum), c("s", "m", "l"))
  expect_identical(props$extras$type, "array")
  expect_identical(props$when$format, "date")
  expect_identical(props$span$type, "array")

  res <- app$run_tool(
    "groups",
    list(
      size = "l",
      extras = list("a", "b"),
      when = "2024-02-02",
      span = list("2024-03-01", "2024-03-05")
    )
  )
  expect_identical(
    res$structuredContent$outputs$summary,
    "l a+b 2024-02-02 2024-03-01..2024-03-05"
  )
})

test_that("custom elements can be marked with an explicit id and type", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    htmltools::div(id = "custom", class = "my-widget") |>
      bindMcp(id = "custom", type = "html")
  )
  app <- as_mcp_app(
    shiny::shinyApp(ui, function(input, output) NULL),
    name = "custom"
  )
  expect_identical(app$runtime()$model_outputs, "custom")
})

# ---- Finding the UI of a Shiny app ----

test_that("UI functions are called with a request", {
  skip_if_not_installed("shiny")
  seen <- NULL
  ui <- function(req) {
    seen <<- req
    shiny::fluidPage(
      shiny::selectInput("y", "Y", c("m", "n")),
      if (identical(req$HTTP_MCP_APP, "1")) shiny::textOutput("mcp_only")
    )
  }
  app <- as_mcp_app(
    shiny::shinyApp(ui, function(input, output) NULL),
    name = "requi"
  )
  expect_identical(names(app$runtime()$inputs), "y")
  expect_true("mcp_only" %in% names(app$runtime()$outputs))
  expect_identical(seen$PATH_INFO, "/")
  expect_identical(seen$REQUEST_METHOD, "GET")
})

test_that("UI functions without arguments are called too", {
  skip_if_not_installed("shiny")
  shiny_app <- shiny::shinyApp(cars_ui(), cars_server)
  shiny_app$ui <- function() shiny::fluidPage(shiny::textInput("t", "T"))
  app <- as_mcp_app(shiny_app, name = "noargs")
  expect_identical(names(app$runtime()$inputs), "t")
})

test_that("a UI function that fails gives a validation error", {
  skip_if_not_installed("shiny")
  ui <- function(req) stop("no database")
  expect_error(
    as_mcp_app(shiny::shinyApp(ui, function(input, output) NULL)),
    class = "shinymcp_error_validation"
  )
  expect_error(
    as_mcp_app(shiny::shinyApp(ui, function(input, output) NULL)),
    "no database"
  )
})

test_that("apps from shinyAppDir() give up their UI", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  dir <- withr::local_tempdir()
  write_app_file(
    dir,
    "shiny::fluidPage(shiny::textInput('name', 'Name', 'Ann'), shiny::textOutput('greet'))",
    "ui.R"
  )
  write_app_file(
    dir,
    "function(input, output, session) output$greet <- shiny::renderText(paste('Hi', input$name))",
    "server.R"
  )
  # Reading ui.R through shinyAppDir() attaches shiny, noisily.
  app <- suppressPackageStartupMessages(as_mcp_app(
    shiny::shinyAppDir(dir),
    name = "split"
  ))
  expect_identical(names(app$runtime()$inputs), "name")
  res <- suppressPackageStartupMessages(app$run_tool(
    "split",
    list(name = "Bo")
  ))
  expect_identical(res$structuredContent$outputs$greet, "Hi Bo")
})

test_that("the app's onStop runs when the runtime closes", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  before <- getwd()
  dir <- withr::local_tempdir()
  write_app_file(
    dir,
    "shiny::fluidPage(shiny::textInput('name', 'Name'))",
    "ui.R"
  )
  write_app_file(dir, "function(input, output, session) NULL", "server.R")
  app <- suppressPackageStartupMessages(as_mcp_app(
    shiny::shinyAppDir(dir),
    name = "dir_app"
  ))
  suppressPackageStartupMessages(app$run_tool("dir_app", list()))
  app$runtime()$close_all()
  expect_identical(getwd(), before)
})

test_that("an app whose UI can't be found gives a validation error", {
  skip_if_not_installed("shiny")
  shiny_app <- local({
    handler <- function(req) NULL
    structure(
      list(
        httpHandler = handler,
        serverFuncSource = function() function(input, output) NULL
      ),
      class = "shiny.appobj"
    )
  })
  expect_error(as_mcp_app(shiny_app), class = "shinymcp_error_validation")
  expect_error(as_mcp_app(shiny_app), "Couldn't find the UI", fixed = TRUE)
})

test_that("HTML string UIs are accepted", {
  skip_if_not_installed("shiny")
  ui <- extract_shiny_ui(list(ui = '<div id="x">hi</div>'))
  expect_s3_class(ui, "html")
})

# ---- Paths ----

test_that("a directory with app.R is sourced and named after the directory", {
  skip_if_not_installed("shiny")
  root <- withr::local_tempdir()
  dir <- file.path(root, "my cars app")
  dir.create(dir)
  write_app_file(
    dir,
    c(
      "source('helpers.R')",
      "ui <- shiny::fluidPage(shiny::selectInput('x', 'X', choices()), shiny::textOutput('out'))",
      "server <- function(input, output, session) output$out <- shiny::renderText(paste('x is', input$x))",
      "shiny::shinyApp(ui, server)"
    )
  )
  # Relative paths resolve inside the app directory.
  write_app_file(dir, "choices <- function() c('a', 'b')", "helpers.R")

  app <- as_mcp_app(dir)
  expect_identical(app$name, "my_cars_app")
  expect_named(app$tools(), c("my_cars_app", "my_cars_app_view"))
  res <- app$run_tool("my_cars_app", list(x = "b"))
  expect_identical(res$structuredContent$outputs$out, "x is b")

  named <- as_mcp_app(dir, name = "custom")
  expect_identical(named$name, "custom")
})

test_that("an app.R app loads its R/ folder and runs in its directory", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  before <- getwd()
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "R"))
  write_app_file(
    dir,
    c(
      "greeting_ui <- function() shiny::textInput('who', 'Who', 'world')",
      "greet <- function(who) paste(readLines('greeting.txt'), who)"
    ),
    "R/helpers.R"
  )
  writeLines("Hello,", file.path(dir, "greeting.txt"))
  write_app_file(
    dir,
    c(
      "ui <- shiny::fluidPage(greeting_ui(), shiny::textOutput('msg'))",
      "server <- function(input, output, session) output$msg <- shiny::renderText(greet(input$who))",
      "shiny::shinyApp(ui, server)"
    )
  )

  app <- suppressPackageStartupMessages(as_mcp_app(dir, name = "greeter"))
  res <- app$run_tool("greeter", list(who = "R"))
  expect_false(isTRUE(res$isError))
  expect_identical(res$structuredContent$outputs$msg, "Hello, R")
  expect_identical(getwd(), before)
})

test_that("shinyAppDir() on an app.R app runs its server function", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  dir <- withr::local_tempdir()
  write_app_file(
    dir,
    c(
      "ui <- shiny::fluidPage(shiny::textInput('who', 'Who', 'world'), shiny::textOutput('msg'))",
      "server <- function(input, output, session) output$msg <- shiny::renderText(paste('Hi', input$who))",
      "shiny::shinyApp(ui, server)"
    )
  )
  app <- suppressPackageStartupMessages(as_mcp_app(
    shiny::shinyAppDir(dir),
    name = "dir_app"
  ))
  res <- app$run_tool("dir_app", list(who = "Bo"))
  expect_false(isTRUE(res$isError))
  expect_identical(res$structuredContent$outputs$msg, "Hi Bo")
})

test_that("a path to the app.R file works too", {
  skip_if_not_installed("shiny")
  dir <- withr::local_tempdir()
  write_app_file(
    dir,
    "shiny::shinyApp(shiny::fluidPage(shiny::textInput('t', 'T')), function(input, output) NULL)"
  )
  app <- as_mcp_app(file.path(dir, "app.R"), name = "direct")
  expect_identical(app$name, "direct")
  expect_identical(names(app$runtime()$inputs), "t")
})

test_that("a directory with ui.R and server.R works", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  dir <- withr::local_tempdir()
  write_app_file(
    dir,
    "shiny::fluidPage(shiny::textInput('name', 'Name', 'Ann'), shiny::textOutput('greet'))",
    "ui.R"
  )
  write_app_file(
    dir,
    "function(input, output, session) output$greet <- shiny::renderText(paste('Hi', input$name))",
    "server.R"
  )
  app <- suppressPackageStartupMessages(as_mcp_app(dir, name = "split"))
  res <- suppressPackageStartupMessages(app$run_tool(
    "split",
    list(name = "Bo")
  ))
  expect_identical(res$structuredContent$outputs$greet, "Hi Bo")
})

test_that("an app.R that builds an McpApp returns it, without serving it", {
  dir <- withr::local_tempdir()
  write_app_file(
    dir,
    c(
      "app <- shinymcp::mcp_app(htmltools::div('hi'), name = 'from-file')",
      "serve(app)",
      "preview_app(app)"
    )
  )
  app <- as_mcp_app(dir)
  expect_s3_class(app, "McpApp")
  expect_identical(app$name, "from-file")
})

test_that("bad paths and broken app files give validation errors", {
  expect_error(
    as_mcp_app(file.path(tempdir(), "no-such-app")),
    class = "shinymcp_error_validation"
  )
  expect_error(as_mcp_app(c("a", "b")), class = "shinymcp_error_validation")

  empty <- withr::local_tempdir()
  expect_error(as_mcp_app(empty), "No .*app\\.R.* or .*server\\.R")

  broken <- withr::local_tempdir()
  write_app_file(broken, "stop('boom')")
  expect_error(as_mcp_app(broken), class = "shinymcp_error_validation")
  expect_error(as_mcp_app(broken), "boom")

  nothing <- withr::local_tempdir()
  write_app_file(nothing, "x <- 1")
  expect_error(as_mcp_app(nothing), "doesn't define an")
})

# ---- Other objects ----

test_that("an McpApp is returned unchanged", {
  app <- mcp_app(htmltools::div("hello"), name = "identity")
  expect_identical(as_mcp_app(app), app)
})

test_that("other objects are refused", {
  expect_error(as_mcp_app(42), class = "shinymcp_error_validation")
  expect_error(as_mcp_app(list(a = 1)), "Can't make an MCP App", fixed = TRUE)
})
