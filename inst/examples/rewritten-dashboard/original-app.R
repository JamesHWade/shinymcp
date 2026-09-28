library(shiny)

ui <- fluidPage(
  titlePanel("Simple Dashboard"),
  sidebarLayout(
    sidebarPanel(
      selectInput("dataset", "Dataset:", c("mtcars", "iris")),
      numericInput("obs", "Observations:", 10, min = 1, max = 50)
    ),
    mainPanel(
      textOutput("summary_text"),
      tableOutput("data_table")
    )
  )
)

server <- function(input, output, session) {
  selected_data <- reactive({
    head(get(input$dataset, envir = asNamespace("datasets")), input$obs)
  })

  output$summary_text <- renderText({
    paste("Showing", nrow(selected_data()), "rows of", input$dataset)
  })

  output$data_table <- renderTable({
    selected_data()
  })
}

shinyApp(ui, server)
