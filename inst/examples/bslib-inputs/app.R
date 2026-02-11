# Demonstrates auto-detection of native bslib/shiny inputs.
#
# The bridge reads tool argument names from config.toolArgs and matches them
# to DOM elements by id. No mcp_select() wrappers needed — just ensure the
# element id matches the tool argument name.
#
# Also shows mcp_input() / mcp_output() escape hatches for edge cases.
library(shinymcp)
library(bslib)
library(htmltools)

ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "Auto-Detect Demo",
  sidebar = sidebar(
    # Native shiny inputs — ids match tool argument names, auto-detected
    shiny::selectInput("dataset", "Dataset", c("mtcars", "iris", "pressure")),
    shiny::numericInput("n", "Rows to show", value = 10, min = 1, max = 50),

    # mcp_input() escape hatch: id on inner element doesn't match arg name,
    # so we explicitly stamp the attribute
    mcp_input(
      shiny::radioButtons("format", "Format", c("summary", "head")),
      id = "format"
    )
  ),
  card(
    card_header("Result"),
    # mcp_output() escape hatch: turn any tag into an output target
    mcp_output(tags$pre(id = "result", style = "white-space: pre-wrap;"))
  )
)

tools <- list(
  ellmer::tool(
    fun = function(dataset = "mtcars", n = 10, format = "summary") {
      data <- get(dataset, envir = asNamespace("datasets"))
      result <- if (format == "summary") {
        paste(capture.output(summary(data)), collapse = "\n")
      } else {
        paste(capture.output(print(head(data, as.integer(n)))), collapse = "\n")
      }
      list(result = result)
    },
    name = "get_data",
    description = "Get dataset summary or first N rows",
    arguments = list(
      dataset = ellmer::type_string("Dataset name"),
      n = ellmer::type_number("Number of rows for 'head' format"),
      format = ellmer::type_string("Output format: 'summary' or 'head'")
    )
  )
)

app <- mcp_app(ui, tools, name = "bslib-inputs-demo")
serve(app)
