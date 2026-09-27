# A Shiny app built on packages that talk to Shiny's JavaScript, served live.
#
# - shinyWidgets' picker registers its own input binding; the page uses it.
# - DT reports the rows the person selects with Shiny.setInputValue(), so
#   input$cars_rows_selected works as it does in a browser.
# - fileInput() uploads the file to the view's session in R.
# - mcp_model_context() tells the model which cars the person selected,
#   so it can talk about them on its next turn.
#
# Preview it:
#   shinymcp::preview_app(system.file("examples", "shiny-packages", "app.R", package = "shinymcp"))

library(shiny)
library(shinymcp)

cars <- data.frame(model = rownames(mtcars), mtcars[c("mpg", "cyl", "hp", "wt")])
rownames(cars) <- NULL

ui <- fluidPage(
  titlePanel("Motor Trend cars"),
  sidebarLayout(
    sidebarPanel(
      shinyWidgets::pickerInput(
        "cyl",
        "Cylinders",
        choices = c(4, 6, 8),
        selected = c(4, 6, 8),
        multiple = TRUE
      ),
      fileInput(
        "upload",
        "Your own cars (CSV with model, mpg, cyl, hp, and wt)",
        accept = ".csv"
      )
    ),
    mainPanel(
      DT::DTOutput("table"),
      textOutput("selection")
    )
  )
)

server <- function(input, output, session) {
  data <- reactive({
    if (is.null(input$upload)) {
      return(cars)
    }
    read.csv(input$upload$datapath)
  })

  shown <- reactive({
    d <- data()
    d[d$cyl %in% as.numeric(input$cyl), , drop = FALSE]
  })

  output$table <- DT::renderDT(
    shown(),
    rownames = FALSE,
    options = list(pageLength = 8, dom = "tp")
  )

  selected <- reactive(shown()[input$table_rows_selected, , drop = FALSE])

  output$selection <- renderText({
    if (nrow(selected()) == 0) {
      return("Select rows to compare them.")
    }
    sprintf(
      "%d selected, averaging %.1f mpg and %.0f hp.",
      nrow(selected()),
      mean(selected()$mpg),
      mean(selected()$hp)
    )
  })

  observe({
    if (nrow(selected()) == 0) {
      return()
    }
    mcp_model_context(
      text = paste0(
        "The user selected these cars: ",
        paste(selected()$model, collapse = ", "),
        "."
      ),
      data = list(selected = selected()$model)
    )
  })
}

app <- as_mcp_app(
  shinyApp(ui, server),
  name = "cars",
  title = "Motor Trend cars",
  description = "Browse the 1974 Motor Trend cars by number of cylinders, select cars in the table to compare them, or upload your own."
)

if (interactive()) preview_app(app) else serve(app)
