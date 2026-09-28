# The smallest MCP App: one input, one tool, one output.
#
# The model calls `summarize_dataset`, the chat shows the card, and the
# person using it can pick another dataset without asking the model again.
#
# Preview it in a browser:
#   shinymcp::preview_app(system.file("examples", "hello", "app.R", package = "shinymcp"))
#
# Or add it to Claude Desktop (see the serve-to-client example):
#   Rscript app.R

library(shinymcp)

datasets <- c("mtcars", "faithful", "airquality", "pressure")

ui <- htmltools::tagList(
  mcp_select("dataset", "Dataset", datasets),
  mcp_text("summary")
)

summarize_dataset <- ellmer::tool(
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
)

app <- mcp_app(
  ui,
  tools = list(summarize_dataset),
  name = "hello",
  title = "Dataset summary"
)

if (interactive()) {
  preview_app(app)
} else {
  serve(app)
}
