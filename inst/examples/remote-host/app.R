# An MCP App from another server, in a Shiny app.
#
# mcp_client() connects to any MCP server, and mcp_host_server() shows its
# app in a pane. The connection stays in R: the app's page never talks to
# its server, and the browser never sees a key.
#
# Start the server first, in another R session, from this folder:
#   Rscript serve.R
# then run this app:
#   shiny::runApp(system.file("examples", "remote-host", package = "shinymcp"))
#
# To host something else, set MCP_URL: an app on Posit Connect (with
# CONNECT_API_KEY set), or a Shiny app served with Shiny's MCP support.

library(shiny)
library(bslib)
library(shinymcp)

url <- Sys.getenv("MCP_URL", "http://127.0.0.1:8080/mcp")

ui <- page_sidebar(
  title = "An app from another server",
  sidebar = sidebar(
    width = 340,
    sliderInput(
      "bins",
      "Open it with",
      min = 5,
      max = 50,
      value = 20,
      post = " bins"
    ),
    h6("What the model would be told"),
    verbatimTextOutput("context"),
    h6("Latest tool call"),
    verbatimTextOutput("call")
  ),
  card(card_header(url), mcp_host_ui("remote"))
)

server <- function(input, output, session) {
  key <- Sys.getenv("CONNECT_API_KEY")
  client <- mcp_client(
    url,
    headers = if (nzchar(key)) list(Authorization = paste("Key", key))
  )
  host <- mcp_host_server("remote", client, arguments = list(bins = 20))

  observeEvent(
    input$bins,
    host$open(list(bins = input$bins)),
    ignoreInit = TRUE
  )

  output$context <- renderText({
    context <- host$model_context()
    if (is.null(context)) {
      "Nothing yet. Change something in the app."
    } else {
      paste(
        vapply(context$content, function(block) block$text, ""),
        collapse = "\n"
      )
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
