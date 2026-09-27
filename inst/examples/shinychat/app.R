# MCP Apps as shinychat tool results.
#
# as_shinychat_tool() turns an app's tools into ellmer tools. When the model
# calls one, shinychat shows the app, live, in the tool's card; the model
# gets the tool's text and structured result.
#
# Needs an API key for the model you choose (here ANTHROPIC_API_KEY).
#   shiny::runApp(system.file("examples", "shinychat", package = "shinymcp"))

library(shiny)
library(bslib)
library(shinychat)
library(shinymcp)

# A Shiny app, served live in the chat.
faithful_app <- as_mcp_app(
  shinyApp(
    fluidPage(
      sliderInput("bins", "Number of bins", min = 5, max = 50, value = 20),
      plotOutput("histogram", height = "300px")
    ),
    function(input, output, session) {
      output$histogram <- renderPlot({
        hist(
          faithful$waiting,
          breaks = input$bins,
          col = "#5b8db8",
          border = "white",
          main = NULL,
          xlab = "Minutes to the next eruption"
        )
      })
    }
  ),
  name = "faithful",
  title = "Old Faithful",
  description = "Show a histogram of waiting times between Old Faithful eruptions."
)

# An app built from a tool.
datasets <- c("mtcars", "faithful", "airquality", "pressure")
summary_app <- mcp_app(
  htmltools::tagList(
    mcp_select("dataset", "Dataset", datasets),
    mcp_text("summary")
  ),
  tools = list(ellmer::tool(
    function(dataset = "mtcars") {
      data <- getExportedValue("datasets", dataset)
      list(summary = paste(utils::capture.output(summary(data)), collapse = "\n"))
    },
    name = "summarize_dataset",
    description = "Summarize one of R's built-in datasets, column by column.",
    arguments = list(dataset = ellmer::type_enum(datasets, "The dataset to summarize.")),
    annotations = ellmer::tool_annotations(read_only_hint = TRUE)
  )),
  name = "dataset-summary",
  title = "Dataset summary"
)

ui <- page_fillable(
  chat_ui(
    "chat",
    greeting = "Ask for **a histogram of Old Faithful waiting times** or **a summary of airquality**."
  )
)

server <- function(input, output, session) {
  client <- ellmer::chat("anthropic/claude-sonnet-5")
  client$register_tool(as_shinychat_tool(faithful_app))
  client$register_tool(as_shinychat_tool(summary_app))
  chat_server("chat", client)
}

shinyApp(ui, server)
