# bindMcp() demo — annotate a standard Shiny app for MCP exposure
#
# This example shows how to take a regular Shiny app and selectively
# expose inputs and outputs as MCP endpoints using |> bindMcp().
#
# Only the annotated elements are visible to the AI agent.
# The "n" input is deliberately NOT annotated — it works in the
# Shiny app but is invisible to MCP.

library(shiny)
library(shinymcp)
library(bslib)

# --- Standard Shiny UI with bindMcp() annotations ---

ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "Dataset Explorer",
  sidebar = sidebar(
    # This input IS exposed to MCP
    selectInput("dataset", "Dataset:", c("mtcars", "iris", "pressure")) |>
      bindMcp(),

    # This input is NOT exposed to MCP (no bindMcp)
    numericInput("n", "Rows to show:", value = 10, min = 1, max = 50)
  ),
  card(
    card_header("Results"),
    # Both outputs ARE exposed to MCP
    plotOutput("plot") |> bindMcp(),
    verbatimTextOutput("summary") |> bindMcp()
  )
)

# --- Standard Shiny server ---

server <- function(input, output, session) {
  data <- reactive({
    head(get(input$dataset, envir = asNamespace("datasets")), input$n)
  })

  output$plot <- renderPlot({
    d <- data()
    numeric_cols <- names(d)[vapply(d, is.numeric, logical(1))]
    if (length(numeric_cols) >= 2) {
      plot(d[[numeric_cols[1]]], d[[numeric_cols[2]]],
        xlab = numeric_cols[1], ylab = numeric_cols[2],
        main = input$dataset, pch = 19,
        col = adjustcolor("steelblue", 0.6)
      )
    }
  })

  output$summary <- renderText({
    paste(capture.output(summary(data())), collapse = "\n")
  })
}

# --- Two ways to run ---

# As a regular Shiny app:
# shinyApp(ui, server)

# As an MCP App (with explicit tool handler):
app <- shinyApp(ui, server) |>
  as_mcp_app(
    name = "dataset-explorer",
    tools = list(
      ellmer::tool(
        fun = function(dataset = "mtcars") {
          data <- get(dataset, envir = asNamespace("datasets"))

          summary_text <- paste(capture.output(summary(data)), collapse = "\n")

          numeric_cols <- names(data)[vapply(data, is.numeric, logical(1))]
          tmp <- tempfile(fileext = ".png")
          grDevices::png(tmp, width = 600, height = 280, res = 96)
          on.exit(unlink(tmp))
          par(mar = c(4, 4, 2, 1))
          if (length(numeric_cols) >= 2) {
            plot(data[[numeric_cols[1]]], data[[numeric_cols[2]]],
              xlab = numeric_cols[1], ylab = numeric_cols[2],
              main = dataset, pch = 19,
              col = adjustcolor("steelblue", 0.6)
            )
          }
          grDevices::dev.off()

          list(summary = summary_text, plot = base64enc::base64encode(tmp))
        },
        name = "explore_dataset",
        description = "Explore a dataset with summary statistics and scatter plot",
        arguments = list(
          dataset = ellmer::type_string("Dataset name: mtcars, iris, or pressure")
        )
      )
    )
  )

serve(app)
