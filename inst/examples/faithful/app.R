# An ordinary Shiny app, served as an MCP App without changes.
#
# as_mcp_app() keeps the server function running in R: each time the app
# opens in a chat, it gets its own session, and the slider talks to that
# session the way it would in a browser. The model gets one tool,
# `faithful`, whose argument is the slider, so it can open the app already
# set up ("show me the eruptions with 40 bins").
#
# Preview it:
#   shinymcp::preview_app(system.file("examples", "faithful", "app.R", package = "shinymcp"))
#
# The same file still runs as a Shiny app with shiny::runApp().

library(shiny)
library(shinymcp)

ui <- fluidPage(
  titlePanel("Old Faithful eruptions"),
  sidebarLayout(
    sidebarPanel(
      sliderInput("bins", "Number of bins", min = 5, max = 50, value = 20)
    ),
    mainPanel(
      plotOutput("histogram"),
      textOutput("caption")
    )
  )
)

server <- function(input, output, session) {
  waiting <- faithful$waiting

  output$histogram <- renderPlot({
    breaks <- seq(min(waiting), max(waiting), length.out = input$bins + 1)
    hist(
      waiting,
      breaks = breaks,
      col = "#5b8db8",
      border = "white",
      main = NULL,
      xlab = "Minutes to the next eruption"
    )
  })

  output$caption <- renderText({
    sprintf(
      "%d eruptions; the median wait was %d minutes.",
      length(waiting),
      stats::median(waiting)
    )
  })
}

shiny_app <- shinyApp(ui, server)

app <- as_mcp_app(
  shiny_app,
  name = "faithful",
  title = "Old Faithful",
  description = "Show a histogram of waiting times between Old Faithful eruptions."
)

if (interactive()) {
  preview_app(app)
} else {
  serve(app)
}
