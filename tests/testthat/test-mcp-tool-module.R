# mcp_tool_module(): a Shiny module served as an MCP App
# (R/mcp-tool-module.R)

car_picker_ui <- function(id) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    shiny::selectInput(ns("cyl"), "Cylinders", c("4", "6", "8")),
    shiny::selectInput(ns("car"), "Car", "none"),
    shiny::numericInput(ns("digits"), "Digits", 1),
    shiny::textOutput(ns("picked")),
    shiny::plotOutput(ns("plot"), height = "200px")
  )
}

car_picker_server <- function(id, prefix = "Car:") {
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
    output$picked <- shiny::renderText({
      shiny::req(input$car != "none")
      mpg <- round(mtcars[input$car, "mpg"], input$digits)
      paste(prefix, input$car, mpg, "mpg")
    })
    output$plot <- shiny::renderPlot(plot(mtcars$wt, mtcars$mpg))
  })
}

# ---- The live runtime ----

test_that("a module runs live, with un-namespaced tool arguments", {
  skip_if_not_installed("shiny")
  app <- mcp_tool_module(
    car_picker_ui,
    car_picker_server,
    name = "cars",
    description = "Pick a car."
  )
  expect_s3_class(app, "McpApp")
  expect_identical(app$name, "cars")
  expect_identical(app$description, "Pick a car.")
  expect_s3_class(app$runtime(), "ShinyRuntime")
  expect_named(app$tools(), c("cars", "cars_view"))
  expect_identical(app$tools()$cars$description, "Pick a car.")
  expect_named(
    app$tools()$cars$input_schema$properties,
    c("cyl", "car", "digits", "view")
  )

  runtime <- app$runtime()
  expect_identical(
    vapply(runtime$inputs, function(i) i$dom_id, character(1)),
    c(cyl = "mcp-cars-cyl", car = "mcp-cars-car", digits = "mcp-cars-digits")
  )
  expect_identical(
    vapply(runtime$outputs, function(o) o$dom_id, character(1)),
    c(picked = "mcp-cars-picked", plot = "mcp-cars-plot")
  )
  expect_identical(runtime$bridge_config()$ns, "mcp-cars")
})

test_that("opening the module sets namespaced inputs and reports outputs by plain id", {
  skip_if_not_installed("shiny")
  app <- mcp_tool_module(
    car_picker_ui,
    car_picker_server,
    name = "cars",
    description = "Pick a car."
  )
  res <- rt_open(app, list(cyl = "8", digits = 0))
  view <- rt_meta(res)
  first_eight <- rownames(mtcars)[mtcars$cyl == 8][[1]]
  mpg <- round(mtcars[first_eight, "mpg"], 0)

  expect_null(res$isError)
  expect_setequal(names(view$outputs), c("picked", "plot"))
  expect_identical(view$outputs$picked$dom, "mcp-cars-picked")
  expect_identical(
    view$outputs$picked$value,
    paste("Car:", first_eight, mpg, "mpg")
  )
  # The plot takes its height from the namespaced plotOutput().
  expect_identical(view$outputs$plot$value$height, 200)

  # The page gets inputs by their DOM ids; the model by plain ids.
  expect_identical(view$inputs[["mcp-cars-cyl"]], "8")
  expect_identical(view$inputs[["mcp-cars-car"]], first_eight)
  expect_mapequal(
    res$structuredContent$inputs,
    list(cyl = "8", car = first_eight, digits = 0)
  )
  expect_match(rt_text(res), paste0('car = "', first_eight, '"'), fixed = TRUE)

  # updateSelectInput() inside the module reached the namespaced input.
  expect_identical(view$inputMessages[[1]]$id, "mcp-cars-car")
  expect_identical(
    rt_session_input(app, view$instance, "mcp-cars-car"),
    first_eight
  )
})

test_that("page updates use namespaced ids", {
  skip_if_not_installed("shiny")
  app <- mcp_tool_module(
    car_picker_ui,
    car_picker_server,
    name = "cars",
    description = "Pick a car."
  )
  view <- rt_meta(rt_open(app, list(cyl = "8")))
  first_four <- rownames(mtcars)[mtcars$cyl == 4][[1]]

  meta <- rt_meta(rt_update(
    app,
    view,
    inputs = list(`mcp-cars-cyl` = "4"),
    changed = "mcp-cars-cyl"
  ))
  expect_named(meta$outputs, "picked")
  expect_match(meta$outputs$picked$value, first_four, fixed = TRUE)
  # The server's new value for the car select goes back to the page.
  expect_identical(meta$inputs, list(`mcp-cars-car` = first_four))
  expect_identical(
    meta$modelContext$structuredContent$inputs$cyl,
    "4"
  )
})

test_that("the model can steer an open module view", {
  skip_if_not_installed("shiny")
  app <- mcp_tool_module(
    car_picker_ui,
    car_picker_server,
    name = "cars",
    description = "Pick a car."
  )
  id <- rt_open(app, list(cyl = "6"))$structuredContent$view
  res <- rt_open(app, list(view = id, digits = 2))
  expect_identical(res$structuredContent$view, id)
  expect_identical(res$structuredContent$inputs$cyl, "6")
  expect_identical(res$structuredContent$inputs$digits, 2)
})

test_that("extra arguments reach the module server", {
  skip_if_not_installed("shiny")
  app <- mcp_tool_module(
    car_picker_ui,
    car_picker_server,
    name = "cars",
    description = "Pick a car.",
    prefix = "Chosen:"
  )
  res <- rt_open(app, list(cyl = "6"))
  expect_match(rt_meta(res)$outputs$picked$value, "^Chosen: ")
})

test_that("the module namespace comes from the sanitized name", {
  skip_if_not_installed("shiny")
  seen <- NULL
  mod_ui <- function(id) {
    seen <<- id
    shiny::textInput(shiny::NS(id, "q"), "Query")
  }
  mod_server <- function(id) {
    shiny::moduleServer(id, function(input, output, session) NULL)
  }
  app <- mcp_tool_module(
    mod_ui,
    mod_server,
    name = "Car Search!",
    description = "Search."
  )
  expect_identical(seen, "mcp-Car_Search")
  expect_identical(app$name, "Car Search!")
  expect_named(app$tools(), c("Car_Search", "Car_Search_view"))
  expect_identical(app$runtime()$inputs$q$dom_id, "mcp-Car_Search-q")
})

test_that("the version is passed through", {
  skip_if_not_installed("shiny")
  app <- mcp_tool_module(
    car_picker_ui,
    car_picker_server,
    name = "cars",
    description = "Pick a car.",
    version = "1.2.3"
  )
  expect_identical(app$version, "1.2.3")
})

# ---- With a handler ----

picker_ui <- function(id) {
  ns <- shiny::NS(id)
  htmltools::tagList(
    shiny::selectInput(ns("choice"), "Pick", c("a", "b")),
    shiny::numericInput(ns("n"), "N", 2),
    shiny::dateInput(ns("when"), "When", "2024-01-01"),
    shiny::actionButton(ns("go"), "Go"),
    shiny::textOutput(ns("result")),
    shiny::plotOutput(ns("plot"))
  )
}

picker_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    stop("The server function doesn't run when a handler is given.")
  })
}

test_that("a handler replaces the live runtime with one stateless tool", {
  skip_if_not_installed("shiny")
  handler <- function(choice = "a", n = 1) {
    list(result = paste("Chose", choice, n))
  }
  app <- mcp_tool_module(
    picker_ui,
    picker_server,
    name = "pick",
    description = "Pick one.",
    handler = handler
  )
  expect_null(app$runtime())
  expect_named(app$tools(), "pick")
  expect_identical(
    app$call_tool("pick", list(choice = "b", n = 3)),
    list(result = "Chose b 3")
  )

  def <- app$tool_definitions()[[1]]
  expect_identical(def$description, "Pick one.")
  # The schema is guessed from the handler's defaults.
  expect_identical(def$inputSchema$properties$choice, list(type = "string"))
  expect_identical(def$inputSchema$properties$n, list(type = "number"))
  # Outputs are declared by their plain ids.
  expect_setequal(names(def$outputSchema$properties), c("result", "plot"))

  res <- app$run_tool("pick", list(choice = "b", n = 3))
  expect_identical(res$content[[1]]$text, "result: Chose b 3")
  expect_identical(res$structuredContent, list(result = "Chose b 3"))
})

test_that("the handler's UI is annotated with plain ids for the bridge", {
  skip_if_not_installed("shiny")
  app <- mcp_tool_module(
    picker_ui,
    picker_server,
    name = "pick",
    description = "Pick one.",
    handler = function(choice = "a") list(result = choice)
  )
  html <- app$html_resource()
  for (id in c("choice", "n", "when", "go")) {
    expect_match(html, paste0('data-shinymcp-input="', id, '"'), fixed = TRUE)
  }
  expect_match(html, 'data-shinymcp-output="result"', fixed = TRUE)
  expect_match(html, 'data-shinymcp-output="plot"', fixed = TRUE)
  expect_match(html, 'data-shinymcp-output-type="plot"', fixed = TRUE)
  # The elements keep their namespaced DOM ids.
  expect_match(html, 'id="mcp-pick-choice"', fixed = TRUE)
  expect_match(html, '"mode":"tools"', fixed = TRUE)
})

test_that("ellmer argument types describe the handler's inputs", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("ellmer")
  app <- mcp_tool_module(
    picker_ui,
    picker_server,
    name = "pick",
    description = "Pick one.",
    handler = function(choice, n) list(result = paste(choice, n)),
    arguments = list(
      choice = ellmer::type_enum(c("a", "b"), "Which one"),
      n = ellmer::type_number("How many")
    )
  )
  schema <- app$tool_definitions()[[1]]$inputSchema
  expect_identical(unclass(schema$properties$choice$enum), c("a", "b"))
  expect_identical(schema$properties$n$type, "number")
  expect_identical(unclass(schema$required), c("choice", "n"))
  expect_identical(
    app$call_tool("pick", list(choice = "a", n = 5)),
    list(result = "a 5")
  )
})

# ---- Validation ----

test_that("mcp_tool_module() checks its arguments", {
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
  expect_error(
    mcp_tool_module(identity, identity, name = c("a", "b"), description = "x"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_tool_module(identity, identity, name = "x", description = c("a", "b")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_tool_module(identity, identity, name = "x", description = NULL),
    class = "shinymcp_error_validation"
  )
})

test_that("a module UI that fails names the id it was given", {
  broken_ui <- function(id) stop("no data")
  expect_error(
    mcp_tool_module(broken_ui, identity, name = "broken", description = "x"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_tool_module(broken_ui, identity, name = "broken", description = "x"),
    "mcp-broken"
  )
})

# ---- Helpers ----

test_that("normalize_module_bindings() strips the namespace but keeps DOM ids", {
  bindings <- list(
    list(id = "mcp-x-a", type = "text"),
    list(id = "other", dom_id = "other-dom", type = "text")
  )
  out <- normalize_module_bindings(bindings, "mcp-x")
  expect_identical(out[[1]]$id, "a")
  expect_identical(out[[1]]$dom_id, "mcp-x-a")
  expect_identical(out[[2]]$id, "other")
  expect_identical(out[[2]]$dom_id, "other-dom")
})

test_that("annotate_module_ui() stamps inputs and outputs once", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::selectInput("mcp-x-a", "A", c("1", "2")),
    shiny::textOutput("mcp-x-out")
  )
  inputs <- list(list(id = "a", dom_id = "mcp-x-a"))
  outputs <- list(list(id = "out", dom_id = "mcp-x-out", type = "text"))
  annotated <- annotate_module_ui(ui, inputs, outputs)
  html <- as.character(annotated)
  expect_match(html, 'data-shinymcp-input="a"', fixed = TRUE)
  expect_match(html, 'data-shinymcp-output="out"', fixed = TRUE)
  # Annotating again changes nothing.
  expect_identical(
    as.character(annotate_module_ui(annotated, inputs, outputs)),
    html
  )
})

test_that("a handler needs no module server", {
  skip_if_not_installed("shiny")
  hist_ui <- function(id) {
    ns <- shiny::NS(id)
    htmltools::tagList(
      shiny::numericInput(ns("bins"), "Bins", 20),
      shiny::textOutput(ns("text"))
    )
  }
  app <- mcp_tool_module(
    hist_ui,
    name = "bins",
    description = "Report the number of bins.",
    handler = function(bins = 20) list(text = paste(bins, "bins"))
  )
  expect_identical(app$call_tool("bins", list(bins = 7))$text, "7 bins")
  expect_error(
    mcp_tool_module(hist_ui, name = "x", description = "x"),
    class = "shinymcp_error_validation"
  )
})
