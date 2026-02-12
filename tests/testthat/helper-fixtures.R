# Test fixtures for shinymcp tests

# Simple app with one input, one output
fixture_simple_app <- function(dir = tempdir()) {
  app_dir <- file.path(dir, "simple-app")
  dir.create(app_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(
    '
library(shiny)
ui <- fluidPage(
  selectInput("x", "Choose:", c("a", "b", "c")),
  textOutput("result")
)
server <- function(input, output, session) {
  output$result <- renderText({ paste("You chose:", input$x) })
}
shinyApp(ui, server)
',
    file.path(app_dir, "app.R")
  )
  app_dir
}

# Medium complexity app
fixture_medium_app <- function(dir = tempdir()) {
  app_dir <- file.path(dir, "medium-app")
  dir.create(app_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(
    '
library(shiny)
ui <- fluidPage(
  selectInput("dataset", "Dataset:", c("mtcars", "iris")),
  numericInput("obs", "Rows:", 10, min = 1, max = 50),
  textOutput("summary"),
  tableOutput("table")
)
server <- function(input, output, session) {
  data <- reactive({
    head(get(input$dataset, envir = asNamespace("datasets")), input$obs)
  })
  output$summary <- renderText({
    paste("Showing", nrow(data()), "rows")
  })
  output$table <- renderTable({ data() })
}
shinyApp(ui, server)
',
    file.path(app_dir, "app.R")
  )
  app_dir
}

# Complex app with observers
fixture_complex_app <- function(dir = tempdir()) {
  app_dir <- file.path(dir, "complex-app")
  dir.create(app_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(
    '
library(shiny)
ui <- fluidPage(
  selectInput("x", "X:", c("a", "b")),
  selectInput("y", "Y:", c("1", "2")),
  actionButton("go", "Go"),
  textOutput("out1"),
  plotOutput("out2"),
  tableOutput("out3")
)
server <- function(input, output, session) {
  rv <- reactiveValues(count = 0)
  data <- reactive({ mtcars[1:5, ] })
  observeEvent(input$go, { rv$count <- rv$count + 1 })
  output$out1 <- renderText({ paste(input$x, input$y, rv$count) })
  output$out2 <- renderPlot({ plot(data()) })
  output$out3 <- renderTable({ data() })
}
shinyApp(ui, server)
',
    file.path(app_dir, "app.R")
  )
  app_dir
}

# App with chained reactives AND independent groups
# - base_data depends on input$dataset
# - filtered_data depends on base_data() + input$n_rows (chain!)
# - output$summary depends on filtered_data()
# - output$greeting depends only on input$user_name (separate group)
fixture_chained_reactive_app <- function(dir = tempdir()) {
  app_dir <- file.path(dir, "chained-app")
  dir.create(app_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(
    '
library(shiny)
ui <- fluidPage(
  selectInput("dataset", "Dataset:", c("mtcars", "iris")),
  numericInput("n_rows", "Rows:", 10, min = 1, max = 50),
  textOutput("summary"),
  plotOutput("plot"),
  textInput("user_name", "Name:"),
  textOutput("greeting")
)
server <- function(input, output, session) {
  base_data <- reactive({
    get(input$dataset, envir = asNamespace("datasets"))
  })
  filtered_data <- reactive({
    head(base_data(), input$n_rows)
  })
  output$summary <- renderText({
    paste("Showing", nrow(filtered_data()), "rows")
  })
  output$plot <- renderPlot({
    d <- filtered_data()
    if (ncol(d) >= 2) plot(d[[1]], d[[2]])
  })
  output$greeting <- renderText({
    paste("Hello,", input$user_name)
  })
}
shinyApp(ui, server)
',
    file.path(app_dir, "app.R")
  )
  app_dir
}

# App with a reactive that depends on multiple other reactives
fixture_multi_reactive_deps_app <- function(dir = tempdir()) {
  app_dir <- file.path(dir, "multi-reactive-deps-app")
  dir.create(app_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(
    '
library(shiny)
ui <- fluidPage(
  numericInput("x", "X:", 1),
  numericInput("y", "Y:", 1),
  textOutput("result")
)
server <- function(input, output, session) {
  val_x <- reactive({ input$x * 2 })
  val_y <- reactive({ input$y + 1 })
  combined <- reactive({ val_x() + val_y() })
  output$result <- renderText({ paste("Result:", combined()) })
}
shinyApp(ui, server)
',
    file.path(app_dir, "app.R")
  )
  app_dir
}

# Split-file app (ui.R + server.R)
fixture_split_app <- function(dir = tempdir()) {
  app_dir <- file.path(dir, "split-app")
  dir.create(app_dir, showWarnings = FALSE, recursive = TRUE)
  writeLines(
    '
library(shiny)
fluidPage(
  textInput("name", "Name:"),
  textOutput("greeting")
)
',
    file.path(app_dir, "ui.R")
  )
  writeLines(
    '
function(input, output, session) {
  output$greeting <- renderText({ paste("Hello,", input$name) })
}
',
    file.path(app_dir, "server.R")
  )
  app_dir
}
