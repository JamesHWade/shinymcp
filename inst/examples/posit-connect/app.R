# One deployment for people and for chat clients.
#
# The Shiny app is for people in a browser. For chat clients, the same UI
# runs on a tool instead of a server function: mcp_endpoint() serves that
# app at /mcp, next to the Shiny app. Both draw with the same function, so
# they agree.
#
# Deploy this file like any Shiny app; MCP clients connect to
# https://<your-server>/<app-path>/mcp. See README.md in this folder for
# deploying to Posit Connect and connecting clients.

library(shiny)
library(shinymcp)

draw_histogram <- function(bins) {
  breaks <- seq(
    min(faithful$waiting),
    max(faithful$waiting),
    length.out = bins + 1
  )
  hist(
    faithful$waiting,
    breaks = breaks,
    col = "#5b8db8",
    border = "white",
    main = NULL,
    xlab = "Minutes to the next eruption"
  )
}

caption <- function(user) {
  who <- if (is.null(user)) "you" else user
  sprintf("Showing %d eruptions to %s.", nrow(faithful), who)
}

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

# For people, in a browser.
server <- function(input, output, session) {
  output$histogram <- renderPlot(draw_histogram(input$bins))
  # On Posit Connect, session$user is the signed-in viewer.
  output$caption <- renderText(caption(session$user))
}

# For chat clients: a tool with the input's name for an argument, returning
# values with the outputs' names.
histogram <- ellmer::tool(
  function(bins = 20) {
    list(
      histogram = mcp_result_plot(
        function() draw_histogram(bins),
        text = "Histogram of waiting times between Old Faithful eruptions."
      ),
      # From a chat client, the owner of the API key.
      caption = caption(mcp_request()$user)
    )
  },
  name = "faithful_histogram",
  description = "Show a histogram of waiting times between Old Faithful eruptions.",
  arguments = list(
    bins = ellmer::type_integer("Number of bins, 5 to 50.", required = FALSE)
  ),
  annotations = ellmer::tool_annotations(read_only_hint = TRUE)
)

faithful_app <- mcp_app(
  ui,
  tools = list(histogram),
  name = "faithful",
  title = "Old Faithful"
)

shinyApp(ui, server) |> mcp_endpoint(apps = faithful_app)
