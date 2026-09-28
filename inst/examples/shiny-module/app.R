# A Shiny module served as an MCP App.
#
# mcp_tool_module() runs the module live, as as_mcp_app() runs a whole app.
# The model sets the module's inputs by their own ids ("dataset", "bins"),
# without the namespace. The same module still works inside any Shiny app,
# and in a shinychat conversation through shinychat::chat_tool_module().
#
# Preview it:
#   shinymcp::preview_app(system.file("examples", "shiny-module", "app.R", package = "shinymcp"))

library(shiny)
library(shinymcp)

histogram_ui <- function(id) {
  ns <- NS(id)
  tagList(
    selectInput(
      ns("dataset"),
      "Variable",
      c(
        "Old Faithful eruption length (minutes)" = "eruptions",
        "Old Faithful waiting time (minutes)" = "waiting",
        "Fuel economy (mpg)" = "mpg"
      )
    ),
    sliderInput(ns("bins"), "Bins", min = 5, max = 50, value = 20),
    plotOutput(ns("plot"), height = "280px"),
    verbatimTextOutput(ns("stats"))
  )
}

histogram_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    values <- reactive(switch(
      input$dataset,
      eruptions = faithful$eruptions,
      waiting = faithful$waiting,
      mpg = mtcars$mpg
    ))

    output$plot <- renderPlot({
      par(mar = c(4, 4, 1, 1))
      hist(
        values(),
        breaks = input$bins,
        col = "#5b8db8",
        border = "white",
        main = NULL,
        xlab = NULL
      )
    })

    output$stats <- renderPrint(summary(values()))
  })
}

app <- mcp_tool_module(
  histogram_ui,
  histogram_server,
  name = "histogram",
  description = "Draw a histogram of Old Faithful eruptions or of car fuel economy."
)

if (interactive()) {
  preview_app(app)
} else {
  serve(app)
}
