# One deployment for people and for chat clients.
#
# mcp_endpoint() returns the Shiny app with an MCP endpoint added at /mcp.
# Deploy this file like any Shiny app. Browsers get the app as before;
# MCP clients connect to https://<your-server>/<app-path>/mcp and get the
# same app, live, inside the chat.
#
# See README.md in this folder for deploying to Posit Connect and
# connecting clients.

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
  output$histogram <- renderPlot({
    breaks <- seq(min(faithful$waiting), max(faithful$waiting), length.out = input$bins + 1)
    hist(faithful$waiting, breaks = breaks, col = "#5b8db8", border = "white",
      main = NULL, xlab = "Minutes to the next eruption")
  })
  output$caption <- renderText({
    # On Posit Connect, the signed-in viewer (in the browser) or the owner of
    # the API key (from a chat client) is session$user.
    who <- if (is.null(session$user)) "you" else session$user
    sprintf("Showing %d eruptions to %s.", nrow(faithful), who)
  })
}

shinyApp(ui, server) |>
  mcp_endpoint(
    name = "faithful",
    title = "Old Faithful",
    description = "Show a histogram of waiting times between Old Faithful eruptions."
  )
