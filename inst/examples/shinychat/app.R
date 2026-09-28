# MCP Apps in a shinychat conversation.
#
# mcp_chat_host() gives the model the apps' tools. When it calls one,
# shinychat shows the app, live, in the tool's card. What the person then
# does in a card reaches the model with their next message, and a message an
# app suggests goes into the input box.
#
# Needs an API key for the model you choose (here ANTHROPIC_API_KEY).
#   shiny::runApp(system.file("examples", "shinychat", package = "shinymcp"))

library(shiny)
library(bslib)
library(shinychat)
library(shinymcp)

# A histogram, with a slider for the number of bins.
faithful_app <- mcp_app(
  fluidPage(
    sliderInput("bins", "Number of bins", min = 5, max = 50, value = 20),
    plotOutput("histogram", height = "300px")
  ),
  tools = list(ellmer::tool(
    function(bins = 20) {
      list(
        histogram = mcp_result_plot(
          function() {
            hist(
              faithful$waiting,
              breaks = bins,
              col = "#5b8db8",
              border = "white",
              main = NULL,
              xlab = "Minutes to the next eruption"
            )
          },
          text = "Histogram of waiting times between Old Faithful eruptions."
        )
      )
    },
    name = "faithful_histogram",
    description = "Show a histogram of waiting times between Old Faithful eruptions.",
    arguments = list(
      bins = ellmer::type_integer("Number of bins, 5 to 50.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(read_only_hint = TRUE)
  )),
  name = "faithful",
  title = "Old Faithful"
)

# A summary of a dataset, with a select input to choose it.
datasets <- c("mtcars", "faithful", "airquality", "pressure")
summary_app <- mcp_app(
  htmltools::tagList(
    mcp_select("dataset", "Dataset", datasets),
    mcp_text("summary")
  ),
  tools = list(ellmer::tool(
    function(dataset = "mtcars") {
      data <- getExportedValue("datasets", dataset)
      list(
        summary = paste(utils::capture.output(summary(data)), collapse = "\n")
      )
    },
    name = "summarize_dataset",
    description = "Summarize one of R's built-in datasets, column by column.",
    arguments = list(
      dataset = ellmer::type_enum(datasets, "The dataset to summarize.")
    ),
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
  chat <- chat_server("chat", ellmer::chat("anthropic/claude-sonnet-5"))
  mcp_chat_host(chat, list(faithful_app, summary_app))
}

shinyApp(ui, server)
