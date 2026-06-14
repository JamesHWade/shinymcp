# embed-in-shiny — Shiny as the review surface for an MCP App.
#
# Define the MCP App once (the same object you would serve to a client), then host
# it inside a Shiny dashboard with mcp_host_ui()/mcp_host_server(). The card runs
# the real tool; the surrounding Shiny app is where a reviewer inspects it.
library(shiny)
library(bslib)
library(shinymcp)

greet_app <- mcp_app(
  ui = htmltools::tagList(
    mcp_text_input("name", "Your name", value = "world"),
    mcp_text("greeting")
  ),
  tools = list(
    ellmer::tool(
      fun = function(name = "world") {
        list(greeting = paste0("Hello, ", name, "!"))
      },
      name = "greet",
      description = "Greet a person by name",
      arguments = list(
        name = ellmer::type_string("The name to greet")
      )
    )
  ),
  name = "greet"
)

ui <- page_sidebar(
  title = "An MCP App embedded in Shiny",
  sidebar = sidebar(
    htmltools::p(
      "The card on the right is the same MCP App you would serve to a client. ",
      "Here it runs inside Shiny, which is a convenient place to review it."
    )
  ),
  card(
    card_header("Embedded MCP App"),
    mcp_host_ui("greet")
  )
)

server <- function(input, output, session) {
  mcp_host_server("greet", greet_app, trigger = "change")
}

shinyApp(ui, server)
