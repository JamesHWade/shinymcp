# Original Shiny app that demonstrates:
# 1. Chained reactives (filtered_data depends on base_data)
# 2. Two independent tool groups (stats group vs. greeting group)
#
# This app is designed to exercise the analyzer's reactive graph tracking.
# The conversion pipeline should produce TWO tool groups:
#   - Tool 1: update_summary_and_plot (dataset, n_rows, sort_col)
#   - Tool 2: update_greeting (user_name)

library(shiny)

ui <- fluidPage(
  titlePanel("Multi-Tool Demo"),

  # --- Group 1: Data exploration (chained reactives) ---
  sidebarLayout(
    sidebarPanel(
      selectInput("dataset", "Dataset:", c("mtcars", "iris", "pressure")),
      numericInput("n_rows", "Rows:", 10, min = 1, max = 50),
      selectInput("sort_col", "Sort by:", c("default"))
    ),
    mainPanel(
      textOutput("summary"),
      plotOutput("plot")
    )
  ),

  # --- Group 2: Independent greeting (no shared reactives) ---
  hr(),
  textInput("user_name", "Your name:"),
  textOutput("greeting")
)

server <- function(input, output, session) {
  # Reactive chain: base_data -> filtered_data
  # base_data depends on input$dataset
  base_data <- reactive({
    get(input$dataset, envir = asNamespace("datasets"))
  })

  # filtered_data depends on base_data() AND input$n_rows, input$sort_col
  # This is the chained reactive case the analyzer must handle.
  filtered_data <- reactive({
    d <- head(base_data(), input$n_rows)
    if (input$sort_col != "default" && input$sort_col %in% names(d)) {
      d <- d[order(d[[input$sort_col]]), ]
    }
    d
  })

  output$summary <- renderText({
    d <- filtered_data()
    paste(
      "Showing",
      nrow(d),
      "of",
      nrow(base_data()),
      "rows from",
      input$dataset
    )
  })

  output$plot <- renderPlot({
    d <- filtered_data()
    if (ncol(d) >= 2) {
      plot(
        d[[1]],
        d[[2]],
        xlab = names(d)[1],
        ylab = names(d)[2],
        main = input$dataset
      )
    }
  })

  # Independent group: greeting
  output$greeting <- renderText({
    if (nzchar(input$user_name)) {
      paste("Hello,", input$user_name, "!")
    } else {
      "Enter your name above."
    }
  })
}

shinyApp(ui, server)
