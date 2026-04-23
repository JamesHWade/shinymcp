library(shiny)
library(bslib)
library(ellmer)
library(shinychat)
library(shinymcp)

card_app <- mcp_app(
  ui = htmltools::tagList(
    mcp_select("dataset", "Dataset", c("mtcars", "iris", "pressure")),
    mcp_text("summary"),
    mcp_plot("plot", height = "220px")
  ),
  tools = list(
    list(
      name = "inspect_dataset",
      description = "Inspect a small built-in dataset",
      inputSchema = list(
        type = "object",
        properties = list(
          dataset = list(type = "string")
        )
      ),
      fun = function(dataset = "mtcars") {
        data <- get(dataset, envir = asNamespace("datasets"))
        summary_text <- paste(capture.output(summary(data)), collapse = "\n")

        list(
          summary = summary_text,
          plot = mcp_result_plot(
            function() {
              numeric_cols <- names(data)[vapply(data, is.numeric, logical(1))]
              if (length(numeric_cols) >= 2) {
                plot(
                  data[[numeric_cols[1]]],
                  data[[numeric_cols[2]]],
                  xlab = numeric_cols[1],
                  ylab = numeric_cols[2],
                  main = dataset,
                  col = "steelblue",
                  pch = 19
                )
              } else {
                plot.new()
                text(0.5, 0.5, dataset)
              }
            },
            text = paste("Scatter plot for", dataset)
          )
        )
      }
    )
  ),
  name = "shinychat-card-demo"
)

inspect_dataset <- as_shinychat_tool(
  card_app,
  value_fn = function(raw_result) list(summary = raw_result$summary),
  summary = function(raw_result) raw_result$summary,
  title = "Dataset Inspector"
)

ui <- page_fillable(
  fillable_mobile = TRUE,
  chat_mod_ui("chat")
)

server <- function(input, output, session) {
  client <- ellmer::chat("openai/gpt-4.1-nano")
  client$register_tool(inspect_dataset)
  chat_mod_server("chat", client)
}

shinyApp(ui, server)
