# Converted from Shiny dashboard to MCP App
library(shinymcp)

ui <- htmltools::tagList(
  htmltools::h2("Simple Dashboard"),
  mcp_select("dataset", "Dataset:", c("mtcars", "iris")),
  mcp_numeric_input("obs", "Observations:", value = 10, min = 1, max = 50),
  mcp_text("summary_text"),
  mcp_table("data_table")
)

tools <- list(
  ellmer::tool(
    fun = function(dataset = "mtcars", obs = 10) {
      data <- head(
        get(dataset, envir = asNamespace("datasets")),
        as.integer(obs)
      )
      list(
        summary_text = paste("Showing", nrow(data), "rows of", dataset),
        data_table = paste(
          capture.output(print(
            htmltools::tags$table(
              htmltools::tags$thead(htmltools::tags$tr(lapply(
                names(data),
                htmltools::tags$th
              ))),
              htmltools::tags$tbody(
                lapply(seq_len(nrow(data)), function(i) {
                  htmltools::tags$tr(lapply(data[i, ], function(x) {
                    htmltools::tags$td(as.character(x))
                  }))
                })
              )
            )
          )),
          collapse = "\n"
        )
      )
    },
    name = "update_dashboard",
    description = "Update dashboard with selected dataset and observation count",
    arguments = list(
      dataset = ellmer::type_string("Dataset name: 'mtcars' or 'iris'"),
      obs = ellmer::type_number("Number of observations to show")
    )
  )
)

app <- mcp_app(ui, tools, name = "converted-dashboard")
serve(app)
