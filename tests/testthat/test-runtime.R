# The live Shiny runtime (R/runtime.R), driven through the two tools the
# protocol uses: the app tool (the model) and the view tool (the page).

# ---- Fixtures ----

# Text outputs only, so most tests stay fast.
cars_text_app <- function(...) {
  ui <- shiny::fluidPage(
    shiny::selectInput("xvar", "X", c("wt", "hp", "disp")),
    shiny::selectInput("yvar", "Y", c("mpg", "qsec")),
    shiny::numericInput("n", "Rows", 3, min = 1, max = 32),
    shiny::textOutput("summary"),
    shiny::textOutput("xonly")
  )
  server <- function(input, output, session) {
    output$summary <- shiny::renderText(
      paste("x:", input$xvar, "y:", input$yvar, "n:", input$n)
    )
    output$xonly <- shiny::renderText(paste("x is", input$xvar))
  }
  rt_app(ui, server, name = "cars", ...)
}

faithful_plot_app <- function(...) {
  ui <- shiny::fluidPage(
    shiny::numericInput("bins", "Bins", 10),
    shiny::plotOutput("hist", height = "300px"),
    shiny::textOutput("dims")
  )
  server <- function(input, output, session) {
    output$hist <- shiny::renderPlot(
      graphics::hist(datasets::faithful$eruptions, breaks = input$bins)
    )
    output$dims <- shiny::renderText(paste(
      session$clientData$output_hist_width,
      session$clientData$output_hist_height,
      session$clientData$pixelratio
    ))
  }
  rt_app(ui, server, name = "faithful", ...)
}

# ---- Opening a view (the app tool) ----

test_that("the app tool opens a view with the model's inputs and reports every output", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  res <- rt_open(app, list(xvar = "hp"))
  view <- rt_meta(res)

  expect_null(res$isError)
  expect_match(view$instance, "^view-[0-9a-f]+$")
  expect_identical(view$revision, 1L)
  expect_setequal(names(view$outputs), c("summary", "xonly"))
  expect_identical(
    view$outputs$summary,
    list(kind = "text", value = "x: hp y: mpg n: 3", dom = "summary")
  )
  # The page is told every input value the session started with.
  expect_mapequal(view$inputs, list(xvar = "hp", yvar = "mpg", n = 3))

  expect_identical(res$structuredContent$view, view$instance)
  expect_mapequal(
    res$structuredContent$inputs,
    list(xvar = "hp", yvar = "mpg", n = 3)
  )
  expect_mapequal(
    res$structuredContent$outputs,
    list(summary = "x: hp y: mpg n: 3", xonly = "x is hp")
  )

  text <- rt_text(res)
  expect_match(
    text,
    paste0(
      "The cars app is open in the conversation (view ",
      view$instance,
      ")."
    ),
    fixed = TRUE
  )
  expect_match(text, 'Inputs: xvar = "hp"; yvar = "mpg"; n = 3.', fixed = TRUE)
  expect_match(text, "summary: x: hp y: mpg n: 3", fixed = TRUE)
  expect_match(text, "xonly: x is hp", fixed = TRUE)
  # The model already has this result, so no separate model context.
  expect_null(view$modelContext)
  expect_identical(app$runtime()$instance_count(), 1L)
})

test_that("inputs the model leaves out start at their UI defaults", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  res <- rt_open(app)
  expect_mapequal(
    res$structuredContent$inputs,
    list(xvar = "wt", yvar = "mpg", n = 3)
  )
  expect_identical(rt_meta(res)$outputs$summary$value, "x: wt y: mpg n: 3")
})

test_that("every call without a view id opens a separate session", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  a <- rt_open(app, list(xvar = "hp"))
  b <- rt_open(app, list(xvar = "disp"))
  expect_false(identical(rt_meta(a)$instance, rt_meta(b)$instance))
  expect_identical(app$runtime()$instance_count(), 2L)
  expect_identical(
    rt_session_input(app, rt_meta(a)$instance, "xvar"),
    "hp"
  )
  expect_identical(
    rt_session_input(app, rt_meta(b)$instance, "xvar"),
    "disp"
  )
})

test_that("the model's values are checked against choices and types", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()

  bad_choice <- rt_open(app, list(xvar = "bogus"))
  expect_true(bad_choice$isError)
  expect_match(rt_text(bad_choice), "not a valid value for xvar", fixed = TRUE)

  bad_number <- rt_open(app, list(n = "lots"))
  expect_true(bad_number$isError)
  expect_match(rt_text(bad_number), "must be a number", fixed = TRUE)

  expect_error(
    app$call_tool("cars", list(xvar = "bogus")),
    class = "shinymcp_error_arguments"
  )
  # Refused calls don't leave sessions behind.
  expect_identical(app$runtime()$instance_count(), 0L)
})

test_that("the model reads argument errors without R's condition header", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  text <- rt_text(rt_open(app, list(xvar = "bogus")))
  expect_no_match(text, "<error/", fixed = TRUE)
  expect_no_match(text, "check_choices", fixed = TRUE)
  expect_match(text, '"bogus" is not a valid value for xvar', fixed = TRUE)
})

test_that("unknown arguments are ignored and reported to the model", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  res <- rt_open(app, list(xvar = "hp", colour = "red"))
  expect_null(res$isError)
  expect_match(rt_text(res), "Ignored unknown arguments: colour.", fixed = TRUE)
  expect_null(res$structuredContent$inputs$colour)
})

test_that("server functions without a session argument run", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::textInput("name", "Name", "Ada"),
    shiny::textOutput("hello")
  )
  server <- function(input, output) {
    output$hello <- shiny::renderText(paste("Hello,", input$name))
  }
  app <- rt_app(ui, server, name = "hello")
  res <- rt_open(app, list(name = "Grace"))
  expect_identical(rt_meta(res)$outputs$hello$value, "Hello, Grace")
})

test_that("onStart runs once, before the app's UI is built", {
  skip_if_not_installed("shiny")
  started <- 0
  ui <- shiny::fluidPage(shiny::textOutput("out"))
  server <- function(input, output, session) {
    output$out <- shiny::renderText("hi")
  }
  shiny_app <- shiny::shinyApp(
    ui,
    server,
    onStart = function() started <<- started + 1
  )
  app <- as_mcp_app(shiny_app, name = "start")
  expect_identical(started, 1)
  rt_open(app)
  rt_open(app)
  expect_identical(started, 1)
})

test_that("a UI built from what onStart defines can be converted", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  dir <- withr::local_tempdir()
  writeLines("species <- c('Adelie', 'Gentoo')", file.path(dir, "global.R"))
  writeLines(
    "shiny::fluidPage(shiny::selectInput('sp', 'Species', species), shiny::textOutput('o'))",
    file.path(dir, "ui.R")
  )
  writeLines(
    "function(input, output, session) output$o <- shiny::renderText(input$sp)",
    file.path(dir, "server.R")
  )
  before <- getwd()
  app <- suppressPackageStartupMessages(as_mcp_app(
    shiny::shinyAppDir(dir),
    name = "globals"
  ))
  # The process keeps its working directory between calls.
  expect_identical(getwd(), before)
  expect_identical(app$runtime()$inputs$sp$choices, c("Adelie", "Gentoo"))
  res <- rt_open(app, list(sp = "Gentoo"))
  expect_identical(res$structuredContent$outputs$o, "Gentoo")
  expect_identical(getwd(), before)
  app$close()
})

test_that("the server function runs in a shinyAppDir() app's directory", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  dir <- withr::local_tempdir()
  writeLines("from the app directory", file.path(dir, "note.txt"))
  writeLines("shiny::fluidPage(shiny::textOutput('o'))", file.path(dir, "ui.R"))
  writeLines(
    "function(input, output, session) output$o <- shiny::renderText(readLines('note.txt'))",
    file.path(dir, "server.R")
  )
  app <- suppressPackageStartupMessages(as_mcp_app(
    shiny::shinyAppDir(dir),
    name = "dir"
  ))
  res <- rt_open(app)
  expect_identical(res$structuredContent$outputs$o, "from the app directory")
  app$close()
})

test_that("onStop runs in a shinyAppDir() app's directory", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  dir <- withr::local_tempdir()
  writeLines("shiny::fluidPage(shiny::textOutput('o'))", file.path(dir, "ui.R"))
  writeLines(
    "function(input, output, session) output$o <- shiny::renderText('hi')",
    file.path(dir, "server.R")
  )
  shiny_app <- shiny::shinyAppDir(dir)
  stop_app <- shiny_app$onStop
  stopped_in <- NULL
  shiny_app$onStop <- function() {
    stopped_in <<- getwd()
    stop_app()
  }
  before <- getwd()
  app <- suppressPackageStartupMessages(as_mcp_app(shiny_app, name = "stop"))
  app$close()
  expect_identical(normalizePath(stopped_in), normalizePath(dir))
  expect_identical(getwd(), before)
})

test_that("mcp_request() inside the server function sees the request", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("who")
  )
  server <- function(input, output, session) {
    output$who <- shiny::renderText({
      input$n
      req <- mcp_request()
      paste(req$caller, req$user %||% "anonymous", session$user %||% "none")
    })
  }
  app <- rt_app(ui, server, name = "who")
  res <- rt_open(app, context = list(user = "ada"))
  expect_identical(rt_meta(res)$outputs$who$value, "model ada ada")
  upd <- rt_update(
    app,
    rt_meta(res),
    inputs = list(n = 2),
    changed = "n",
    context = list(user = "ada")
  )
  expect_identical(rt_meta(upd)$outputs$who$value, "app ada ada")
})

# ---- The tools the runtime adds ----

test_that("the runtime adds a model tool and an app-only view tool", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  tools <- app$tools()
  expect_named(tools, c("cars", "cars_view"))
  expect_null(tools$cars$visibility)
  expect_identical(tools$cars_view$visibility, "app")
  expect_identical(tools$cars$source, "runtime")
  expect_identical(
    tools$cars$annotations,
    list(readOnlyHint = FALSE, openWorldHint = FALSE)
  )

  props <- tools$cars$input_schema$properties
  expect_named(props, c("xvar", "yvar", "n", "view"))
  expect_identical(unclass(props$xvar$enum), c("wt", "hp", "disp"))
  expect_identical(props$view$type, "string")

  view_props <- tools$cars_view$input_schema$properties
  expect_setequal(
    names(view_props),
    c(
      "action",
      "instance",
      "inputs",
      "changed",
      "events",
      "kinds",
      "sizes",
      "pixelRatio",
      "revision",
      "host",
      "output",
      "body",
      "sync",
      "tick",
      "dependency",
      "all"
    )
  )
  expect_setequal(
    unclass(view_props$action$enum),
    c("update", "download", "data", "dependency", "close")
  )
  expect_match(tools$cars_view$description, "Not for the model", fixed = TRUE)

  # Only the model tool is listed for the model.
  model_tools <- app$tool_definitions(include_app_only = FALSE)
  expect_identical(vapply(model_tools, `[[`, character(1), "name"), "cars")
  # Its outputSchema covers the outputs the model is told about.
  expect_setequal(
    names(model_tools[[1]]$outputSchema$properties),
    c("summary", "xonly")
  )
})

test_that("the default description names the inputs and outputs", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  description <- app$tools()$cars$description
  expect_match(description, "Show the interactive cars app", fixed = TRUE)
  expect_match(description, "(xvar, yvar, n)", fixed = TRUE)
  expect_match(description, "(summary, xonly)", fixed = TRUE)

  runtime <- app$runtime()
  runtime$model_inputs <- character()
  runtime$model_outputs <- character()
  bare <- default_runtime_description(runtime)
  expect_no_match(bare, "Arguments set", fixed = TRUE)
  expect_no_match(bare, "The result reports", fixed = TRUE)
})

test_that("an input named `view` is an ordinary argument, not a view id", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("view", "View", c("table", "chart")),
    shiny::textOutput("showing")
  )
  server <- function(input, output, session) {
    output$showing <- shiny::renderText(paste("showing", input$view))
  }
  app <- rt_app(ui, server, name = "views")
  props <- app$tools()$views$input_schema$properties
  expect_identical(unclass(props$view$enum), c("table", "chart"))

  first <- rt_open(app, list(view = "chart"))
  expect_identical(rt_meta(first)$outputs$showing$value, "showing chart")
  second <- rt_open(app, list(view = "table"))
  expect_false(identical(rt_meta(first)$instance, rt_meta(second)$instance))
  expect_no_match(rt_text(second), "no longer running", fixed = TRUE)
})

test_that("bridge_config() names the app tool and the view tool", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  expect_identical(
    app$runtime()$bridge_config(),
    list(viewTool = "cars_view", entryTool = "cars")
  )
})

test_that("ShinyRuntime requires a server function", {
  expect_error(
    ShinyRuntime$new(server = "nope", ui = htmltools::div(), app_name = "x"),
    class = "shinymcp_error_validation"
  )
})

# ---- Steering an open view (`view` argument) ----

test_that("a view id continues that session and keeps inputs left out", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("xvar", "X", c("wt", "hp")),
    shiny::numericInput("n", "N", 3),
    shiny::textOutput("summary")
  )
  server <- function(input, output, session) {
    renders <- shiny::reactiveVal(0)
    shiny::observe({
      input$n
      shiny::isolate(renders(renders() + 1))
    })
    output$summary <- shiny::renderText(
      paste(input$xvar, input$n, "runs:", renders())
    )
  }
  app <- rt_app(ui, server, name = "steer")
  first <- rt_open(app, list(xvar = "hp"))
  id <- first$structuredContent$view

  second <- rt_open(app, list(view = id, n = 7))
  expect_identical(second$structuredContent$view, id)
  expect_identical(rt_meta(second)$instance, id)
  expect_identical(rt_meta(second)$revision, 2L)
  expect_mapequal(second$structuredContent$inputs, list(xvar = "hp", n = 7))
  # The same session: state kept outside inputs carries on.
  expect_identical(rt_meta(second)$outputs$summary$value, "hp 7 runs: 2")
  expect_match(
    rt_text(second),
    paste0("Updated the steer app (view ", id, ")."),
    fixed = TRUE
  )
  expect_identical(app$runtime()$instance_count(), 1L)
  # All outputs come back to the model, changed or not.
  expect_named(rt_meta(second)$outputs, "summary")
})

test_that("buttons the model marks as pressed increment their counters", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::numericInput("n", "N", 1) |> bindMcp(),
    shiny::actionButton("go", "Go") |> bindMcp(),
    shiny::textOutput("status") |> bindMcp()
  )
  server <- function(input, output, session) {
    presses <- shiny::reactiveVal(0)
    shiny::observeEvent(input$go, presses(presses() + 1))
    output$status <- shiny::renderText(paste(
      "n",
      input$n,
      "go",
      input$go,
      "presses",
      presses(),
      class(input$go)[[1]]
    ))
  }
  app <- rt_app(ui, server, name = "press")
  expect_identical(app$tools()$press$input_schema$properties$go$type, "boolean")

  first <- rt_open(app, list(n = 2, go = TRUE))
  id <- first$structuredContent$view
  expect_identical(
    rt_meta(first)$outputs$status$value,
    "n 2 go 1 presses 1 shinyActionButtonValue"
  )

  second <- rt_open(app, list(view = id, go = TRUE))
  expect_identical(
    rt_meta(second)$outputs$status$value,
    "n 2 go 2 presses 2 shinyActionButtonValue"
  )
  expect_identical(second$structuredContent$inputs$go, 2L)

  # false (or leaving it out) doesn't press.
  third <- rt_open(app, list(view = id, go = FALSE, n = 5))
  expect_identical(
    rt_meta(third)$outputs$status$value,
    "n 5 go 2 presses 2 shinyActionButtonValue"
  )
})

test_that("a lost view id starts a new view and says so", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  res <- rt_open(app, list(view = "view-gone", n = 9))
  expect_null(res$isError)
  expect_false(identical(res$structuredContent$view, "view-gone"))
  expect_match(
    rt_text(res),
    "View view-gone is no longer running, so this is a new view",
    fixed = TRUE
  )
  expect_match(rt_text(res), "The cars app is open", fixed = TRUE)
  # Inputs the model didn't set are back to their defaults.
  expect_mapequal(
    res$structuredContent$inputs,
    list(xvar = "wt", yvar = "mpg", n = 9)
  )
})

# ---- Page updates (the view tool) ----

test_that("the view tool applies changed inputs and returns only changed outputs", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  view <- rt_meta(rt_open(app, list(xvar = "hp")))

  res <- rt_update(
    app,
    view,
    inputs = list(xvar = "hp", yvar = "qsec", n = 3),
    changed = "yvar"
  )
  meta <- rt_meta(res)
  expect_identical(meta$instance, view$instance)
  expect_identical(meta$revision, 2L)
  expect_named(meta$outputs, "summary")
  expect_identical(meta$outputs$summary$value, "x: hp y: qsec n: 3")
  # The page's own value isn't echoed back to it.
  expect_null(meta$inputs)
  expect_null(meta$restarted)

  # The page's result has text but no structured content or images.
  expect_null(res$structuredContent)
  expect_identical(rt_content_types(res), "text")
  expect_match(rt_text(res), "^cars updated\\.")
  expect_match(rt_text(res), "summary: x: hp y: qsec n: 3", fixed = TRUE)
})

test_that("inputs the page didn't list as changed are left alone", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  view <- rt_meta(rt_open(app, list(xvar = "hp")))
  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(xvar = "disp", yvar = "qsec"),
    changed = "yvar"
  ))
  expect_identical(meta$outputs$summary$value, "x: hp y: qsec n: 3")
  expect_identical(rt_session_input(app, view$instance, "xvar"), "hp")
})

test_that("an update that changes nothing returns an empty outputs object", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  view <- rt_meta(rt_open(app))
  meta <- rt_meta(rt_update(app, view, inputs = list(n = 3), changed = "n"))
  expect_length(meta$outputs, 0)
  expect_identical(as.character(to_json(meta$outputs)), "{}")
  expect_identical(meta$revision, 2L)
  expect_null(meta$modelContext)
})

test_that("without `changed`, every input the page sent counts as changed", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  view <- rt_meta(rt_open(app))
  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(xvar = "disp", yvar = "mpg", n = 3)
  ))
  expect_setequal(names(meta$outputs), c("summary", "xonly"))
  expect_identical(meta$outputs$xonly$value, "x is disp")
})

test_that("a stale revision resyncs from all of the page's inputs", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  view <- rt_meta(rt_open(app))
  second <- rt_meta(rt_update(
    app,
    view,
    inputs = list(yvar = "qsec"),
    changed = "yvar"
  ))
  expect_identical(second$revision, 2L)

  # A page still showing revision 1 (reloaded, say) sends its state.
  stale <- rt_meta(rt_update(
    app,
    view,
    inputs = list(xvar = "disp", yvar = "mpg", n = 3),
    changed = "n",
    revision = 1L
  ))
  expect_setequal(names(stale$outputs), c("summary", "xonly"))
  expect_identical(stale$outputs$summary$value, "x: disp y: mpg n: 3")
  expect_identical(stale$revision, 3L)

  # Revisions arrive from JSON as doubles; a current one isn't stale.
  current <- rt_meta(rt_update(
    app,
    stale,
    inputs = list(n = 4),
    changed = "n",
    revision = as.numeric(stale$revision)
  ))
  expect_named(current$outputs, "summary")
})

test_that("`all = TRUE` returns every output", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  view <- rt_meta(rt_open(app))
  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(n = 3),
    changed = "n",
    all = TRUE
  ))
  expect_setequal(names(meta$outputs), c("summary", "xonly"))
})

test_that("a view whose session is gone restarts from the page's inputs", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  res <- rt_update(
    app,
    list(instance = "view-restart", revision = 7L),
    inputs = list(xvar = "disp", yvar = "qsec", n = 2),
    changed = "n"
  )
  meta <- rt_meta(res)
  expect_true(meta$restarted)
  expect_identical(meta$instance, "view-restart")
  expect_identical(meta$revision, 1L)
  expect_setequal(names(meta$outputs), c("summary", "xonly"))
  expect_identical(meta$outputs$summary$value, "x: disp y: qsec n: 2")
  # The page already shows these values.
  expect_null(meta$inputs)
  expect_identical(app$runtime()$instance_count(), 1L)

  # Later calls reach the restarted session by the same id.
  again <- rt_meta(rt_update(app, meta, inputs = list(n = 4), changed = "n"))
  expect_null(again$restarted)
  expect_identical(again$outputs$summary$value, "x: disp y: qsec n: 4")
})

test_that("a view call without an instance id opens a new view", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  res <- app$run_tool(
    "cars_view",
    list(action = "update", inputs = list(xvar = "hp")),
    context = list(caller = "app")
  )
  meta <- rt_meta(res)
  expect_match(meta$instance, "^view-")
  expect_null(meta$restarted)
  expect_identical(meta$outputs$xonly$value, "x is hp")
})

test_that("close ends the view's session", {
  skip_if_not_installed("shiny")
  ended <- 0
  ui <- shiny::fluidPage(shiny::textOutput("out"))
  server <- function(input, output, session) {
    session$onSessionEnded(function() ended <<- ended + 1)
    output$out <- shiny::renderText("hi")
  }
  app <- rt_app(ui, server, name = "closing")
  id <- rt_meta(rt_open(app))$instance
  res <- app$run_tool(
    "closing_view",
    list(action = "close", instance = id),
    context = list(caller = "app")
  )
  expect_identical(rt_text(res), "closed")
  expect_identical(app$runtime()$instance_count(), 0L)
  expect_identical(ended, 1)

  # Closing a view that's already gone is harmless.
  again <- app$run_tool(
    "closing_view",
    list(action = "close", instance = id),
    context = list(caller = "app")
  )
  expect_identical(rt_text(again), "closed")
  expect_identical(ended, 1)
})

test_that("page values arrive as the R types Shiny delivers", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::dateInput("when", "When", "2024-01-01"),
    shiny::dateRangeInput("span", "Span", "2024-01-01", "2024-01-31"),
    shiny::checkboxGroupInput("pick", "Pick", c("a", "b", "c")),
    shiny::sliderInput("range", "Range", min = 0, max = 10, value = c(2, 8)),
    shiny::actionButton("go", "Go"),
    shiny::checkboxInput("flag", "Flag"),
    shiny::textOutput("types")
  )
  server <- function(input, output, session) {
    output$types <- shiny::renderText(paste(
      class(input$when)[[1]],
      format(input$when),
      paste(format(input$span), collapse = ".."),
      paste(input$pick, collapse = "+"),
      paste(input$range, collapse = "-"),
      class(input$go)[[1]],
      input$go,
      input$flag
    ))
  }
  app <- rt_app(ui, server, name = "types")
  view <- rt_meta(rt_open(app))
  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(
      when = "2024-02-29",
      span = list("2024-03-01", "2024-03-15"),
      pick = list("a", "c"),
      range = list(9, 1),
      go = 3,
      flag = TRUE
    )
  ))
  expect_identical(
    meta$outputs$types$value,
    "Date 2024-02-29 2024-03-01..2024-03-15 a+c 1-9 shinyActionButtonValue 3 TRUE"
  )
})

test_that("inputs created by renderUI take their kind from the page", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::checkboxInput("more", "More", FALSE),
    shiny::uiOutput("extra_ui"),
    shiny::textOutput("summary")
  )
  server <- function(input, output, session) {
    output$extra_ui <- shiny::renderUI({
      if (isTRUE(input$more)) {
        shiny::tagList(
          shiny::sliderInput("extra", "Extra", min = 0, max = 10, value = 3),
          shiny::dateInput("when", "When", "2024-05-05"),
          shiny::actionButton("again", "Again"),
          shiny::textOutput("extra_out")
        )
      }
    })
    output$extra_out <- shiny::renderText(paste(
      "extra",
      input$extra,
      "when",
      format(input$when %||% "none"),
      "again",
      class(input$again)[[1]]
    ))
    output$summary <- shiny::renderText(paste("more", input$more))
  }
  app <- rt_app(ui, server, name = "dynamic")
  res <- rt_open(app, list(more = TRUE))
  view <- rt_meta(res)
  # The dynamic UI goes to the page as HTML; its inputs aren't known until
  # the page reports them.
  expect_identical(view$outputs$extra_ui$kind, "html")
  expect_match(view$outputs$extra_ui$value, 'id="extra"', fixed = TRUE)
  # Outputs defined in the server but only created by renderUI are collected.
  expect_identical(view$outputs$extra_out$dom, "extra_out")
  expect_identical(
    view$outputs$extra_out$value,
    "extra  when none again NULL"
  )
  expect_false("extra" %in% app$runtime()$model_inputs)

  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(extra = 7, when = "2024-06-01", again = 1),
    changed = c("extra", "when", "again"),
    kinds = list(
      extra = list(kind = "slider", dataType = "number"),
      when = list(kind = "date"),
      again = list(kind = "action")
    )
  ))
  expect_identical(
    meta$outputs$extra_out$value,
    "extra 7 when 2024-06-01 again shinyActionButtonValue"
  )
  expect_s3_class(rt_session_input(app, view$instance, "when"), "Date")
})

test_that("page input kinds may be plain strings", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::uiOutput("dyn"), shiny::textOutput("out"))
  server <- function(input, output, session) {
    output$dyn <- shiny::renderUI(shiny::dateInput("when", "When"))
    output$out <- shiny::renderText(class(input$when)[[1]])
  }
  app <- rt_app(ui, server, name = "kinds")
  view <- rt_meta(rt_open(app))
  res <- rt_update(
    app,
    view,
    inputs = list(when = "2024-06-01"),
    changed = "when",
    kinds = list(when = "date")
  )
  expect_null(res$isError)
  expect_identical(rt_meta(res)$outputs$out$value, "Date")
})

# ---- Values the server sets (update*Input()) ----

test_that("updateSelectInput() values reach the session and the page", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("cyl", "Cylinders", c("4", "6", "8")),
    shiny::selectInput("model", "Model", "none"),
    shiny::textOutput("picked")
  )
  server <- function(input, output, session) {
    shiny::observe({
      models <- rownames(mtcars)[mtcars$cyl == as.numeric(input$cyl)]
      shiny::updateSelectInput(
        session,
        "model",
        choices = models,
        selected = models[[2]]
      )
    })
    output$picked <- shiny::renderText(paste("Model:", input$model))
  }
  app <- rt_app(ui, server, name = "models")
  six <- rownames(mtcars)[mtcars$cyl == 6]
  four <- rownames(mtcars)[mtcars$cyl == 4]

  res <- rt_open(app, list(cyl = "6"))
  view <- rt_meta(res)
  # The session sees the new value in the same call, as it would after the
  # browser applied the update.
  expect_identical(view$outputs$picked$value, paste("Model:", six[[2]]))
  expect_identical(res$structuredContent$inputs$model, six[[2]])
  expect_length(view$inputMessages, 1)
  expect_identical(view$inputMessages[[1]]$id, "model")
  expect_identical(view$inputMessages[[1]]$message$value, six[[2]])
  expect_match(
    as.character(view$inputMessages[[1]]$message$options),
    six[[1]],
    fixed = TRUE
  )

  upd <- rt_meta(rt_update(
    app,
    view,
    inputs = list(cyl = "4", model = six[[2]]),
    changed = "cyl"
  ))
  # Only the value the server changed goes back to the page.
  expect_identical(upd$inputs, list(model = four[[2]]))
  expect_identical(upd$outputs$picked$value, paste("Model:", four[[2]]))
  expect_length(upd$inputMessages, 1)
})

test_that("new choices without a selection keep a valid value, else take the first", {
  # updateRadioButtons() itself selects the first new choice, as in Shiny.
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::numericInput("version", "Version", 0),
    shiny::selectInput("pick", "Pick", c("a", "b")),
    shiny::radioButtons("radio", "Radio", c("x", "y")),
    shiny::textOutput("out")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$version, {
      if (input$version == 1) {
        shiny::updateSelectInput(session, "pick", choices = c("z", "a"))
        shiny::updateRadioButtons(session, "radio", choices = c("w", "x"))
      }
      if (input$version == 2) {
        shiny::updateSelectInput(session, "pick", choices = c("q", "r"))
      }
    })
    output$out <- shiny::renderText(paste(input$pick, input$radio))
  }
  app <- rt_app(ui, server, name = "choices")
  view <- rt_meta(rt_open(app))
  v1 <- rt_meta(rt_update(
    app,
    view,
    inputs = list(version = 1),
    changed = "version"
  ))
  expect_identical(rt_session_input(app, view$instance, "pick"), "a")
  expect_identical(rt_session_input(app, view$instance, "radio"), "w")
  expect_identical(v1$inputs, list(radio = "w"))
  v2 <- rt_meta(rt_update(
    app,
    v1,
    inputs = list(version = 2),
    changed = "version"
  ))
  expect_identical(rt_session_input(app, view$instance, "pick"), "q")
  expect_identical(v2$outputs$out$value, "q w")
  expect_identical(v2$inputs, list(pick = "q"))
})

test_that("other update*Input() calls are applied the way the browser would", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::numericInput("step", "Step", 0),
    shiny::dateInput("d", "D", "2024-01-01"),
    shiny::sliderInput("rng", "Rng", min = 0, max = 10, value = c(2, 7)),
    shiny::checkboxGroupInput("cg", "CG", c("a", "b", "c"), selected = "a"),
    shiny::radioButtons("rb", "RB", c("x", "y", "z")),
    shiny::textInput("t", "T", "orig"),
    shiny::checkboxInput("cb", "CB", FALSE),
    shiny::selectInput("sm", "SM", c("p", "q", "r"), multiple = TRUE),
    shiny::numericInput("num", "Num", 1),
    shiny::textOutput("o")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$step, {
      if (input$step == 1) {
        shiny::updateDateInput(session, "d", value = "2024-05-05")
        shiny::updateSliderInput(session, "rng", value = c(3, 9))
        shiny::updateCheckboxGroupInput(
          session,
          "cg",
          choices = c("a", "b", "c", "d"),
          selected = c("b", "d")
        )
        shiny::updateRadioButtons(session, "rb", selected = "z")
        shiny::updateTextInput(session, "t", value = "changed")
        shiny::updateCheckboxInput(session, "cb", value = TRUE)
        shiny::updateSelectInput(session, "sm", selected = c("q", "r"))
        shiny::updateNumericInput(session, "num", value = 42)
      }
    })
    output$o <- shiny::renderText(paste(
      format(input$d),
      paste(input$rng, collapse = "-"),
      paste(input$cg, collapse = "+"),
      input$rb,
      input$t,
      input$cb,
      paste(input$sm, collapse = "+"),
      input$num
    ))
  }
  app <- rt_app(ui, server, name = "updates")
  res <- rt_open(app, list(step = 1))
  view <- rt_meta(res)
  expect_identical(
    view$outputs$o$value,
    "2024-05-05 3-9 b+d z changed TRUE q+r 42"
  )
  expect_length(view$inputMessages, 8)
  id <- view$instance
  expect_s3_class(rt_session_input(app, id, "d"), "Date")
  expect_identical(rt_session_input(app, id, "rng"), c(3, 9))
  expect_identical(rt_session_input(app, id, "num"), 42)
  expect_identical(res$structuredContent$inputs$d, "2024-05-05")
  expect_identical(unclass(res$structuredContent$inputs$cg), c("b", "d"))
  expect_match(rt_text(res), "cg = b, d; rb = \"z\"", fixed = TRUE)
})

test_that("updates that clear a multi-value input clear it in the session", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::numericInput("step", "Step", 0),
    shiny::checkboxGroupInput("cg", "CG", c("a", "b"), selected = "a"),
    shiny::selectInput(
      "sm",
      "SM",
      c("p", "q"),
      selected = "p",
      multiple = TRUE
    ),
    shiny::checkboxGroupInput(
      "new",
      "New",
      c("x", "y"),
      selected = c("x", "y")
    ),
    shiny::textOutput("o")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$step, {
      if (input$step == 1) {
        shiny::updateCheckboxGroupInput(session, "cg", selected = character(0))
        shiny::updateSelectInput(session, "sm", selected = character(0))
        # New choices without a selection leave nothing selected, even a
        # value that is among them, as in the browser.
        shiny::updateCheckboxGroupInput(session, "new", choices = c("y", "z"))
      }
    })
    output$o <- shiny::renderText(paste(
      length(input$cg),
      length(input$sm),
      length(input$new)
    ))
  }
  app <- rt_app(ui, server, name = "cleared")
  view <- rt_meta(rt_open(app, list(step = 1)))
  expect_identical(view$outputs$o$value, "0 0 0")
  for (id in c("cg", "sm", "new")) {
    expect_null(rt_session_input(app, view$instance, id))
  }
})

test_that("input update loops are cut off instead of hanging", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("out")
  )
  server <- function(input, output, session) {
    # Every value sets the next one, forever.
    shiny::observe(shiny::updateNumericInput(session, "n", value = input$n + 1))
    output$out <- shiny::renderText(input$n)
  }
  app <- rt_app(ui, server, name = "loop")
  res <- rt_open(app)
  expect_null(res$isError)
  n <- rt_session_input(app, rt_meta(res)$instance, "n")
  expect_gt(n, 1)
  expect_lt(n, 10)
  expect_identical(rt_meta(res)$outputs$out$value, as.character(n))
  # The update the session didn't apply is still sent to the page.
  messages <- rt_meta(res)$inputMessages
  expect_identical(
    as.numeric(messages[[length(messages)]]$message$value),
    n + 1
  )
})

test_that("updateDateRangeInput() with only an end date keeps the start", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::numericInput("step", "Step", 0),
    shiny::dateRangeInput("span", "Span", "2024-01-01", "2024-01-31"),
    shiny::textOutput("o")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$step, {
      if (input$step == 1) {
        shiny::updateDateRangeInput(session, "span", end = "2024-03-01")
      }
    })
    output$o <- shiny::renderText(paste(format(input$span), collapse = " / "))
  }
  app <- rt_app(ui, server, name = "span")
  res <- rt_open(app, list(step = 1))
  expect_identical(rt_meta(res)$outputs$o$value, "2024-01-01 / 2024-03-01")
})

test_that("updateSliderInput() bounds apply to the session's value", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::checkboxInput("wide", "Wide", FALSE),
    shiny::sliderInput("level", "Level", min = 0, max = 100, value = 40),
    shiny::textOutput("o")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$wide, {
      if (isTRUE(input$wide)) {
        shiny::updateSliderInput(session, "level", max = 200, value = 150)
      }
    })
    output$o <- shiny::renderText(paste("level", input$level))
  }
  app <- rt_app(ui, server, name = "bounds")
  view <- rt_meta(rt_open(app, list(wide = TRUE)))
  expect_identical(view$outputs$o$value, "level 150")
  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(level = 180),
    changed = "level"
  ))
  expect_identical(meta$outputs$o$value, "level 180")
})

test_that("module input updates go to the namespaced input", {
  skip_if_not_installed("shiny")
  picker_ui <- function(id) {
    ns <- shiny::NS(id)
    htmltools::tagList(
      shiny::selectInput(ns("cyl"), "Cylinders", c("4", "6", "8")),
      shiny::selectInput(ns("car"), "Car", "none"),
      shiny::textOutput(ns("picked"))
    )
  }
  picker_server <- function(id) {
    shiny::moduleServer(id, function(input, output, session) {
      shiny::observe({
        cars <- rownames(mtcars)[mtcars$cyl == as.numeric(input$cyl)]
        shiny::updateSelectInput(
          session,
          "car",
          choices = cars,
          selected = cars[[1]]
        )
      })
      output$picked <- shiny::renderText(paste("Car:", input$car))
    })
  }
  ui <- shiny::fluidPage(picker_ui("left"))
  server <- function(input, output, session) picker_server("left")
  app <- rt_app(ui, server, name = "modules")
  expect_setequal(app$runtime()$model_inputs, c("left-cyl", "left-car"))

  res <- rt_open(app, list(`left-cyl` = "8"))
  view <- rt_meta(res)
  eight <- rownames(mtcars)[mtcars$cyl == 8]
  expect_identical(view$inputMessages[[1]]$id, "left-car")
  expect_identical(rt_session_input(app, view$instance, "left-car"), eight[[1]])
  expect_null(rt_session_input(app, view$instance, "car"))
  # Outputs are reported by their full ids, as in the page.
  expect_identical(
    view$outputs[["left-picked"]]$value,
    paste("Car:", eight[[1]])
  )
  expect_identical(view$outputs[["left-picked"]]$dom, "left-picked")
})

# ---- Messages from the server to the page ----

test_that("notifications, modals, UI changes and custom messages reach the page once", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::actionButton("go", "Go"),
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("out")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$go, {
      shiny::showNotification("Saved it", type = "warning")
      shiny::showModal(shiny::modalDialog("Are you sure?", title = "Check"))
      shiny::insertUI("#out", "afterEnd", shiny::tags$p("inserted"))
      shiny::removeUI("#gone", multiple = TRUE)
      session$sendCustomMessage("highlight", list(row = 3))
      mcp_send_message("Look at row 3")
    })
    output$out <- shiny::renderText(paste("n", input$n))
  }
  app <- rt_app(ui, server, name = "messages")
  view <- rt_meta(rt_open(app))
  expect_null(view$notifications)
  expect_null(view$modals)

  meta <- rt_meta(rt_update(app, view, inputs = list(go = 1), changed = "go"))

  expect_length(meta$notifications, 1)
  expect_identical(meta$notifications[[1]]$type, "show")
  expect_type(meta$notifications[[1]]$message$html, "character")
  expect_match(meta$notifications[[1]]$message$html, "Saved it", fixed = TRUE)
  expect_identical(meta$notifications[[1]]$message$type, "warning")

  expect_length(meta$modals, 1)
  expect_identical(meta$modals[[1]]$type, "show")
  expect_match(meta$modals[[1]]$message$html, "Are you sure?", fixed = TRUE)

  expect_length(meta$uiChanges, 2)
  insert <- meta$uiChanges[[1]]
  expect_identical(insert$op, "insert")
  expect_identical(insert$selector, "#out")
  expect_identical(insert$where, "afterEnd")
  expect_false(insert$multiple)
  expect_match(insert$content$html, "<p>inserted</p>", fixed = TRUE)
  expect_identical(
    meta$uiChanges[[2]],
    list(op = "remove", selector = "#gone", multiple = TRUE)
  )

  expect_identical(
    meta$customMessages,
    list(list(type = "highlight", message = list(row = 3)))
  )
  expect_identical(meta$messages, list("Look at row 3"))

  # Each message is sent once.
  after <- rt_meta(rt_update(app, meta, inputs = list(n = 2), changed = "n"))
  expect_null(after$notifications)
  expect_null(after$modals)
  expect_null(after$uiChanges)
  expect_null(after$customMessages)
  expect_null(after$messages)
})

test_that("removing notifications and modals is relayed", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::numericInput("n", "N", 0))
  server <- function(input, output, session) {
    shiny::observeEvent(input$n, {
      if (input$n == 1) {
        shiny::removeNotification("note-1")
        shiny::removeModal()
      }
    })
  }
  app <- rt_app(ui, server, name = "removals")
  view <- rt_meta(rt_open(app))
  meta <- rt_meta(rt_update(app, view, inputs = list(n = 1), changed = "n"))
  expect_identical(
    meta$notifications,
    list(list(type = "remove", message = "note-1"))
  )
  expect_identical(meta$modals[[1]]$type, "remove")
})

test_that("hideTab() and showTab() reach the page", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::checkboxInput("hide", "Hide", FALSE),
    shiny::tabsetPanel(
      id = "tabs",
      shiny::tabPanel("A", "a"),
      shiny::tabPanel("B", "b")
    )
  )
  server <- function(input, output, session) {
    shiny::observeEvent(
      input$hide,
      if (isTRUE(input$hide)) {
        shiny::hideTab("tabs", "B")
      } else {
        shiny::showTab("tabs", "B")
      },
      ignoreInit = TRUE
    )
  }
  app <- rt_app(ui, server, name = "tabs")
  view <- rt_meta(rt_open(app))
  res <- rt_update(app, view, inputs = list(hide = TRUE), changed = "hide")
  expect_null(res$isError)
  change <- rt_meta(res)$uiChanges[[1]]
  expect_identical(change$op, "tab-visibility")
  expect_identical(change$id, "tabs")
  expect_identical(change$target, "B")
  expect_identical(change$type, "hide")
})

test_that("insertTab() and removeTab() reach the page", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::actionButton("add", "Add"),
    shiny::actionButton("drop", "Drop"),
    shiny::tabsetPanel(id = "tabs", shiny::tabPanel("A", "a"))
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$add, {
      shiny::insertTab("tabs", shiny::tabPanel("B", "b"), target = "A")
    })
    shiny::observeEvent(input$drop, shiny::removeTab("tabs", "A"))
  }
  app <- rt_app(ui, server, name = "tab-edits")
  view <- rt_meta(rt_open(app))

  added <- rt_meta(rt_update(
    app,
    view,
    inputs = list(add = 1),
    changed = "add"
  ))
  insert <- added$uiChanges[[1]]
  expect_identical(insert$op, "insert-tab")
  expect_identical(insert$id, "tabs")
  expect_identical(insert$target, "A")
  expect_identical(insert$position, "after")
  expect_match(insert$li$html, "data-value=\"B\"", fixed = TRUE)
  expect_match(insert$div$html, "tab-tsid-id", fixed = TRUE)

  dropped <- rt_meta(rt_update(
    app,
    added,
    inputs = list(add = 1, drop = 1),
    changed = "drop"
  ))
  expect_identical(
    dropped$uiChanges[[1]],
    list(op = "remove-tab", id = "tabs", target = "A")
  )
})

test_that("dependencies of dynamic UI are inlined for the page", {
  skip_if_not_installed("shiny")
  dir <- withr::local_tempdir()
  writeLines("window.dynamicDepLoaded = true;", file.path(dir, "dynamic.js"))
  dep <- htmltools::htmlDependency(
    "dynamic-dep",
    "1.0.0",
    src = c(file = dir),
    script = "dynamic.js"
  )
  ui <- shiny::fluidPage(shiny::uiOutput("dyn"))
  server <- function(input, output, session) {
    output$dyn <- shiny::renderUI(htmltools::tagList(htmltools::div("hi"), dep))
  }
  app <- rt_app(ui, server, name = "deps")
  view <- rt_meta(rt_open(app))
  head <- view$outputs$dyn$deps[[1]]$head
  expect_match(head, "window.dynamicDepLoaded = true;", fixed = TRUE)
})

# ---- Outputs ----

test_that("render functions map to page payloads and model text", {
  skip_if_not_installed("shiny")
  png_path <- withr::local_tempfile(fileext = ".png")
  grDevices::png(png_path, width = 60, height = 40)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  grDevices::dev.off()

  ui <- shiny::fluidPage(
    shiny::textOutput("txt"),
    shiny::verbatimTextOutput("printed"),
    shiny::tableOutput("tbl"),
    shiny::uiOutput("html"),
    shiny::imageOutput("img")
  )
  server <- function(input, output, session) {
    output$txt <- shiny::renderText("plain & simple")
    output$printed <- shiny::renderPrint(summary(c(1, 2, 3)))
    output$tbl <- shiny::renderTable(data.frame(a = 1:2, b = c("x", "y")))
    output$html <- shiny::renderUI(shiny::tags$b("bold text"))
    output$img <- shiny::renderImage(
      list(src = png_path, contentType = "image/png", alt = "A tiny image"),
      deleteFile = FALSE
    )
  }
  app <- rt_app(ui, server, name = "renders")
  res <- rt_open(app)
  outputs <- rt_meta(res)$outputs

  expect_identical(outputs$txt$kind, "text")
  expect_identical(outputs$txt$value, "plain & simple")
  expect_identical(res$structuredContent$outputs$txt, "plain & simple")

  expect_identical(outputs$printed$kind, "text")
  expect_match(outputs$printed$value, "Median", fixed = TRUE)

  # Tables go to the page as HTML and to the model as Markdown.
  expect_identical(outputs$tbl$kind, "html")
  expect_match(outputs$tbl$value, "<table", fixed = TRUE)
  expect_match(res$structuredContent$outputs$tbl, "| a | b |", fixed = TRUE)

  expect_identical(outputs$html$kind, "html")
  expect_match(outputs$html$value, "<b>bold text</b>", fixed = TRUE)
  expect_identical(res$structuredContent$outputs$html, "bold text")

  expect_identical(outputs$img$kind, "image")
  expect_match(outputs$img$value$src, "^data:image/png;base64,")
  expect_identical(outputs$img$value$alt, "A tiny image")
  expect_identical(res$structuredContent$outputs$img, "A tiny image")
  # The model sees images as image blocks.
  expect_identical(rt_content_types(res), c("text", "image"))
  expect_identical(res$content[[2]]$mimeType, "image/png")
})

test_that("req() clears an output and validate() shows its message", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::textInput("name", "Name", ""),
    shiny::numericInput("n", "N", -1),
    shiny::textOutput("greeting"),
    shiny::textOutput("checked"),
    shiny::textOutput("kept")
  )
  server <- function(input, output, session) {
    output$greeting <- shiny::renderText({
      shiny::req(input$name)
      paste("Hello,", input$name)
    })
    output$checked <- shiny::renderText({
      shiny::validate(shiny::need(input$n > 0, "N must be positive"))
      paste("n =", input$n)
    })
    output$kept <- shiny::renderText({
      shiny::req(input$n > 0, cancelOutput = TRUE)
      paste("kept", input$n)
    })
  }
  app <- rt_app(ui, server, name = "checks")
  res <- rt_open(app)
  outputs <- rt_meta(res)$outputs
  expect_identical(outputs$greeting, list(kind = "clear", dom = "greeting"))
  expect_identical(
    outputs$checked,
    list(
      kind = "error",
      value = "N must be positive",
      validation = TRUE,
      dom = "checked"
    )
  )
  expect_identical(outputs$kept$kind, "keep")
  expect_null(res$structuredContent$outputs$greeting)
  expect_identical(res$structuredContent$outputs$checked, "N must be positive")
  expect_match(rt_text(res), "checked: N must be positive", fixed = TRUE)
  expect_no_match(rt_text(res), "greeting:", fixed = TRUE)

  meta <- rt_meta(rt_update(
    app,
    rt_meta(res),
    inputs = list(name = "Ann", n = 2),
    changed = c("name", "n")
  ))
  expect_identical(meta$outputs$greeting$value, "Hello, Ann")
  expect_identical(meta$outputs$checked$value, "n = 2")
  expect_identical(meta$outputs$kept$value, "kept 2")
})

test_that("errors in outputs are reported, and sanitized when Shiny would", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::textOutput("boom"),
    shiny::textOutput("safe")
  )
  server <- function(input, output, session) {
    output$boom <- shiny::renderText(stop("disk on fire"))
    output$safe <- shiny::renderText(stop(shiny::safeError("bad input")))
  }
  app <- rt_app(ui, server, name = "errors")
  res <- rt_open(app)
  outputs <- rt_meta(res)$outputs
  expect_identical(outputs$boom$kind, "error")
  expect_identical(outputs$boom$value, "disk on fire")
  expect_identical(res$structuredContent$outputs$boom, "Error: disk on fire")
  expect_null(res$isError)

  withr::local_options(shiny.sanitize.errors = TRUE)
  sanitized <- rt_meta(rt_open(app))$outputs
  expect_match(sanitized$boom$value, "An error has occurred", fixed = TRUE)
  expect_identical(sanitized$safe$value, "bad input")
})

test_that("long output text is truncated for the model", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::textOutput("long"))
  server <- function(input, output, session) {
    output$long <- shiny::renderText(strrep("a", 50))
  }
  app <- rt_app(ui, server, name = "long")
  withr::local_options(shinymcp.max_text_chars = 10)
  res <- rt_open(app)
  expect_match(
    rt_text(res),
    "aaaaaaaaaa\n... [40 more characters]",
    fixed = TRUE
  )
  # The page still gets the whole value.
  expect_identical(nchar(rt_meta(res)$outputs$long$value), 50L)
})

test_that("runtime_output_entry() handles widgets and other values", {
  widget <- structure("{\"x\":1}", class = "json")
  entry <- runtime_output_entry(widget, list(type = "html"), "w")
  expect_identical(entry$payload$kind, "widget")
  expect_identical(entry$payload$value, "{\"x\":1}")
  expect_identical(entry$payload$dom, "w")
  expect_match(entry$model, "interactive widget", fixed = TRUE)

  html_string <- runtime_output_entry(
    "<p>Hi <b>there</b></p>",
    list(type = NULL),
    "h"
  )
  expect_identical(html_string$payload$kind, "html")
  expect_identical(html_string$text, "Hi there")

  plain <- runtime_output_entry("no tags here", list(type = NULL), "p")
  expect_identical(plain$payload$kind, "text")

  other <- runtime_output_entry(1:3, list(type = "text"), "o")
  expect_identical(other$payload$kind, "text")
  expect_match(other$text, "1 2 3", fixed = TRUE)

  cleared <- runtime_output_entry(NULL, list(type = "text"), "c")
  expect_identical(cleared$payload, list(kind = "clear", dom = "c"))
  expect_type(cleared$digest, "character")
})

test_that("collect_runtime_outputs() skips outputs the server never defined", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::textOutput("defined"),
    shiny::textOutput("undefined")
  )
  server <- function(input, output, session) {
    output$defined <- shiny::renderText("here")
  }
  app <- rt_app(ui, server, name = "partial")
  res <- rt_open(app)
  expect_named(rt_meta(res)$outputs, "defined")
  expect_named(res$structuredContent$outputs, "defined")
})

# ---- Plots, sizes and client data ----

test_that("plots are image payloads for the page and image blocks for the model", {
  skip_if_not_installed("shiny")
  app <- faithful_plot_app()
  res <- rt_open(app)
  hist <- rt_meta(res)$outputs$hist
  expect_identical(hist$kind, "image")
  expect_match(hist$value$src, "^data:image/png;base64,")
  # Width from the page default, height from plotOutput(height = "300px").
  expect_identical(hist$value$width, 640)
  expect_identical(hist$value$height, 300)
  expect_identical(hist$value$alt, "A plot (640 x 300).")
  expect_identical(res$structuredContent$outputs$hist, hist$value$alt)

  expect_identical(rt_content_types(res), c("text", "image"))
  expect_identical(res$content[[2]]$mimeType, "image/png")
  expect_gt(nchar(res$content[[2]]$data), 100)

  # No image blocks when the context turns them off.
  quiet <- rt_open(app, context = list(images = FALSE))
  expect_identical(rt_content_types(quiet), "text")
})

test_that("plots redraw when the page reports a new size or pixel ratio", {
  skip_if_not_installed("shiny")
  app <- faithful_plot_app()
  view <- rt_meta(rt_open(app))
  expect_identical(view$outputs$dims$value, "640 300 1")

  # A few pixels of jitter isn't worth a redraw.
  jitter <- rt_meta(rt_update(
    app,
    view,
    inputs = list(bins = 10),
    changed = "bins",
    sizes = list(hist = list(width = 645, height = 302))
  ))
  expect_length(jitter$outputs, 0)

  wider <- rt_meta(rt_update(
    app,
    jitter,
    inputs = list(bins = 10),
    changed = "bins",
    sizes = list(hist = list(width = 500, height = 300))
  ))
  expect_setequal(names(wider$outputs), c("hist", "dims"))
  expect_identical(wider$outputs$hist$value$width, 500)
  expect_identical(wider$outputs$dims$value, "500 300 1")

  sharper <- rt_meta(rt_update(
    app,
    wider,
    inputs = list(bins = 10),
    changed = "bins",
    pixelRatio = 2
  ))
  expect_setequal(names(sharper$outputs), c("hist", "dims"))
  expect_identical(sharper$outputs$dims$value, "500 300 2")

  # Tiny changes are ignored and ratios are kept within 1 to 3.
  same <- rt_meta(rt_update(
    app,
    sharper,
    inputs = list(bins = 10),
    changed = "bins",
    pixelRatio = 2.001
  ))
  expect_length(same$outputs, 0)
  capped <- rt_meta(rt_update(
    app,
    same,
    inputs = list(bins = 10),
    changed = "bins",
    pixelRatio = 10
  ))
  expect_identical(capped$outputs$dims$value, "500 300 3")

  # Sizes that aren't positive numbers are ignored.
  ignored <- rt_meta(rt_update(
    app,
    capped,
    inputs = list(bins = 10),
    changed = "bins",
    sizes = list(hist = list(width = -5, height = "tall"))
  ))
  expect_length(ignored$outputs, 0)
})

test_that("clientData reads sizes reactively and supplies defaults", {
  skip_if_not_installed("shiny")
  inst <- new.env(parent = emptyenv())
  inst$client <- shiny::reactiveValues(
    pixelratio = 2,
    output_plot_width = 800
  )
  client <- structure(list(), class = "shinymcp_clientdata", instance = inst)

  expect_identical(client$output_plot_width, 800)
  expect_identical(client[["output_plot_width"]], 800)
  expect_identical(client$pixelratio, 2)
  expect_false(client$output_plot_hidden)
  # Outputs the page hasn't measured get Shiny-like defaults.
  expect_identical(client$output_plot_height, 400)
  expect_identical(client$output_other_width, 640)
  expect_identical(client$url_hostname, "shinymcp")
  expect_identical(client$url_protocol, "https:")
  expect_identical(client$url_pathname, "/")
  expect_true(client$allowDataUriScheme)
  expect_null(client$something_else)

  # Reads inside a reactive context take a dependency.
  runs <- 0
  obs <- shiny::observe({
    client$output_plot_width
    runs <<- runs + 1
  })
  shiny:::flushReact()
  expect_identical(runs, 1)
  inst$client$output_plot_width <- 900
  shiny:::flushReact()
  expect_identical(runs, 2)
  obs$destroy()
})

test_that("pixel ratio and missing clientData values have defaults", {
  skip_if_not_installed("shiny")
  inst <- new.env(parent = emptyenv())
  inst$client <- shiny::reactiveValues()
  client <- structure(list(), class = "shinymcp_clientdata", instance = inst)
  expect_identical(client$pixelratio, 1)
  expect_identical(client$singletons, "")
  expect_identical(client$url_search, "")
})

# ---- Downloads ----

download_app <- function() {
  ui <- shiny::fluidPage(
    shiny::numericInput("rows", "Rows", 3),
    shiny::downloadButton("csv", "CSV"),
    shiny::downloadButton("notes", "Notes"),
    shiny::downloadButton("broken", "Broken"),
    shiny::textOutput("count")
  )
  server <- function(input, output, session) {
    output$csv <- shiny::downloadHandler(
      filename = function() paste0("faithful-", input$rows, ".csv"),
      content = function(file) {
        utils::write.csv(
          utils::head(datasets::faithful, input$rows),
          file,
          row.names = FALSE
        )
      }
    )
    output$notes <- shiny::downloadHandler(
      filename = "notes.dat",
      content = function(file) writeLines("some notes", file),
      contentType = "text/plain"
    )
    output$broken <- shiny::downloadHandler(
      filename = "broken.txt",
      content = function(file) stop("no data")
    )
    output$count <- shiny::renderText(paste(input$rows, "rows"))
  }
  rt_app(ui, server, name = "files")
}

test_that("downloads are page outputs but not model outputs", {
  skip_if_not_installed("shiny")
  app <- download_app()
  expect_false("csv" %in% app$runtime()$model_outputs)
  res <- rt_open(app)
  csv <- rt_meta(res)$outputs$csv
  expect_identical(csv$kind, "download")
  expect_identical(csv$value$filename, "faithful-3.csv")
  expect_null(res$structuredContent$outputs$csv)
  expect_no_match(rt_text(res), "csv:", fixed = TRUE)
})

test_that("the download action returns the file with the current inputs", {
  skip_if_not_installed("shiny")
  app <- download_app()
  view <- rt_meta(rt_open(app))
  res <- app$run_tool(
    "files_view",
    list(
      action = "download",
      instance = view$instance,
      output = "csv",
      inputs = list(rows = 2),
      changed = list("rows")
    ),
    context = list(caller = "app")
  )
  expect_null(res$isError)
  expect_identical(rt_text(res), "Prepared faithful-2.csv")
  download <- rt_meta(res)$download
  expect_identical(rt_meta(res)$instance, view$instance)
  expect_identical(download$output, "csv")
  expect_identical(download$filename, "faithful-2.csv")
  expect_identical(download$mimeType, "text/csv")
  body <- rawToChar(jsonlite::base64_dec(download$data))
  # write.csv() ends lines with CRLF on Windows.
  expect_identical(
    strsplit(body, "\r?\n")[[1]],
    c('"eruptions","waiting"', "3.6,79", "1.8,54")
  )

  notes <- rt_meta(app$run_tool(
    "files_view",
    list(action = "download", instance = view$instance, output = "notes"),
    context = list(caller = "app")
  ))$download
  expect_identical(notes$filename, "notes.dat")
  # The handler's content type wins over the file extension.
  expect_identical(notes$mimeType, "text/plain")
})

test_that("a download from a view whose session is gone starts a new one", {
  skip_if_not_installed("shiny")
  app <- download_app()
  res <- app$run_tool(
    "files_view",
    list(
      action = "download",
      instance = "view-lost",
      output = "csv",
      inputs = list(rows = 4)
    ),
    context = list(caller = "app")
  )
  expect_null(res$isError)
  expect_identical(rt_meta(res)$download$filename, "faithful-4.csv")
  expect_identical(app$runtime()$instance_count(), 1L)
  # With the new view's state, which the page shows from then on.
  meta <- rt_meta(res)
  expect_true(meta$restarted)
  expect_identical(meta$outputs$count$value, "4 rows")
  quiet <- rt_update(app, meta, changed = list())
  expect_length(rt_meta(quiet)$outputs, 0)

  # Even when the download fails.
  broken <- app$run_tool(
    "files_view",
    list(
      action = "download",
      instance = "view-lost-2",
      output = "broken",
      inputs = list(rows = 5)
    ),
    context = list(caller = "app")
  )
  expect_true(broken$isError)
  expect_identical(rt_meta(broken)$outputs$count$value, "5 rows")
  expect_null(rt_meta(broken)$download)
})

test_that("downloads that don't exist, fail, or are too big return errors", {
  skip_if_not_installed("shiny")
  app <- download_app()
  view <- rt_meta(rt_open(app))
  download <- function(output) {
    app$run_tool(
      "files_view",
      list(action = "download", instance = view$instance, output = output),
      context = list(caller = "app")
    )
  }

  missing <- download("nope")
  expect_true(missing$isError)
  expect_identical(rt_text(missing), "No download named 'nope'.")

  broken <- download("broken")
  expect_true(broken$isError)
  expect_match(rt_text(broken), "no data", fixed = TRUE)

  withr::local_options(shinymcp.max_download_bytes = 5)
  big <- download("csv")
  expect_true(big$isError)
  expect_match(rt_text(big), "over the 5 bytes limit", fixed = TRUE)
})

# ---- Data kept in R (server-side widgets) ----

test_that("registerDataObj() data is served through the data action", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::textOutput("url"))
  server <- function(input, output, session) {
    url <- session$registerDataObj(
      "rows",
      datasets::faithful,
      function(data, req) {
        body <- rawToChar(req$rook.input$read())
        shiny::httpResponse(
          200,
          "application/json",
          jsonlite::toJSON(
            list(
              n = nrow(data),
              body = body,
              method = req$REQUEST_METHOD,
              path = req$PATH_INFO
            ),
            auto_unbox = TRUE
          )
        )
      }
    )
    output$url <- shiny::renderText(url)
  }
  app <- rt_app(ui, server, name = "data")
  view <- rt_meta(rt_open(app))
  # The URL has Shiny's form, which widgets look for.
  expect_match(
    view$outputs$url$value,
    "^session/view[0-9a-f]+/dataobj/rows\\?w=&nonce="
  )

  res <- app$run_tool(
    "data_view",
    list(
      action = "data",
      instance = view$instance,
      output = "rows",
      body = "start=0&length=5"
    ),
    context = list(caller = "app")
  )
  expect_null(res$isError)
  expect_identical(rt_text(res), "Data for rows.")
  expect_identical(rt_meta(res)$instance, view$instance)
  data <- jsonlite::fromJSON(rt_meta(res)$data)
  expect_identical(data$n, nrow(datasets::faithful))
  expect_identical(data$body, "start=0&length=5")
  expect_identical(data$method, "POST")
  expect_identical(data$path, "/dataobj/rows")

  missing <- app$run_tool(
    "data_view",
    list(action = "data", instance = view$instance, output = "nope"),
    context = list(caller = "app")
  )
  expect_true(missing$isError)
  expect_identical(rt_text(missing), "No data named 'nope' in this view.")

  # Data needs a live session: a lost view has none, and says so, so the
  # page asks again with its inputs; then the view is rebuilt from them.
  lost <- app$run_tool(
    "data_view",
    list(action = "data", instance = "view-lost", output = "rows"),
    context = list(caller = "app")
  )
  expect_true(lost$isError)
  expect_true(rt_meta(lost)$gone)
  again <- app$run_tool(
    "data_view",
    list(
      action = "data",
      instance = "view-lost",
      output = "rows",
      body = "start=0",
      inputs = setNames(list(), character()),
      kinds = setNames(list(), character())
    ),
    context = list(caller = "app")
  )
  expect_null(again$isError)
  expect_true(rt_meta(again)$restarted)
  expect_true(is_string(rt_meta(again)$instance))
  expect_true(is.numeric(rt_meta(again)$revision))
  expect_identical(
    jsonlite::fromJSON(rt_meta(again)$data)$n,
    nrow(datasets::faithful)
  )
  # The answer brings the new view's outputs, so an update that changes
  # nothing has none to send.
  expect_match(rt_meta(again)$outputs$url$value, "^session/")
  quiet <- rt_update(app, rt_meta(again), changed = list())
  expect_length(rt_meta(quiet)$outputs, 0)
})

test_that("a view rebuilt for a data request answers with its state", {
  skip_if_not_installed("shiny")
  starts <- 0
  ui <- shiny::fluidPage(
    shiny::textInput("note", "Note"),
    shiny::textOutput("session")
  )
  server <- function(input, output, session) {
    starts <<- starts + 1
    n <- starts
    shiny::updateTextInput(session, "note", placeholder = paste("start", n))
    shiny::showNotification(paste("session", n))
    session$registerDataObj("rows", n, function(data, req) {
      shiny::httpResponse(200, "application/json", data)
    })
    output$session <- shiny::renderText(paste("session", n))
  }
  app <- rt_app(ui, server, name = "data")
  old <- rt_meta(rt_open(app))
  expect_identical(old$outputs$session$value, "session 1")

  res <- app$run_tool(
    "data_view",
    list(
      action = "data",
      instance = "view-lost",
      output = "rows",
      inputs = list(note = "kept"),
      kinds = list(note = list(kind = "text"))
    ),
    context = list(caller = "app")
  )
  meta <- rt_meta(res)
  expect_identical(meta$data, "2")
  expect_true(meta$restarted)
  # What the new session shows, not what the old one did.
  expect_identical(meta$outputs$session$value, "session 2")
  expect_identical(meta$inputMessages[[1]]$message$placeholder, "start 2")
  expect_match(meta$notifications[[1]]$message$html, "session 2", fixed = TRUE)
  expect_identical(rt_session_input(app, meta$instance, "note"), "kept")

  # The new view is where the page's data requests go from now on.
  more <- app$run_tool(
    "data_view",
    list(action = "data", instance = meta$instance, output = "rows"),
    context = list(caller = "app")
  )
  expect_identical(rt_meta(more)$data, "2")
  expect_null(rt_meta(more)$restarted)
  expect_null(rt_meta(more)$outputs)
})

test_that("a rebuilt view's state comes back even without its data", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::textOutput("o"))
  server <- function(input, output, session) {
    output$o <- shiny::renderText("rebuilt")
  }
  app <- rt_app(ui, server, name = "data")
  res <- app$run_tool(
    "data_view",
    list(
      action = "data",
      instance = "view-lost",
      output = "nope",
      inputs = setNames(list(), character())
    ),
    context = list(caller = "app")
  )
  expect_true(res$isError)
  expect_identical(rt_text(res), "No data named 'nope' in this view.")
  expect_true(rt_meta(res)$restarted)
  expect_identical(rt_meta(res)$outputs$o$value, "rebuilt")
  expect_null(rt_meta(res)$data)
})

test_that("uploads a data request brings belong to the view it rebuilds", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::fileInput("upload", "Upload"))
  server <- function(input, output, session) {
    session$registerDataObj("rows", 1, function(data, req) {
      shiny::httpResponse(200, "application/json", "[]")
    })
  }
  app <- rt_app(ui, server, name = "data")
  csv <- "a,b\n1,2\n"
  res <- app$run_tool(
    "data_view",
    list(
      action = "data",
      instance = "view-lost",
      output = "rows",
      inputs = list(
        upload = list(list(
          name = "data.csv",
          size = nchar(csv),
          type = "text/csv",
          data = jsonlite::base64_enc(charToRaw(csv))
        ))
      ),
      kinds = list(upload = list(kind = "file"))
    ),
    context = list(caller = "app")
  )
  id <- rt_meta(res)$instance
  datapath <- rt_session_input(app, id, "upload")$datapath
  expect_true(file.exists(datapath))
  # No other view's update can take them.
  expect_length(rt_private(app)$uploads, 0)
  # Closing the view removes them.
  app$run_tool(
    "data_view",
    list(action = "close", instance = id),
    context = list(caller = "app")
  )
  expect_false(file.exists(datapath))
})

test_that("a view rebuilt for a data request renders its outputs first", {
  skip_if_not_installed("shiny")
  # As DT does, the data is registered when the output renders.
  ui <- shiny::fluidPage(shiny::textOutput("url"))
  server <- function(input, output, session) {
    output$url <- shiny::renderText({
      session$registerDataObj("rows", datasets::faithful, function(data, req) {
        shiny::httpResponse(200, "application/json", nrow(data))
      })
    })
  }
  app <- rt_app(ui, server, name = "data")
  res <- app$run_tool(
    "data_view",
    list(
      action = "data",
      instance = "view-lost",
      output = "rows",
      inputs = setNames(list(), character())
    ),
    context = list(caller = "app")
  )
  expect_null(res$isError)
  expect_identical(rt_meta(res)$data, "272")
})

test_that("a failing data filter returns an error result", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::textOutput("url"))
  server <- function(input, output, session) {
    session$registerDataObj("rows", 1:3, function(data, req) {
      stop("filter failed")
    })
  }
  app <- rt_app(ui, server, name = "data")
  view <- rt_meta(rt_open(app))
  res <- app$run_tool(
    "data_view",
    list(action = "data", instance = view$instance, output = "rows"),
    context = list(caller = "app")
  )
  expect_true(res$isError)
  expect_match(rt_text(res), "filter failed", fixed = TRUE)
})

dt_request_body <- function(n_columns, start = 0, length = 10) {
  columns <- unlist(lapply(seq_len(n_columns) - 1, function(i) {
    c(
      sprintf("columns[%d][data]=%d", i, i),
      sprintf("columns[%d][name]=", i),
      sprintf("columns[%d][searchable]=true", i),
      sprintf("columns[%d][orderable]=true", i),
      sprintf("columns[%d][search][value]=", i),
      sprintf("columns[%d][search][regex]=false", i)
    )
  }))
  fields <- c(
    "draw=1",
    columns,
    "order[0][column]=0",
    "order[0][dir]=asc",
    paste0("start=", start),
    paste0("length=", length),
    "search[value]=",
    "search[regex]=false",
    "search[caseInsensitive]=true",
    "escape=true"
  )
  pairs <- strsplit(fields, "=", fixed = TRUE)
  paste(
    vapply(
      pairs,
      function(kv) {
        paste0(
          utils::URLencode(kv[[1]], reserved = TRUE),
          "=",
          if (length(kv) > 1) utils::URLencode(kv[[2]], reserved = TRUE) else ""
        )
      },
      character(1)
    ),
    collapse = "&"
  )
}

test_that("a session that ends after an error is reported, and restarts", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("out")
  )
  server <- function(input, output, session) {
    shiny::observe(if (input$n > 5) stop("n is too big"))
    output$out <- shiny::renderText(paste("n is", input$n))
  }
  app <- rt_app(ui, server, name = "crash")

  # The model hears why the app it opened stopped.
  # Shiny prints the error and its stack trace, as a server would log them.
  res <- quiet_crash(rt_open(app, list(n = 9)))
  expect_true(res$isError)
  expect_identical(
    rt_text(res),
    "The crash app stopped after an error in its server function: n is too big."
  )
  expect_length(ls(rt_private(app)$instances), 0)

  # So does the page, and its next change starts a new session.
  view <- rt_meta(rt_open(app, list(n = 1)))
  res <- quiet_crash(rt_update(app, view, list(n = 9), changed = "n"))
  expect_true(res$isError)
  expect_match(rt_text(res), "n is too big", fixed = TRUE)
  res <- rt_update(app, view, list(n = 2), changed = "n")
  expect_null(res$isError)
  expect_true(rt_meta(res)$restarted)
  expect_identical(rt_meta(res)$outputs$out$value, "n is 2")
})

test_that("session errors respect shiny.sanitize.errors", {
  skip_if_not_installed("shiny")
  withr::local_options(shiny.sanitize.errors = TRUE)
  ui <- shiny::fluidPage(shiny::numericInput("n", "N", 9))
  server <- function(input, output, session) {
    shiny::observe(stop("secret detail"))
  }
  res <- quiet_crash(rt_open(rt_app(ui, server, name = "crash")))
  expect_true(res$isError)
  expect_no_match(rt_text(res), "secret", fixed = TRUE)
})

test_that("an input emptied on the page or by the model becomes NULL", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::checkboxGroupInput("g", "G", c("a", "b"), selected = "a"),
    shiny::textOutput("out")
  )
  server <- function(input, output, session) {
    output$out <- shiny::renderText(
      if (is.null(input$g)) "none" else paste(input$g, collapse = ",")
    )
  }
  app <- rt_app(ui, server, name = "cb")
  view <- rt_meta(rt_open(app))
  expect_identical(view$outputs$out$value, "a")

  res <- rt_update(app, view, list(g = list()), changed = "g")
  expect_identical(rt_meta(res)$outputs$out$value, "none")

  res <- rt_open(app, list(view = view$instance, g = list("b")))
  expect_identical(res$structuredContent$outputs$out, "b")
  res <- rt_open(app, list(view = view$instance, g = list()))
  expect_identical(res$structuredContent$outputs$out, "none")
})

test_that("an output made with reactive() works, and carries its value", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::checkboxInput("more", "More", FALSE),
    shiny::conditionalPanel("output.ready", shiny::p("ready"))
  )
  server <- function(input, output, session) {
    output$ready <- shiny::reactive(isTRUE(input$more))
    shiny::outputOptions(output, "ready", suspendWhenHidden = FALSE)
  }
  app <- rt_app(ui, server, name = "cond")
  view <- rt_meta(rt_open(app, list(more = TRUE)))
  # A conditionalPanel() on the page reads the raw value.
  expect_identical(view$outputs$ready$raw, TRUE)
  expect_null(view$outputs$ready$error)
  res <- rt_update(app, view, list(more = FALSE), changed = "more")
  expect_identical(rt_meta(res)$outputs$ready$raw, FALSE)
})

test_that("varSelectInput() values reach the server as symbols", {
  skip_if_not_installed("shiny")
  seen <- new.env()
  ui <- shiny::fluidPage(
    shiny::varSelectInput("var", "Variable", mtcars[1:4]),
    shiny::varSelectInput("vars", "Variables", mtcars[1:4], multiple = TRUE),
    shiny::textOutput("out")
  )
  server <- function(input, output, session) {
    output$out <- shiny::renderText({
      seen$var <- input$var
      seen$vars <- input$vars
      mean(mtcars[[input$var]])
    })
  }
  app <- rt_app(ui, server, name = "vars")
  schema <- app$tool_definitions()[[1]]$inputSchema$properties$var
  expect_identical(unclass(schema$enum), c("mpg", "cyl", "disp", "hp"))

  res <- rt_open(app)
  expect_identical(seen$var, quote(mpg))
  expect_identical(seen$vars, list())

  res <- rt_open(app, list(var = "hp", vars = list("mpg", "cyl")))
  expect_identical(seen$var, quote(hp))
  expect_identical(seen$vars, list(quote(mpg), quote(cyl)))
  # The model and the page get names back.
  expect_identical(res$structuredContent$inputs$var, "hp")
  expect_identical(unclass(res$structuredContent$inputs$vars), c("mpg", "cyl"))

  view <- rt_meta(res)
  rt_update(app, view, list(var = "disp"), changed = "var")
  expect_identical(seen$var, quote(disp))
})

test_that("plots carry their coordmap, for clicks and brushes", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::plotOutput("p", click = "pc", brush = "pb"))
  server <- function(input, output, session) {
    output$p <- shiny::renderPlot(plot(mtcars$wt, mtcars$mpg))
  }
  app <- rt_app(ui, server, name = "plot")
  coordmap <- rt_meta(rt_open(app))$outputs$p$value$coordmap
  expect_length(coordmap$panels, 1)
  expect_named(
    coordmap$panels[[1]]$domain,
    c("left", "right", "bottom", "top"),
    ignore.order = TRUE
  )
  expect_true(coordmap$dims$width > 0)

  # What the page sends on a click is what nearPoints() reads.
  view <- rt_meta(rt_open(app))
  panel <- coordmap$panels[[1]]
  click <- list(
    x = 3.2,
    y = 21,
    coords_css = list(x = 300, y = 200),
    coords_img = list(x = 300, y = 200),
    img_css_ratio = list(x = 1, y = 1),
    mapping = panel$mapping,
    domain = panel$domain,
    range = panel$range,
    log = list(x = NULL, y = NULL)
  )
  seen <- new.env()
  server <- function(input, output, session) {
    output$p <- shiny::renderPlot(plot(mtcars$wt, mtcars$mpg))
    shiny::observe({
      shiny::req(input$pc)
      seen$near <- shiny::nearPoints(
        mtcars,
        input$pc,
        xvar = "wt",
        yvar = "mpg",
        threshold = 1000,
        maxpoints = 1
      )
    })
  }
  app <- rt_app(ui, server, name = "plot")
  view <- rt_meta(rt_open(app))
  rt_update(
    app,
    view,
    list(pc = click),
    changed = "pc",
    kinds = list(pc = list(kind = "value")),
    events = list("pc")
  )
  expect_identical(nrow(seen$near), 1L)
})

test_that("a message's `values` isn't taken for a new `value`", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  session$setInputs(acc = "A")
  # bslib's accordion_panel_open() sends `values`; `$value` would match it.
  msg <- list(id = "acc", message = list(method = "open", values = list("B")))
  expect_null(implied_input_value(msg, NULL, session))
})

test_that("an ExtendedTask's result arrives on a later tick", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  skip_if_not_installed("promises")
  skip_if_not(
    exists("ExtendedTask", envir = asNamespace("shiny")),
    "shiny without ExtendedTask"
  )
  ui <- shiny::fluidPage(
    shiny::actionButton("go", "Go"),
    shiny::textOutput("result")
  )
  server <- function(input, output, session) {
    task <- shiny::ExtendedTask$new(function() {
      promises::promise(function(resolve, reject) {
        later::later(function() resolve("done"), 0.2)
      })
    })
    shiny::observeEvent(input$go, task$invoke())
    output$result <- shiny::renderText(task$result())
  }
  app <- rt_app(ui, server, name = "task")
  view <- rt_meta(rt_open(app))
  res <- rt_update(app, view, list(go = 1), changed = "go")
  meta <- rt_meta(res)
  # While the task runs, the output is busy and the page is asked back.
  expect_identical(meta$outputs$result$kind, "progress")
  expect_true(meta$nextTick <= 500)

  Sys.sleep(0.4)
  res <- rt_update(app, meta, tick = TRUE)
  expect_identical(rt_meta(res)$outputs$result$value, "done")
  expect_null(rt_meta(res)$nextTick)
})

test_that("a view answers while other callbacks are scheduled in the process", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  ui <- shiny::fluidPage(
    shiny::textInput("name", "Name", "a"),
    shiny::textOutput("out")
  )
  server <- function(input, output, session) {
    output$out <- shiny::renderText(paste("name:", input$name))
  }
  app <- rt_app(ui, server, name = "busy")
  # Something else that keeps a callback scheduled, as a Shiny app's timers
  # do, for three seconds.
  stopped <- FALSE
  stop_at <- Sys.time() + 3
  tick <- function() {
    if (!stopped && Sys.time() < stop_at) later::later(tick, 0.2)
  }
  later::later(tick, 0.2)
  withr::defer(stopped <- TRUE)

  start <- Sys.time()
  res <- rt_open(app, list(name = "b"))
  took <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  expect_identical(rt_meta(res)$outputs$out$value, "name: b")
  expect_lt(took, 2)
})

test_that("values set from JavaScript arrive as Shiny delivers them", {
  skip_if_not_installed("shiny")
  seen <- new.env()
  ui <- shiny::fluidPage(shiny::textOutput("out"))
  server <- function(input, output, session) {
    output$out <- shiny::renderText({
      seen$rows <- input$tbl_rows_selected
      seen$state <- input$tbl_state
      "ok"
    })
  }
  app <- rt_app(ui, server, name = "js")
  view <- rt_meta(rt_open(app))
  kinds <- list(
    tbl_rows_selected = list(kind = "value"),
    tbl_state = list(kind = "value")
  )
  # An empty array is NULL, as unlist() makes it in Shiny.
  rt_update(
    app,
    view,
    list(tbl_rows_selected = list(), tbl_state = list(start = 0)),
    changed = c("tbl_rows_selected", "tbl_state"),
    kinds = kinds
  )
  expect_null(seen$rows)
  expect_identical(seen$state, list(start = 0))
  rt_update(
    app,
    view,
    list(tbl_rows_selected = list(1L, 3L)),
    changed = "tbl_rows_selected",
    kinds = kinds
  )
  expect_identical(seen$rows, c(1L, 3L))
})

test_that("server-side selectize choices are searched through the view tool", {
  skip_if_not_installed("shiny")
  genes <- sprintf("GENE%04d", 1:3000)
  ui <- shiny::fluidPage(
    shiny::selectizeInput("gene", "Gene", choices = NULL),
    shiny::textOutput("chosen")
  )
  server <- function(input, output, session) {
    shiny::updateSelectizeInput(
      session,
      "gene",
      choices = genes,
      selected = "GENE0042",
      server = TRUE
    )
    output$chosen <- shiny::renderText(paste("gene:", input$gene))
  }
  app <- rt_app(ui, server, name = "genes")
  view <- rt_meta(rt_open(app))
  expect_identical(view$outputs$chosen$value, "gene: GENE0042")
  message <- view$inputMessages[[1]]$message
  expect_match(message$url, "/dataobj/gene?", fixed = TRUE)

  search <- function(query) {
    res <- app$run_tool(
      "genes_view",
      list(
        action = "data",
        instance = view$instance,
        output = "gene",
        body = paste0(
          "query=",
          query,
          "&field=%5B%22value%22%2C%22label%22%5D&value=value&conju=and&maxop=1000"
        )
      ),
      context = list(caller = "app")
    )
    jsonlite::fromJSON(rt_meta(res)$data)$value
  }
  expect_length(search(""), 1000)
  expect_identical(search("gene2999"), c("GENE0042", "GENE2999"))
})

test_that("server-side DT tables fetch their rows from the view's session", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("DT")
  ui <- shiny::fluidPage(
    shiny::numericInput("n", "N", 5),
    DT::DTOutput("tbl")
  )
  server <- function(input, output, session) {
    output$tbl <- DT::renderDT(
      utils::head(mtcars[, 1:3], input$n),
      server = TRUE
    )
  }
  app <- rt_app(ui, server, name = "dt")
  res <- rt_open(app)
  view <- rt_meta(res)
  tbl <- view$outputs$tbl
  expect_identical(tbl$kind, "widget")
  # The model reads the table's rows, as it would a tableOutput()'s.
  model_rows <- res$structuredContent$outputs$tbl
  expect_length(model_rows, 5)
  expect_identical(model_rows[[1]]$mpg, 21)
  expect_match(res$content[[1]]$text, "A table with 5 rows:", fixed = TRUE)
  expect_match(res$content[[1]]$text, "Mazda RX4", fixed = TRUE)
  widget <- jsonlite::fromJSON(tbl$value, simplifyVector = FALSE)
  expect_match(widget$x$options$ajax$url, "/dataobj/tbl?", fixed = TRUE)

  rows <- app$run_tool(
    "dt_view",
    list(
      action = "data",
      instance = view$instance,
      output = "tbl",
      body = dt_request_body(4, length = 2)
    ),
    context = list(caller = "app")
  )
  expect_null(rows$isError)
  data <- jsonlite::fromJSON(rt_meta(rows)$data)
  expect_identical(data$recordsTotal, 5L)
  expect_identical(nrow(data$data), 2L)
})

test_that("widget dependencies are inlined, and skipped when the page has them", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("DT")
  ui <- shiny::fluidPage(DT::DTOutput("tbl"))
  server <- function(input, output, session) {
    output$tbl <- DT::renderDT(utils::head(mtcars[, 1:3]), server = FALSE)
  }
  app <- rt_app(ui, server, name = "dt")
  tbl <- rt_meta(rt_open(app))$outputs$tbl
  names <- vapply(tbl$deps, function(d) d$name, character(1))
  expect_true("dt-core" %in% names)
  # The page was built with jQuery.
  expect_false("jquery" %in% names)
  heads <- vapply(tbl$deps, function(d) d$head, character(1))
  # Inlined, not links to paths only a Shiny server could serve.
  expect_false(any(grepl("<script src=", heads, fixed = TRUE)))
  expect_true(all(nchar(heads) > 100))

  skipped <- rt_meta(rt_open(
    app,
    context = list(skip_deps = "dt-core@0.0.1")
  ))$outputs$tbl
  expect_false(
    "dt-core" %in% vapply(skipped$deps, function(d) d$name, character(1))
  )
  expect_identical(skipped$value, tbl$value)

  # Which dependencies go with a widget doesn't make it a changed output.
  view <- rt_meta(rt_open(app))
  meta <- rt_meta(rt_update(
    app,
    view,
    context = list(skip_deps = "dt-core@0.0.1")
  ))
  expect_length(meta$outputs, 0)
})

test_that("widget_dependencies() maps Shiny's web paths back to local files", {
  skip_if_not_installed("shiny")
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "js"))
  writeLines("window.testWidgetDep = 1;", file.path(dir, "js", "dep.js"))
  shiny::addResourcePath("shinymcp-test-dep-1.0", dir)
  withr::defer(shiny::removeResourcePath("shinymcp-test-dep-1.0"))

  json <- structure(
    as.character(jsonlite::toJSON(
      list(
        x = list(a = 1),
        deps = list(
          list(
            name = "test-dep",
            version = "1.0",
            src = list(href = "shinymcp-test-dep-1.0/js"),
            script = "dep.js"
          ),
          list(
            name = "unknown-dep",
            version = "2.0",
            src = list(href = "not-registered-2.0"),
            script = "x.js"
          )
        )
      ),
      auto_unbox = TRUE
    )),
    class = "json"
  )
  deps <- widget_dependencies(json)
  expect_length(deps, 1)
  expect_identical(deps[[1]]$name, "test-dep")
  expect_identical(
    normalizePath(deps[[1]]$src$file),
    normalizePath(file.path(dir, "js"))
  )
  expect_match(
    dependency_payload(deps[[1]])$head,
    "window.testWidgetDep = 1;",
    fixed = TRUE
  )

  expect_length(widget_dependencies(structure("not json", class = "json")), 0)
  expect_length(widget_dependencies(structure('{"x":1}', class = "json")), 0)
})

# ---- Timers ----

test_that("a request runs the invalidateLater() timer that's due", {
  skip_if_not_installed("shiny")
  ticks <- 0
  ui <- shiny::fluidPage(
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("clock")
  )
  server <- function(input, output, session) {
    output$clock <- shiny::renderText({
      shiny::invalidateLater(500)
      ticks <<- ticks + 1
      paste("tick", ticks)
    })
  }
  app <- rt_app(ui, server, name = "timer")
  view <- rt_meta(rt_open(app))
  expect_identical(view$outputs$clock$value, "tick 1")

  # Pretend the last request was a second ago: the timer is due (twice
  # over, but a missed run isn't made up).
  inst <- rt_instance(app, view$instance)
  inst$clock <- inst$clock - 1
  meta <- rt_meta(rt_update(app, view, inputs = list(n = 1), changed = "n"))
  expect_identical(meta$outputs$clock$value, "tick 2")
})

# ---- Eviction and ownership ----

counting_app <- function(ended) {
  ui <- shiny::fluidPage(
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("out")
  )
  server <- function(input, output, session) {
    who <- session$user %||% "anonymous"
    session$onSessionEnded(function() ended$ids <- c(ended$ids, who))
    output$out <- shiny::renderText(paste(who, input$n))
  }
  rt_app(ui, server, name = "count")
}

test_that("max_instances evicts the least recently used view", {
  skip_if_not_installed("shiny")
  ended <- new.env()
  app <- counting_app(ended)
  runtime <- app$runtime()
  runtime$max_instances <- 2
  a <- rt_meta(rt_open(app, list(n = 1)))
  b <- rt_meta(rt_open(app, list(n = 2)))
  # Make b the least recently used.
  b_inst <- rt_instance(app, b$instance)
  b_inst$last_used <- rt_instance(app, a$instance)$last_used - 10
  c <- rt_meta(rt_open(app, list(n = 3)))

  expect_identical(runtime$instance_count(), 2L)
  expect_null(rt_instance(app, b$instance))
  expect_false(is.null(rt_instance(app, a$instance)))
  expect_false(is.null(rt_instance(app, c$instance)))
  # Evicted sessions are closed properly.
  expect_identical(ended$ids, "anonymous")

  # The evicted view's page can still carry on: a new session starts from
  # its inputs.
  restarted <- rt_meta(rt_update(app, b, inputs = list(n = 2), changed = "n"))
  expect_true(restarted$restarted)
  expect_identical(restarted$outputs$out$value, "anonymous 2")
})

test_that("idle views are closed after idle_seconds", {
  skip_if_not_installed("shiny")
  ended <- new.env()
  app <- counting_app(ended)
  runtime <- app$runtime()
  runtime$idle_seconds <- 60
  old <- rt_meta(rt_open(app))
  old_inst <- rt_instance(app, old$instance)
  old_inst$last_used <- as.numeric(Sys.time()) - 120
  fresh <- rt_meta(rt_open(app))

  expect_identical(runtime$instance_count(), 1L)
  expect_null(rt_instance(app, old$instance))
  expect_false(is.null(rt_instance(app, fresh$instance)))
  expect_length(ended$ids, 1)
})

test_that("options set the default view limits", {
  skip_if_not_installed("shiny")
  withr::local_options(shinymcp.max_views = NULL, shinymcp.view_timeout = NULL)
  default <- cars_text_app()$runtime()
  expect_identical(default$max_instances, 50L)
  expect_identical(default$idle_seconds, 3600)

  withr::local_options(shinymcp.max_views = 3L, shinymcp.view_timeout = 10)
  limited <- cars_text_app()$runtime()
  expect_identical(limited$max_instances, 3L)
  expect_identical(limited$idle_seconds, 10)
})

test_that("close_all() closes every session", {
  skip_if_not_installed("shiny")
  ended <- new.env()
  app <- counting_app(ended)
  rt_open(app)
  rt_open(app, context = list(user = "ada"))
  expect_identical(app$runtime()$instance_count(), 2L)
  app$runtime()$close_all()
  expect_identical(app$runtime()$instance_count(), 0L)
  expect_setequal(ended$ids, c("anonymous", "ada"))
})

test_that("a view belongs to the user who opened it", {
  skip_if_not_installed("shiny")
  ended <- new.env()
  app <- counting_app(ended)
  alice <- rt_open(app, list(n = 5), context = list(user = "alice"))
  id <- alice$structuredContent$view
  expect_identical(rt_meta(alice)$outputs$out$value, "alice 5")

  # Bob can't steer Alice's view: he gets a new one of his own.
  bob <- rt_open(app, list(view = id, n = 6), context = list(user = "bob"))
  expect_false(identical(bob$structuredContent$view, id))
  expect_match(
    rt_text(bob),
    paste("View", id, "is no longer running"),
    fixed = TRUE
  )
  expect_identical(rt_meta(bob)$outputs$out$value, "bob 6")

  # Alice's view is untouched.
  again <- rt_open(app, list(view = id, n = 7), context = list(user = "alice"))
  expect_identical(again$structuredContent$view, id)
  expect_match(rt_text(again), "Updated the count app", fixed = TRUE)
  expect_identical(rt_meta(again)$outputs$out$value, "alice 7")
})

test_that("another user's view call can't replace the owner's session", {
  skip_if_not_installed("shiny")
  ended <- new.env()
  app <- counting_app(ended)
  id <- rt_open(
    app,
    list(n = 5),
    context = list(user = "alice")
  )$structuredContent$view

  bob <- rt_update(
    app,
    list(instance = id, revision = 1L),
    inputs = list(n = 6),
    changed = "n",
    context = list(user = "bob")
  )
  expect_false(identical(rt_meta(bob)$instance, id))

  alice <- rt_open(app, list(view = id, n = 7), context = list(user = "alice"))
  expect_identical(alice$structuredContent$view, id)
  expect_identical(rt_meta(alice)$outputs$out$value, "alice 7")
})

test_that("views opened without a user can be continued by anyone", {
  skip_if_not_installed("shiny")
  ended <- new.env()
  app <- counting_app(ended)
  id <- rt_open(app, list(n = 1))$structuredContent$view
  res <- rt_open(app, list(view = id, n = 2), context = list(user = "carol"))
  expect_identical(res$structuredContent$view, id)
  expect_identical(rt_meta(res)$outputs$out$value, "anonymous 2")
})

# ---- Helpers for server functions ----

test_that("is_mcp_session() is TRUE only inside the runtime", {
  skip_if_not_installed("shiny")
  seen <- NULL
  ui <- shiny::fluidPage(shiny::textOutput("out"))
  server <- function(input, output, session) {
    seen <<- is_mcp_session()
    output$out <- shiny::renderText("x")
  }
  app <- rt_app(ui, server, name = "inside")
  rt_open(app)
  expect_true(seen)

  expect_false(is_mcp_session(NULL))
  expect_false(is_mcp_session(shiny::MockShinySession$new()))
  expect_false(is_mcp_session())
})

test_that("the session helpers work where Shiny isn't installed", {
  skip_if_not_installed("shiny")
  local_mocked_bindings(
    is_installed = function(pkg, ...) !identical(pkg, "shiny"),
    .package = "rlang"
  )
  local_mocked_bindings(
    getDefaultReactiveDomain = function() stop("there is no package 'shiny'"),
    .package = "shiny"
  )
  expect_false(mcp_model_context(text = "hi"))
  expect_false(mcp_send_message("hi"))
  expect_false(is_mcp_session())
  expect_null(mcp_host_context())
})

test_that("the default model context lists the model's inputs and outputs", {
  skip_if_not_installed("shiny")
  app <- cars_text_app()
  view <- rt_meta(rt_open(app, list(xvar = "hp")))
  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(yvar = "qsec"),
    changed = "yvar"
  ))
  context <- meta$modelContext
  expect_identical(
    context$content,
    list(list(
      type = "text",
      text = paste0(
        "In the cars app (view ",
        view$instance,
        '), the user has set xvar = "hp"; yvar = "qsec"; n = 3.',
        " It shows: summary: x: hp y: qsec n: 3; xonly: x is hp."
      )
    ))
  )
  expect_identical(context$structuredContent$app, "cars")
  expect_identical(context$structuredContent$view, view$instance)
  expect_mapequal(
    context$structuredContent$inputs,
    list(xvar = "hp", yvar = "qsec", n = 3)
  )
  expect_mapequal(
    context$structuredContent$outputs,
    list(summary = "x: hp y: qsec n: 3", xonly = "x is hp")
  )

  # Published again only when it changes.
  same <- rt_meta(rt_update(
    app,
    meta,
    inputs = list(yvar = "qsec"),
    changed = "yvar"
  ))
  expect_null(same$modelContext)
})

test_that("runtime_model_context() says when no inputs are set", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::textOutput("out") |> bindMcp())
  server <- function(input, output, session) {
    output$out <- shiny::renderText("constant")
  }
  app <- rt_app(ui, server, name = "empty")
  view <- rt_meta(rt_open(app))
  inst <- rt_instance(app, view$instance)
  inst$model_context_sent <- NULL
  collected <- collect_runtime_outputs(inst, app$runtime()$outputs)

  published <- runtime_model_context(
    inst,
    app$runtime(),
    collected,
    publish = TRUE
  )
  expect_identical(
    published$content[[1]]$text,
    paste0(
      "In the empty app (view ",
      view$instance,
      "). It shows: out: constant."
    )
  )
  expect_identical(published$structuredContent$inputs, json_object())
  # The same context isn't published twice.
  expect_null(runtime_model_context(
    inst,
    app$runtime(),
    collected,
    publish = TRUE
  ))

  # publish = FALSE records it without returning it.
  inst$model_context_sent <- NULL
  expect_null(runtime_model_context(
    inst,
    app$runtime(),
    collected,
    publish = FALSE
  ))
  expect_null(runtime_model_context(
    inst,
    app$runtime(),
    collected,
    publish = TRUE
  ))
})

test_that("mcp_model_context() replaces the default model context", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("cyl", "Cylinders", c("4", "6", "8")),
    shiny::textOutput("n")
  )
  server <- function(input, output, session) {
    cars <- shiny::reactive(mtcars[mtcars$cyl == as.numeric(input$cyl), ])
    shiny::observe({
      mcp_model_context(
        text = c("Showing", paste(nrow(cars()), "cars")),
        data = list(cyl = input$cyl, n = nrow(cars()))
      )
    })
    output$n <- shiny::renderText(nrow(cars()))
  }
  app <- rt_app(ui, server, name = "context")
  view <- rt_meta(rt_open(app, list(cyl = "6")))
  expect_null(view$modelContext)

  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(cyl = "8"),
    changed = "cyl"
  ))
  expect_identical(meta$modelContext$content[[1]]$text, "Showing\n14 cars")
  expect_identical(
    meta$modelContext$structuredContent,
    list(cyl = "8", n = 14L)
  )

  unchanged <- rt_meta(rt_update(
    app,
    meta,
    inputs = list(cyl = "8"),
    changed = "cyl"
  ))
  expect_null(unchanged$modelContext)
})

test_that("mcp_model_context() with only data sends no text", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::numericInput("n", "N", 1))
  server <- function(input, output, session) {
    shiny::observe(mcp_model_context(data = list(n = input$n)))
  }
  app <- rt_app(ui, server, name = "data_only")
  view <- rt_meta(rt_open(app))
  meta <- rt_meta(rt_update(app, view, inputs = list(n = 2), changed = "n"))
  expect_null(meta$modelContext$content)
  expect_identical(meta$modelContext$structuredContent, list(n = 2))
})

test_that("the helpers do nothing outside the runtime and check their arguments", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  expect_false(mcp_model_context("text", session = session))
  expect_invisible(mcp_model_context("text", session = session))
  expect_false(mcp_model_context("text", session = NULL))
  expect_false(mcp_send_message("hello", session = session))
  expect_invisible(mcp_send_message("hello", session = session))

  expect_error(mcp_model_context(session = session), class = "shinymcp_error")
  expect_error(
    mcp_send_message(c("a", "b"), session = session),
    class = "shinymcp_error"
  )
  expect_error(
    mcp_send_message("", session = session),
    class = "shinymcp_error"
  )
  expect_error(
    mcp_send_message(NA_character_, session = session),
    class = "shinymcp_error"
  )
})

test_that("mcp_host_context() is empty until the page reports, then reactive", {
  skip_if_not_installed("shiny")
  seen <- list()
  ui <- shiny::fluidPage(
    shiny::numericInput("n", "N", 1),
    shiny::textOutput("theme"),
    shiny::textOutput("n_out")
  )
  server <- function(input, output, session) {
    seen$initial <<- mcp_host_context()
    output$theme <- shiny::renderText({
      host <- mcp_host_context()
      paste(
        "theme:",
        host$theme %||% "unknown",
        "keys:",
        paste(names(host), collapse = ",")
      )
    })
    output$n_out <- shiny::renderText(input$n)
  }
  app <- rt_app(ui, server, name = "host")
  view <- rt_meta(rt_open(app))
  expect_identical(seen$initial, list())
  expect_identical(view$outputs$theme$value, "theme: unknown keys: ")

  meta <- rt_meta(rt_update(
    app,
    view,
    host = list(
      theme = "dark",
      displayMode = "fullscreen",
      locale = "en-GB",
      timeZone = "Europe/London",
      platform = "web",
      userAgent = "ignored",
      containerDimensions = list(width = 100)
    )
  ))
  # Only the theme output depends on the host context.
  expect_named(meta$outputs, "theme")
  expect_identical(
    meta$outputs$theme$value,
    "theme: dark keys: display_mode,locale,platform,theme,time_zone"
  )

  # The same context again doesn't re-render anything.
  same <- rt_meta(rt_update(
    app,
    meta,
    host = list(
      theme = "dark",
      displayMode = "fullscreen",
      locale = "en-GB",
      timeZone = "Europe/London",
      platform = "web"
    )
  ))
  expect_length(same$outputs, 0)

  lighter <- rt_meta(rt_update(app, same, host = list(theme = "light")))
  expect_identical(lighter$outputs$theme$value, "theme: light keys: theme")

  # Non-string values are dropped.
  odd <- rt_meta(rt_update(app, lighter, host = list(theme = 1, locale = "fr")))
  expect_identical(odd$outputs$theme$value, "theme: unknown keys: locale")

  expect_null(mcp_host_context(NULL))
  expect_null(mcp_host_context(shiny::MockShinySession$new()))
})

# ---- Result text and structured content ----

test_that("format_snapshot_value() writes values the way the model reads them", {
  expect_identical(format_snapshot_value("hp"), '"hp"')
  expect_identical(format_snapshot_value('say "hi"'), '"say \\"hi\\""')
  expect_identical(format_snapshot_value(TRUE), "true")
  expect_identical(format_snapshot_value(c(TRUE, FALSE)), "true, false")
  expect_identical(format_snapshot_value(3), "3")
  expect_identical(format_snapshot_value(c(1.6, 7)), "1.6, 7")
  expect_identical(format_snapshot_value(I(c("a", "b"))), "a, b")
  expect_identical(format_snapshot_value(2L), "2")
})

test_that("runtime_result_text() describes opens, continued views and page updates", {
  runtime <- list(
    title = NULL,
    app_name = "demo",
    model_outputs = "out",
    model_inputs = character()
  )
  inst <- list(id = "view-1")
  collected <- list(
    out = list(text = "hello"),
    multi = list(text = "line 1\nline 2"),
    empty = list(text = "")
  )
  opened <- runtime_result_text(runtime, inst, collected, model = TRUE)
  expect_identical(
    opened,
    "The demo app is open in the conversation (view view-1).\n\nout: hello"
  )
  continued <- runtime_result_text(
    runtime,
    inst,
    collected,
    model = TRUE,
    continued = TRUE
  )
  expect_match(continued, "^Updated the demo app \\(view view-1\\)\\.")
  lost <- runtime_result_text(
    runtime,
    inst,
    collected,
    model = TRUE,
    lost_view = "view-0"
  )
  expect_match(lost, "View view-0 is no longer running", fixed = TRUE)
  unknown <- runtime_result_text(
    runtime,
    inst,
    collected,
    model = TRUE,
    unknown = c("a", "b")
  )
  expect_match(unknown, "Ignored unknown arguments: a, b.", fixed = TRUE)

  # Page updates list every collected output; multi-line text starts on its
  # own line and empty text is skipped.
  page <- runtime_result_text(runtime, inst, collected, model = FALSE)
  expect_identical(
    page,
    "demo updated.\n\nout: hello\n\nmulti:\nline 1\nline 2"
  )

  runtime$title <- "Demo App"
  expect_match(
    runtime_result_text(runtime, inst, collected, model = FALSE),
    "^Demo App updated\\."
  )
})

test_that("structured content reports only model outputs, as JSON-safe values", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::dateInput("when", "When", "2024-01-02") |> bindMcp(),
    shiny::numericInput("hidden_input", "Hidden", 1),
    shiny::textOutput("shown") |> bindMcp(),
    shiny::textOutput("not_shown")
  )
  server <- function(input, output, session) {
    output$shown <- shiny::renderText(format(input$when))
    output$not_shown <- shiny::renderText("secret")
  }
  app <- rt_app(ui, server, name = "safe")
  res <- rt_open(app)
  expect_identical(res$structuredContent$inputs, list(when = "2024-01-02"))
  expect_identical(res$structuredContent$outputs, list(shown = "2024-01-02"))
  expect_no_match(rt_text(res), "secret", fixed = TRUE)
  # The page still gets every output.
  expect_identical(rt_meta(res)$outputs$not_shown$value, "secret")
  # Structured content with nothing to report is an empty object.
  expect_identical(
    runtime_input_snapshot(
      list(model_inputs = character(), inputs = list()),
      NULL
    ),
    json_object()
  )
})

test_that("page_input_updates() sends what the page doesn't already show", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  session$setInputs(
    a = 1,
    b = "x",
    go = action_value(2L),
    when = as.Date("2024-01-01"),
    blank = NA_real_
  )
  inst <- new.env(parent = emptyenv())
  inst$session <- session

  full <- page_input_updates(inst, full = TRUE)
  expect_mapequal(full, list(a = 1, b = "x", go = 2L, when = "2024-01-01"))
  expect_null(page_input_updates(inst, full = FALSE))

  session$setInputs(a = 2, b = "y")
  inst$page_sent <- list(b = "y")
  expect_identical(page_input_updates(inst, full = FALSE), list(a = 2))
  expect_null(inst$page_sent)
})

test_that("option_values() reads values and selections from options HTML", {
  html <- paste0(
    '<option value="a">A</option>',
    '<option value="b&amp;c" selected>B</option>',
    '<input type="radio" name="r" value="x" checked="checked"/>',
    '<input type="text" value="ignored"/>'
  )
  values <- option_values(html)
  expect_identical(as.vector(values), c("a", "b&c", "x"))
  expect_identical(attr(values, "selected"), c("b&c", "x"))
  expect_length(option_values(""), 0)
})

test_that("implied_input_value() mirrors the browser's input bindings", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  session$setInputs(
    pick = "b",
    many = c("a", "b"),
    free = "text",
    n = 1,
    flag = FALSE
  )
  select <- list(id = "pick", kind = "select", choices = c("a", "b"))

  # A value in the message wins.
  expect_identical(
    implied_input_value(
      list(id = "pick", message = list(value = "a")),
      select,
      session
    ),
    list(value = "a")
  )
  # An unchanged value implies nothing.
  expect_null(implied_input_value(
    list(id = "pick", message = list(value = "b")),
    select,
    session
  ))
  # New options without a selection keep a valid value...
  expect_null(implied_input_value(
    list(
      id = "pick",
      message = list(
        options = '<option value="c">C</option><option value="b">B</option>'
      )
    ),
    select,
    session
  ))
  # ...or fall back to the first option.
  expect_identical(
    implied_input_value(
      list(
        id = "pick",
        message = list(options = '<option value="c">C</option>')
      ),
      select,
      session
    ),
    list(value = "c")
  )
  # Multiple selects take their selection from the new options alone, as
  # Shiny's binding and the page's do.
  expect_identical(
    implied_input_value(
      list(
        id = "many",
        message = list(
          options = '<option value="b">B</option><option value="z">Z</option>'
        )
      ),
      list(id = "many", kind = "select-multiple"),
      session
    ),
    list(value = NULL)
  )
  expect_identical(
    implied_input_value(
      list(
        id = "many",
        message = list(
          options = '<option value="b" selected>B</option><option value="z">Z</option>'
        )
      ),
      list(id = "many", kind = "select-multiple"),
      session
    ),
    list(value = "b")
  )
  # Without a spec the kind is guessed from the current value.
  expect_identical(
    implied_input_value(
      list(id = "n", message = list(value = 5)),
      NULL,
      session
    ),
    list(value = 5)
  )
  expect_identical(
    implied_input_value(
      list(id = "flag", message = list(value = TRUE)),
      NULL,
      session
    ),
    list(value = TRUE)
  )
  # Label-only updates don't change the value.
  expect_null(implied_input_value(
    list(id = "free", message = list(label = "New")),
    NULL,
    session
  ))
})

# ---- The session class ----

test_that("runtime_session_class() is a MockShinySession subclass, made once", {
  skip_if_not_installed("shiny")
  cls <- runtime_session_class()
  expect_identical(runtime_session_class(), cls)
  session <- cls$new()
  expect_true(inherits(session, "MockShinySession"))
  expect_true(inherits(session, "ShinymcpRuntimeSession"))
})

test_that("the session records defined outputs and registered downloads", {
  skip_if_not_installed("shiny")
  session <- runtime_session_class()$new()
  inst <- new.env(parent = emptyenv())
  inst$outputs <- character()
  inst$downloads <- list()
  session$userData$.shinymcp <- inst
  with_mock_context(session, {
    session$output$text <- shiny::renderText("x")
    session$output$file <- shiny::downloadHandler(
      "data.csv",
      function(file) NULL,
      contentType = "text/csv"
    )
  })
  # Download handlers register themselves when the outputs are flushed.
  expect_null(inst$downloads$file)
  session$flushReact()
  expect_true("text" %in% inst$outputs)
  expect_identical(inst$downloads$file$content_type, "text/csv")
  expect_identical(inst$downloads$file$filename(), "data.csv")
})

test_that("drain() empties a queue once", {
  inst <- new.env(parent = emptyenv())
  inst$queue <- list("a", "b")
  inst$echoed <- 2
  expect_identical(drain(inst, "queue", reset_echo = TRUE), list("a", "b"))
  expect_identical(inst$echoed, 0)
  expect_null(drain(inst, "queue"))
})

test_that("updateSliderInput() moves a date slider", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::checkboxInput("later", "Later", FALSE),
    shiny::sliderInput(
      "day",
      "Day",
      min = as.Date("2024-01-01"),
      max = as.Date("2024-12-31"),
      value = as.Date("2024-03-01")
    ),
    shiny::textOutput("o")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$later, {
      if (isTRUE(input$later)) {
        shiny::updateSliderInput(session, "day", value = as.Date("2024-06-01"))
      }
    })
    output$o <- shiny::renderText(format(input$day))
  }
  app <- rt_app(ui, server, name = "days")
  res <- rt_open(app, list(later = TRUE))
  expect_identical(rt_meta(res)$outputs$o$value, "2024-06-01")
})

test_that("the model and updateTabsetPanel() choose the shown tab", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::actionButton("jump", "Jump"),
    shiny::tabsetPanel(
      id = "tabs",
      shiny::tabPanel("Plot", "p"),
      shiny::tabPanel("Table", "t")
    ),
    shiny::textOutput("shown")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$jump, {
      shiny::updateTabsetPanel(session, "tabs", selected = "Plot")
    })
    output$shown <- shiny::renderText(paste("showing", input$tabs))
  }
  app <- rt_app(ui, server, name = "tabbed")
  expect_true("tabs" %in% app$runtime()$model_inputs)

  res <- rt_open(app, list(tabs = "Table"))
  view <- rt_meta(res)
  expect_identical(view$outputs$shown$value, "showing Table")
  expect_identical(view$inputs$tabs, "Table")

  # The user clicks back to Plot on the page.
  clicked <- rt_meta(rt_update(
    app,
    view,
    inputs = list(tabs = "Plot"),
    changed = "tabs"
  ))
  expect_identical(clicked$outputs$shown$value, "showing Plot")

  # The server moves the tabset.
  back <- rt_meta(rt_update(
    app,
    clicked,
    inputs = list(tabs = "Table"),
    changed = "tabs"
  ))
  expect_identical(back$outputs$shown$value, "showing Table")
  jumped <- rt_meta(rt_update(
    app,
    back,
    inputs = list(tabs = "Table", jump = 1),
    changed = "jump"
  ))
  expect_identical(jumped$outputs$shown$value, "showing Plot")
  expect_identical(jumped$inputMessages[[1]]$id, "tabs")
  expect_identical(jumped$inputMessages[[1]]$message$value, "Plot")
})

test_that("a restarted view doesn't redo earlier button presses", {
  skip_if_not_installed("shiny")
  saves <- 0
  ui <- shiny::fluidPage(
    shiny::textInput("note", "Note", "a"),
    shiny::actionButton("save", "Save"),
    shiny::textOutput("o")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$save, saves <<- saves + 1)
    output$o <- shiny::renderText(input$note)
  }
  app <- rt_app(ui, server, name = "saver")
  gone <- list(instance = "view-gone", revision = 3L)

  # The page had pressed Save three times; the user now edits the note.
  rt_update(app, gone, inputs = list(note = "b", save = 3), changed = "note")
  expect_identical(saves, 0)

  # A press that arrives with the restart still counts, once.
  rt_update(
    app,
    list(instance = "view-gone-2", revision = 3L),
    inputs = list(note = "b", save = 4),
    changed = "save"
  )
  expect_identical(saves, 1)
})

test_that("choices the server sets are valid when the model changes a view", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::selectInput("make", "Make", c("Ford", "Honda")),
    shiny::selectInput("model", "Model", "none"),
    shiny::textOutput("o")
  )
  server <- function(input, output, session) {
    shiny::observeEvent(input$make, {
      models <- switch(
        input$make,
        Ford = c("F150", "Focus"),
        Honda = c("Civic", "Fit")
      )
      shiny::updateSelectInput(session, "model", choices = models)
    })
    output$o <- shiny::renderText(paste(input$make, input$model))
  }
  app <- rt_app(ui, server, name = "cars2")
  opened <- rt_meta(rt_open(app, list(make = "Honda")))
  expect_identical(opened$outputs$o$value, "Honda Civic")

  steered <- rt_open(app, list(view = opened$instance, model = "Fit"))
  expect_null(steered$isError)
  expect_identical(rt_meta(steered)$outputs$o$value, "Honda Fit")

  wrong <- rt_open(app, list(view = opened$instance, model = "F150"))
  expect_true(wrong$isError)
})

test_that("inputs the page marks as events count even when they repeat", {
  skip_if_not_installed("shiny")
  clicks <- 0
  ui <- shiny::fluidPage(shiny::textOutput("o"))
  server <- function(input, output, session) {
    shiny::observeEvent(input$map_click, clicks <<- clicks + 1)
    output$o <- shiny::renderText(paste("clicks", clicks, input$map_click$lat))
  }
  app <- rt_app(ui, server, name = "clicks")
  view <- rt_meta(rt_open(app))
  point <- list(lat = 1, lng = 2)
  first <- rt_meta(rt_update(
    app,
    view,
    inputs = list(map_click = point),
    changed = "map_click",
    kinds = list(map_click = list(kind = "value")),
    events = "map_click"
  ))
  expect_identical(clicks, 1)
  rt_update(
    app,
    first,
    inputs = list(map_click = point),
    changed = "map_click",
    kinds = list(map_click = list(kind = "value")),
    events = "map_click"
  )
  expect_identical(clicks, 2)
  # Without the event mark, a repeated value is no change.
  rt_update(app, first, inputs = list(map_click = point), changed = "map_click")
  expect_identical(clicks, 2)
})

test_that("values from JavaScript go through the input handler for their type", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::textOutput("o"))
  server <- function(input, output, session) {
    output$o <- shiny::renderText(class(input$when)[1])
  }
  app <- rt_app(ui, server, name = "typed")
  view <- rt_meta(rt_open(app))
  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(when = "2024-05-01", .clientValue_x = 1),
    changed = c("when", ".clientValue_x"),
    kinds = list(when = list(kind = "value", type = "shiny.date"))
  ))
  expect_identical(meta$outputs$o$value, "Date")
})

test_that("the model's result names large libraries, and the page fetches them", {
  skip_if_not_installed("shiny")
  withr::local_options(shinymcp.max_inline_dependency_bytes = 100)
  dir <- withr::local_tempdir()
  writeLines(strrep("window.bigLibrary = 1;\n", 20), file.path(dir, "big.js"))
  big <- htmltools::htmlDependency(
    "big-lib",
    "2.0.0",
    src = c(file = dir),
    script = "big.js"
  )
  ui <- shiny::fluidPage(shiny::uiOutput("dyn"))
  server <- function(input, output, session) {
    output$dyn <- shiny::renderUI(htmltools::tagList(htmltools::div("hi"), big))
  }
  app <- rt_app(ui, server, name = "big")
  view <- rt_meta(rt_open(app))
  dep <- view$outputs$dyn$deps[[1]]
  expect_identical(dep, list(name = "big-lib", version = "2.0.0", fetch = TRUE))

  fetched <- app$run_tool(
    "big_view",
    list(action = "dependency", dependency = "big-lib@2.0.0"),
    context = list(caller = "app")
  )
  expect_null(fetched$isError)
  expect_match(
    rt_meta(fetched)$dependency$head,
    "window.bigLibrary = 1;",
    fixed = TRUE
  )

  missing <- app$run_tool(
    "big_view",
    list(action = "dependency", dependency = "nope@1"),
    context = list(caller = "app")
  )
  expect_true(missing$isError)

  # The page's own calls carry libraries whole.
  update <- rt_meta(rt_update(app, view, all = TRUE))
  expect_match(
    update$outputs$dyn$deps[[1]]$head,
    "window.bigLibrary",
    fixed = TRUE
  )
})

test_that("results leave out libraries the page was built with", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::uiOutput("dyn"))
  server <- function(input, output, session) {
    output$dyn <- shiny::renderUI(shiny::fluidRow(shiny::column(6, "x")))
  }
  app <- rt_app(ui, server, name = "own")
  view <- rt_meta(rt_open(app))
  names <- vapply(
    view$outputs$dyn$deps %||% list(),
    function(d) d$name,
    character(1)
  )
  expect_false("jquery" %in% names)
  expect_false("bootstrap" %in% names)
})

test_that("views say when their next timer is due, and a tick runs it", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::textOutput("n"))
  server <- function(input, output, session) {
    count <- 0
    output$n <- shiny::renderText({
      shiny::invalidateLater(200)
      count <<- count + 1
      count
    })
  }
  app <- rt_app(ui, server, name = "ticker")
  view <- rt_meta(rt_open(app))
  expect_identical(view$outputs$n$value, "1")
  expect_true(is.numeric(view$nextTick))
  expect_lte(view$nextTick, 200)

  Sys.sleep(0.3)
  ticked <- rt_meta(rt_update(app, view, tick = TRUE))
  expect_identical(ticked$outputs$n$value, "2")

  # A long pause runs the timer once, not once for every interval missed.
  Sys.sleep(1)
  later <- rt_meta(rt_update(app, ticked, tick = TRUE))
  expect_identical(later$outputs$n$value, "3")
})

test_that("views without timers don't ask the page to check back", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::textOutput("n"))
  app <- rt_app(
    ui,
    function(input, output, session) {
      output$n <- shiny::renderText("still")
    },
    name = "still"
  )
  expect_null(rt_meta(rt_open(app))$nextTick)
})

test_that("files the page uploads reach the server as Shiny's data frame", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::fileInput("upload", "Upload"),
    shiny::textOutput("o")
  )
  server <- function(input, output, session) {
    output$o <- shiny::renderText({
      shiny::req(input$upload)
      paste(input$upload$name, nrow(utils::read.csv(input$upload$datapath)))
    })
  }
  app <- rt_app(ui, server, name = "uploads")
  expect_false("upload" %in% app$runtime()$model_inputs)
  view <- rt_meta(rt_open(app))
  csv <- "a,b\n1,2\n3,4\n"
  file <- list(
    name = "data.csv",
    size = nchar(csv),
    type = "text/csv",
    data = jsonlite::base64_enc(charToRaw(csv))
  )
  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(upload = list(file)),
    changed = "upload",
    kinds = list(upload = list(kind = "file"))
  ))
  expect_identical(meta$outputs$o$value, "data.csv 2")

  inst <- rt_instance(app, view$instance)
  datapath <- shiny::isolate(inst$session$input$upload$datapath)
  expect_true(file.exists(datapath))
  expect_identical(basename(datapath), "0.csv")
  # Closing the view removes its uploads.
  app$run_tool(
    "uploads_view",
    list(action = "close", instance = view$instance),
    context = list(caller = "app")
  )
  expect_false(file.exists(datapath))
})

test_that("an upload that can't be read leaves no files behind", {
  skip_if_not_installed("shiny")
  uploads <- function() list.files(tempdir(), pattern = "^shinymcp-upload-")
  before <- uploads()
  ui <- shiny::fluidPage(shiny::fileInput("upload", "Upload"))
  upload <- function(files) {
    app <- rt_app(ui, function(input, output, session) NULL, name = "broken")
    rt_update(
      app,
      rt_meta(rt_open(app)),
      inputs = list(upload = files),
      changed = "upload",
      kinds = list(upload = list(kind = "file"))
    )
  }

  res <- upload(list("not a file"))
  expect_true(res$isError)
  expect_match(res$content[[1]]$text, "must be an object", fixed = TRUE)
  withr::with_options(list(shiny.maxRequestSize = 10), {
    res <- upload(list(list(
      name = "big.txt",
      data = jsonlite::base64_enc(charToRaw(strrep("x", 100)))
    )))
  })
  expect_true(res$isError)
  expect_setequal(uploads(), before)
})

test_that("uploads over shiny.maxRequestSize are refused", {
  skip_if_not_installed("shiny")
  withr::local_options(shiny.maxRequestSize = 10)
  ui <- shiny::fluidPage(shiny::fileInput("upload", "Upload"))
  app <- rt_app(ui, function(input, output, session) NULL, name = "limit")
  view <- rt_meta(rt_open(app))
  res <- rt_update(
    app,
    view,
    inputs = list(
      upload = list(list(
        name = "big.txt",
        data = jsonlite::base64_enc(charToRaw(strrep("x", 100)))
      ))
    ),
    changed = "upload",
    kinds = list(upload = list(kind = "file"))
  )
  expect_true(res$isError)
  expect_match(res$content[[1]]$text, "limited", fixed = TRUE)
})
