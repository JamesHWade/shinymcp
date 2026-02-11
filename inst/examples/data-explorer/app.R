# Data Explorer - MCP App example
# Demonstrates programmatic input generation from a data frame.
# Pass any data frame and the app builds column selectors automatically.
library(shinymcp)
library(bslib)
library(htmltools)
library(ggplot2)

# --- Data setup ---
# Replace this with any data frame in your environment
data <- mtcars
data$name <- rownames(mtcars)
rownames(data) <- NULL

# --- Programmatic input choices ---
numeric_cols <- names(data)[vapply(data, is.numeric, logical(1))]
all_cols <- names(data)
categorical_cols <- names(data)[vapply(
  data,
  function(x) {
    is.character(x) || is.factor(x) || length(unique(x)) <= 10
  },
  logical(1)
)]

num_choices <- setNames(numeric_cols, gsub("_", " ", numeric_cols))
cat_choices <- c("None" = "none", setNames(categorical_cols, categorical_cols))
geom_choices <- c(
  "Points" = "point",
  "Line" = "line",
  "Bar" = "bar",
  "Boxplot" = "boxplot",
  "Histogram" = "histogram"
)

# --- UI ---
ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "Data Explorer",
  sidebar = sidebar(
    width = 260,
    shiny::selectInput("x_var", "X axis", num_choices),
    shiny::selectInput(
      "y_var",
      "Y axis",
      num_choices,
      selected = numeric_cols[min(2, length(numeric_cols))]
    ),
    shiny::selectInput("color_var", "Color by", cat_choices),
    shiny::selectInput("geom", "Plot type", geom_choices),
    shiny::checkboxInput("trend", "Show trend line")
  ),
  card(
    full_screen = TRUE,
    card_header("Plot"),
    mcp_plot("plot", height = "400px")
  ),
  card(
    card_header("Summary"),
    mcp_text("summary")
  )
)

# --- Tool ---
tools <- list(
  ellmer::tool(
    fun = function(
      x_var = numeric_cols[1],
      y_var = numeric_cols[min(2, length(numeric_cols))],
      color_var = "none",
      geom = "point",
      trend = FALSE
    ) {
      p <- ggplot(data, aes(x = .data[[x_var]]))

      use_color <- color_var != "none" && color_var %in% names(data)

      if (geom == "histogram") {
        if (use_color) {
          p <- p +
            aes(fill = factor(.data[[color_var]])) +
            geom_histogram(bins = 30, alpha = 0.7, position = "identity") +
            labs(fill = color_var)
        } else {
          p <- p + geom_histogram(bins = 30, fill = "#3366cc", alpha = 0.7)
        }
      } else if (geom == "bar") {
        if (use_color) {
          p <- p +
            aes(fill = factor(.data[[color_var]])) +
            geom_bar(alpha = 0.7) +
            labs(fill = color_var)
        } else {
          p <- p + geom_bar(fill = "#3366cc", alpha = 0.7)
        }
      } else if (geom == "boxplot") {
        p <- ggplot(data, aes(x = factor(.data[[x_var]]), y = .data[[y_var]]))
        if (use_color) {
          p <- p +
            aes(fill = factor(.data[[color_var]])) +
            geom_boxplot(alpha = 0.7) +
            labs(fill = color_var)
        } else {
          p <- p + geom_boxplot(fill = "#3366cc", alpha = 0.7)
        }
        p <- p + labs(x = x_var)
      } else {
        p <- p + aes(y = .data[[y_var]])
        if (use_color) {
          p <- p +
            aes(color = factor(.data[[color_var]])) +
            labs(color = color_var)
        }
        if (geom == "point") {
          p <- p + geom_point(alpha = 0.7, size = 2.5)
        } else if (geom == "line") {
          p <- p + geom_line(linewidth = 0.8)
        }
      }

      if (isTRUE(trend) || identical(trend, "true")) {
        if (geom %in% c("point", "line")) {
          p <- p + geom_smooth(method = "lm", se = FALSE, linewidth = 0.8)
        }
      }

      p <- p +
        labs(x = x_var, y = if (geom != "histogram") y_var else "Count") +
        theme_minimal(base_size = 13) +
        theme(legend.position = "bottom")

      tmp <- tempfile(fileext = ".png")
      ggsave(tmp, p, width = 7, height = 4, dpi = 144, bg = "white")
      on.exit(unlink(tmp))
      plot_b64 <- base64enc::base64encode(tmp)

      # Summary statistics for the selected columns
      cols <- unique(c(x_var, y_var))
      stats <- paste(
        capture.output({
          cat(sprintf(
            "Dataset: %d rows x %d columns\n\n",
            nrow(data),
            ncol(data)
          ))
          for (col in cols) {
            if (is.numeric(data[[col]])) {
              cat(sprintf(
                "%s: mean=%.2f, sd=%.2f, range=[%.2f, %.2f]\n",
                col,
                mean(data[[col]], na.rm = TRUE),
                sd(data[[col]], na.rm = TRUE),
                min(data[[col]], na.rm = TRUE),
                max(data[[col]], na.rm = TRUE)
              ))
            }
          }
          if (use_color) {
            cat(sprintf(
              "\nColor variable '%s': %d unique values\n",
              color_var,
              length(unique(data[[color_var]]))
            ))
          }
        }),
        collapse = "\n"
      )

      list(plot = plot_b64, summary = stats)
    },
    name = "explore_data",
    description = "Explore a dataset with interactive ggplot2 visualizations",
    arguments = list(
      x_var = ellmer::type_string("Column name for X axis"),
      y_var = ellmer::type_string("Column name for Y axis"),
      color_var = ellmer::type_string(
        "Column to use for color grouping, or 'none'"
      ),
      geom = ellmer::type_string(
        "Plot type: point, line, bar, boxplot, or histogram"
      ),
      trend = ellmer::type_boolean("Whether to show a linear trend line")
    )
  )
)

app <- mcp_app(ui, tools, name = "data-explorer")
serve(app)
