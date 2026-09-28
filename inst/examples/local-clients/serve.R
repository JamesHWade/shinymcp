# An MCP server for desktop clients, over stdio.
#
# A client such as Claude Desktop starts this script and talks to it on
# stdin and stdout. See README.md for the client settings. Nothing here is
# specific to stdio except the last line; the apps are the same ones you
# would preview with preview_app().

library(shiny)
library(shinymcp)

# A histogram, with a slider for the number of bins.
faithful_app <- mcp_app(
  fluidPage(
    sliderInput("bins", "Number of bins", min = 5, max = 50, value = 20),
    plotOutput("histogram"),
    textOutput("caption")
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
        ),
        caption = sprintf("%d eruptions.", nrow(faithful))
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
      list(summary = paste(utils::capture.output(summary(data)), collapse = "\n"))
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

# One server, both apps. Messages from R (warnings, cat() in your code) go
# to stderr, which clients keep in their logs; stdout carries the protocol.
serve(list(faithful_app, summary_app))
