# Minimal MCP App example with bslib theming
library(shinymcp)
library(bslib)
library(htmltools)

ui <- page(
  theme = bs_theme(preset = "shiny"),
  card(
    card_header("Dataset Explorer"),
    layout_columns(
      col_widths = c(4, 8),
      mcp_select("dataset", "Choose dataset", c("mtcars", "iris", "pressure")),
      mcp_text("summary")
    )
  )
)

tools <- list(
  ellmer::tool(
    fun = function(dataset = "mtcars") {
      data <- get(dataset, envir = asNamespace("datasets"))
      paste(capture.output(summary(data)), collapse = "\n")
    },
    name = "get_summary",
    description = "Get summary statistics for the selected dataset",
    arguments = list(
      dataset = ellmer::type_string("Dataset name")
    )
  )
)

app <- mcp_app(ui, tools, name = "hello-mcp")
serve(app)
