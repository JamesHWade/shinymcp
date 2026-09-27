# An MCP App inside a Shiny app.
#
# mcp_host_ui() and mcp_host_server() show an app exactly as a chat client
# would: in a sandboxed frame, with its tool calls answered in R. The
# surrounding Shiny app can watch what happens in it: the context the app
# publishes for the model, and every tool call.
#
#   shiny::runApp(system.file("examples", "shiny-host", package = "shinymcp"))

library(shiny)
library(bslib)
library(shinymcp)

cars_app <- as_mcp_app(
  shinyApp(
    fluidPage(
      selectInput("cyl", "Cylinders", c(4, 6, 8)),
      plotOutput("scatter", height = "280px"),
      textOutput("count")
    ),
    function(input, output, session) {
      cars <- reactive(mtcars[mtcars$cyl == input$cyl, ])
      output$scatter <- renderPlot(
        plot(cars()$wt, cars()$mpg, pch = 19, xlab = "Weight (1000 lb)", ylab = "Miles per gallon")
      )
      output$count <- renderText(paste(nrow(cars()), "cars"))
    }
  ),
  name = "cars",
  title = "Cars by cylinders"
)

ui <- page_sidebar(
  title = "Reviewing an MCP App",
  sidebar = sidebar(
    width = 360,
    h6("What the model would be told"),
    verbatimTextOutput("context"),
    h6("Latest tool call"),
    verbatimTextOutput("call")
  ),
  card(
    card_header("The app, as a chat client shows it"),
    mcp_host_ui("cars")
  )
)

server <- function(input, output, session) {
  host <- mcp_host_server("cars", cars_app, arguments = list(cyl = 6))

  output$context <- renderText({
    context <- host$model_context()
    if (is.null(context)) {
      "Nothing yet. Change the input in the app."
    } else {
      paste(vapply(context$content, function(block) block$text, ""), collapse = "\n")
    }
  })

  output$call <- renderText({
    call <- host$last_tool_call()
    if (is.null(call)) {
      return("None yet.")
    }
    text <- unlist(lapply(call$result$content, function(block) block$text))
    paste0(call$name, "\n\n", paste(text, collapse = "\n"))
  })
}

shinyApp(ui, server)
