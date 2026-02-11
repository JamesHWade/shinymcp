# MCP App example with bslib theming and plot output
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
      tagList(
        mcp_plot("plot", height = "280px"),
        mcp_text("summary")
      )
    )
  )
)

tools <- list(
  ellmer::tool(
    fun = function(dataset = "mtcars") {
      data <- get(dataset, envir = asNamespace("datasets"))

      # Text summary
      summary_text <- paste(capture.output(summary(data)), collapse = "\n")

      # Plot: scatter of first two numeric columns
      numeric_cols <- names(data)[vapply(data, is.numeric, logical(1))]
      tmp <- tempfile(fileext = ".png")
      grDevices::png(tmp, width = 600, height = 280, res = 96)
      on.exit(unlink(tmp))
      par(mar = c(4, 4, 2, 1))
      if (length(numeric_cols) >= 2) {
        plot(
          data[[numeric_cols[1]]],
          data[[numeric_cols[2]]],
          xlab = numeric_cols[1],
          ylab = numeric_cols[2],
          main = dataset,
          pch = 19,
          col = adjustcolor("steelblue", 0.6)
        )
      } else {
        plot(
          data[[numeric_cols[1]]],
          type = "l",
          col = "steelblue",
          main = dataset,
          xlab = "Index",
          ylab = numeric_cols[1]
        )
      }
      grDevices::dev.off()

      plot_b64 <- base64enc::base64encode(tmp)

      list(summary = summary_text, plot = plot_b64)
    },
    name = "get_summary",
    description = "Get summary statistics and a plot for the selected dataset",
    arguments = list(
      dataset = ellmer::type_string("Dataset name")
    )
  )
)

app <- mcp_app(ui, tools, name = "hello-mcp")
serve(app)
