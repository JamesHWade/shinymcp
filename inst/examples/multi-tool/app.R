# Multi-Tool MCP App
#
# Demonstrates two improvements to shinymcp's reactive graph handling:
#
# 1. **Chained reactives**: `filtered_data` depends on `base_data`, which
#    depends on `input$dataset`. The analyzer now traces this transitive
#    chain so that `dataset` is correctly included in the tool arguments
#    even though `filtered_data` doesn't reference `input$dataset` directly.
#
# 2. **Multiple independent tools**: The data exploration tool and the
#    greeting tool are separate connected components. The JS bridge now
#    routes input changes to only the affected tool(s) instead of calling
#    a single hardcoded tool.
#
# Original Shiny app: original-app.R

library(shinymcp)

# --- UI ---
ui <- htmltools::tagList(
  htmltools::h2("Multi-Tool Demo"),


  # Group 1: data exploration
  htmltools::h3("Data Explorer"),
  shiny::selectInput("dataset", "Dataset:", c("mtcars", "iris", "pressure")),
  shiny::numericInput("n_rows", "Rows:", 10, min = 1, max = 50),
  shiny::selectInput("sort_col", "Sort by:", c("default")),
  mcp_text("summary"),
  mcp_plot("plot"),

  htmltools::hr(),

  # Group 2: greeting (independent)
  htmltools::h3("Greeting"),
  shiny::textInput("user_name", "Your name:"),
  mcp_text("greeting")
)

# --- Tools ---
explore_data <- ellmer::tool(
  fun = function(dataset, n_rows, sort_col) {
    full <- get(dataset, envir = asNamespace("datasets"))
    d <- utils::head(full, as.integer(n_rows))
    if (sort_col != "default" && sort_col %in% names(d)) {
      d <- d[order(d[[sort_col]]), ]
    }

    # Plot
    tmp <- tempfile(fileext = ".png")
    grDevices::png(tmp, width = 600, height = 400)
    on.exit(unlink(tmp), add = TRUE)
    if (ncol(d) >= 2) {
      plot(d[[1]], d[[2]],
        xlab = names(d)[1], ylab = names(d)[2],
        main = dataset
      )
    }
    grDevices::dev.off()
    raw <- readBin(tmp, "raw", file.info(tmp)$size)
    plot_b64 <- base64enc::base64encode(raw)

    list(
      summary = paste(
        "Showing", nrow(d), "of", nrow(full), "rows from", dataset
      ),
      plot = plot_b64
    )
  },
  name = "update_summary_and_plot",
  description = "Explore a dataset: filter rows, sort, and visualise",
  arguments = list(
    dataset = ellmer::type_string("Dataset name"),
    n_rows = ellmer::type_number("Number of rows to show"),
    sort_col = ellmer::type_string("Column to sort by")
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    idempotent_hint = TRUE
  )
)

greet <- ellmer::tool(
  fun = function(user_name) {
    msg <- if (nzchar(user_name)) {
      paste("Hello,", user_name, "!")
    } else {
      "Enter your name above."
    }
    list(greeting = msg)
  },
  name = "update_greeting",
  description = "Generate a personalised greeting",
  arguments = list(
    user_name = ellmer::type_string("User's name")
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    idempotent_hint = TRUE
  )
)

# --- App ---
app <- mcp_app(
  ui = ui,
  tools = list(explore_data, greet),
  name = "multi-tool-demo"
)

serve(app)
