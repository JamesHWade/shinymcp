# Palmer Penguins Explorer - MCP App example
# Demonstrates auto-detection of bslib/shiny inputs by tool argument names.
# No mcp_select() or mcp_checkbox() needed — the bridge finds <select id="species">
# etc. automatically because the tool arguments match the element ids.
library(shinymcp)
library(bslib)
library(htmltools)
library(ggplot2)
library(palmerpenguins)

var_labels <- c(
  bill_length_mm = "Bill Length (mm)",
  bill_depth_mm = "Bill Depth (mm)",
  flipper_length_mm = "Flipper Length (mm)",
  body_mass_g = "Body Mass (g)"
)

var_choices <- setNames(names(var_labels), var_labels)

ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "Palmer Penguins Explorer",
  sidebar = sidebar(
    width = 260,
    # Native shiny inputs — auto-detected by matching tool argument names
    shiny::selectInput(
      "species",
      "Species",
      c("All", "Adelie", "Chinstrap", "Gentoo")
    ),
    shiny::selectInput("x_var", "X axis", var_choices),
    shiny::selectInput(
      "y_var",
      "Y axis",
      var_choices,
      selected = "bill_depth_mm"
    ),
    shiny::checkboxInput("trend", "Show trend line")
  ),
  card(
    full_screen = TRUE,
    card_header("Scatter Plot"),
    mcp_plot("scatter", height = "380px")
  ),
  card(
    card_header("Summary Statistics"),
    mcp_text("stats")
  )
)

tools <- list(
  ellmer::tool(
    fun = function(
      species = "All",
      x_var = "bill_length_mm",
      y_var = "bill_depth_mm",
      trend = FALSE
    ) {
      data <- penguins
      data <- data[complete.cases(data), ]

      if (species != "All") {
        data <- data[data$species == species, ]
      }

      # ggplot2 scatter plot colored by species
      p <- ggplot(
        data,
        aes(x = .data[[x_var]], y = .data[[y_var]], color = species)
      ) +
        geom_point(alpha = 0.7, size = 2.5) +
        scale_color_manual(
          values = c(
            Adelie = "#ff6b35",
            Chinstrap = "#7b2d8e",
            Gentoo = "#0f7173"
          )
        ) +
        labs(
          x = var_labels[[x_var]],
          y = var_labels[[y_var]],
          color = "Species"
        ) +
        theme_minimal(base_size = 13) +
        theme(legend.position = "bottom")

      if (isTRUE(trend) || identical(trend, "true")) {
        p <- p + geom_smooth(method = "lm", se = FALSE, linewidth = 0.8)
      }

      tmp <- tempfile(fileext = ".png")
      ggsave(tmp, p, width = 7, height = 4, dpi = 144, bg = "white")
      on.exit(unlink(tmp))
      plot_b64 <- base64enc::base64encode(tmp)

      # Summary statistics
      stats <- paste(
        capture.output({
          cat(sprintf("Observations: %d penguins\n\n", nrow(data)))
          print(summary(data[, c(x_var, y_var, "species")]))
        }),
        collapse = "\n"
      )

      list(scatter = plot_b64, stats = stats)
    },
    name = "explore_penguins",
    description = "Explore the Palmer Penguins dataset with interactive scatter plots and summary statistics",
    arguments = list(
      species = ellmer::type_string(
        "Species filter: All, Adelie, Chinstrap, or Gentoo"
      ),
      x_var = ellmer::type_string("X axis variable name"),
      y_var = ellmer::type_string("Y axis variable name"),
      trend = ellmer::type_boolean("Whether to show a linear trend line")
    )
  )
)

app <- mcp_app(ui, tools, name = "penguins-explorer")
serve(app)
