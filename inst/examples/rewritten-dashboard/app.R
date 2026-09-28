# The Shiny app in original-app.R, rewritten as a tool.
#
# The UI is the original's, unchanged. The server function became one R
# function: both outputs came from the same reactive expression, so one
# tool returns both. The app keeps nothing between calls, so it runs in any
# number of processes, and its tool is useful in clients that can't show
# apps. See vignette("rewriting-as-tools").
#
# Preview it:
#   shinymcp::preview_app(system.file("examples", "rewritten-dashboard", "app.R", package = "shinymcp"))

library(shiny)
library(shinymcp)

ui <- fluidPage(
  titlePanel("Simple Dashboard"),
  sidebarLayout(
    sidebarPanel(
      selectInput("dataset", "Dataset:", c("mtcars", "iris")),
      numericInput("obs", "Observations:", 10, min = 1, max = 50)
    ),
    mainPanel(
      textOutput("summary_text"),
      tableOutput("data_table")
    )
  )
)

show_dataset <- ellmer::tool(
  function(dataset = "mtcars", obs = 10) {
    data <- utils::head(getExportedValue("datasets", dataset), obs)
    list(
      summary_text = paste("Showing", nrow(data), "rows of", dataset),
      data_table = data
    )
  },
  name = "show_dataset",
  description = "Show the first rows of one of R's built-in datasets.",
  arguments = list(
    dataset = ellmer::type_enum(
      c("mtcars", "iris"),
      "Dataset to show.",
      required = FALSE
    ),
    obs = ellmer::type_integer("Number of rows, 1 to 50.", required = FALSE)
  ),
  annotations = ellmer::tool_annotations(read_only_hint = TRUE)
)

app <- mcp_app(ui, tools = list(show_dataset), name = "dashboard")

if (interactive()) preview_app(app) else serve(app)
