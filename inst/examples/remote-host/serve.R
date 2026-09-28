# The server for the remote-host example: an MCP App served over HTTP, the
# way it would be from Posit Connect. Run it in its own R session, from this
# folder:
#
#   Rscript serve.R

library(shiny)
library(shinymcp)

histogram <- ellmer::tool(
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
      summary = sprintf(
        "%d eruptions, a median wait of %.0f minutes.",
        nrow(faithful),
        median(faithful$waiting)
      )
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
  fluidPage(
    sliderInput("bins", "Number of bins", min = 5, max = 50, value = 20),
    plotOutput("histogram", height = "300px"),
    textOutput("summary")
  ),
  tools = list(histogram),
  name = "faithful",
  title = "Old Faithful"
)

serve(faithful_app, type = "http", port = 8080)
