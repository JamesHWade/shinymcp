# mcp_tool_module() demo — wrap a Shiny module as an MCP App
#
# Shows how a standard Shiny module (ui + server) can be served as an
# MCP App using mcp_tool_module(). The same module could also be used
# with shinychat::chat_tool_module() in a chat interface.

library(shiny)
library(shinymcp)
library(bslib)

# --- A standard Shiny module ---

hist_ui <- function(id) {
  ns <- NS(id)
  page(
    theme = bs_theme(preset = "shiny"),
    card(
      card_header("Interactive Histogram"),
      layout_columns(
        col_widths = c(4, 8),
        tagList(
          selectInput(ns("dataset"), "Dataset:",
            c("faithful" = "faithful", "mtcars" = "mtcars")
          ),
          sliderInput(ns("bins"), "Bins:", min = 5, max = 50, value = 25)
        ),
        plotOutput(ns("plot"), height = "280px")
      )
    )
  )
}

hist_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    output$plot <- renderPlot({
      data <- if (input$dataset == "faithful") {
        faithful$eruptions
      } else {
        mtcars$mpg
      }
      hist(data, breaks = input$bins, col = "#007bc2", border = "white",
        main = paste(input$dataset, "histogram"))
    })
  })
}

# --- Serve as MCP App ---

app <- mcp_tool_module(
  module_ui = hist_ui,
  module_server = hist_server,
  name = "histogram",
  description = "Show an interactive histogram with adjustable bins",
  handler = function(dataset = "faithful", bins = 25) {
    data <- if (dataset == "faithful") faithful$eruptions else mtcars$mpg
    tmp <- tempfile(fileext = ".png")
    grDevices::png(tmp, width = 600, height = 280, res = 96)
    on.exit(unlink(tmp))
    par(mar = c(4, 4, 2, 1))
    hist(data, breaks = as.integer(bins), col = "#007bc2", border = "white",
      main = paste(dataset, "histogram"))
    grDevices::dev.off()
    list(plot = base64enc::base64encode(tmp))
  },
  arguments = list(
    dataset = ellmer::type_string("Dataset: 'faithful' or 'mtcars'"),
    bins = ellmer::type_number("Number of histogram bins")
  )
)

serve(app)
