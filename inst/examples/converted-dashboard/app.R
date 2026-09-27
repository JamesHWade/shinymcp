# The Shiny app in original-app.R, rewritten as a tool.
#
# as_mcp_app() could serve original-app.R as it is. Rewriting it as tools
# is the other route: the reactive graph becomes one R function, and the
# app keeps no state between calls, so it runs in any number of processes
# and its tool is useful to clients that can't show apps.
#
# convert_app() writes the first draft of a file like this one; see
# vignette("rewriting-as-tools").
#
# Preview it:
#   shinymcp::preview_app(system.file("examples", "converted-dashboard", "app.R", package = "shinymcp"))

library(shinymcp)

ui <- htmltools::tagList(
  htmltools::h2("Simple dashboard"),
  mcp_select("dataset", "Dataset", c("mtcars", "iris")),
  mcp_numeric_input("obs", "Observations", value = 10, min = 1, max = 50),
  mcp_text("summary_text"),
  mcp_table("data_table")
)

# The two outputs share one reactive in the original, so they become one
# tool that returns both.
update_dashboard <- ellmer::tool(
  function(dataset = "mtcars", obs = 10) {
    data <- utils::head(getExportedValue("datasets", dataset), obs)
    list(
      summary_text = paste("Showing", nrow(data), "rows of", dataset),
      data_table = data
    )
  },
  name = "update_dashboard",
  description = "Show the first rows of a built-in dataset.",
  arguments = list(
    dataset = ellmer::type_enum(c("mtcars", "iris"), "Dataset to show."),
    obs = ellmer::type_integer("Number of rows, 1 to 50.", required = FALSE)
  ),
  annotations = ellmer::tool_annotations(read_only_hint = TRUE)
)

app <- mcp_app(ui, tools = list(update_dashboard), name = "converted-dashboard")

if (interactive()) preview_app(app) else serve(app)
