# ggplot2 4.0.0 Builder — plain Shiny version
# This is the standard Shiny implementation. See app.R for the MCP App version.
library(shiny)
library(bslib)
library(ggplot2)
library(palmerpenguins)

data <- penguins[complete.cases(penguins), ]

numeric_cols <- c(
  "Bill Length (mm)" = "bill_length_mm",
  "Bill Depth (mm)" = "bill_depth_mm",
  "Flipper Length (mm)" = "flipper_length_mm",
  "Body Mass (g)" = "body_mass_g"
)

categorical_cols <- c(
  "Species" = "species",
  "Island" = "island",
  "Sex" = "sex"
)

label_dict <- c(
  bill_length_mm = "Bill Length (mm)",
  bill_depth_mm = "Bill Depth (mm)",
  flipper_length_mm = "Flipper Length (mm)",
  body_mass_g = "Body Mass (g)",
  species = "Species",
  island = "Island",
  sex = "Sex"
)

geom_choices <- c(
  "Points" = "point",
  "Points + Convex Hull" = "hull",
  "Points + Centroids" = "centroids",
  "Connected Steps" = "connect_step",
  "Connected Smooth" = "connect_smooth",
  "Boxplot" = "boxplot",
  "Violin + Quantiles" = "violin",
  "Labels" = "label"
)

theme_choices <- c(
  "Minimal" = "minimal",
  "Gray" = "gray",
  "Classic" = "classic",
  "Black/White" = "bw",
  "Light" = "light",
  "Dark" = "dark",
  "Void" = "void"
)

ink_choices <- c(
  "Default" = "default",
  "Navy" = "navy",
  "Dark Green" = "darkgreen",
  "Dark Red" = "darkred",
  "Grey 20" = "grey20"
)

paper_choices <- c(
  "Default" = "default",
  "Cornsilk" = "cornsilk",
  "Alice Blue" = "aliceblue",
  "Linen" = "linen",
  "Mint Cream" = "mintcream",
  "Lavender Blush" = "lavenderblush"
)

accent_choices <- c(
  "Default" = "default",
  "Tomato" = "tomato",
  "Steel Blue" = "steelblue",
  "Forest Green" = "forestgreen",
  "Dark Orange" = "darkorange",
  "Orchid" = "orchid"
)

ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "ggplot2 4.0.0 Builder",
  sidebar = sidebar(
    width = 280,
    accordion(
      open = c("Data Mapping", "Geometry"),
      accordion_panel(
        "Data Mapping",
        selectInput("x_var", "X axis", numeric_cols),
        selectInput(
          "y_var",
          "Y axis",
          numeric_cols,
          selected = "bill_depth_mm"
        ),
        selectInput(
          "color_var",
          "Color by",
          c("None" = "none", categorical_cols)
        ),
        selectInput(
          "facet_var",
          "Facet by",
          c("None" = "none", categorical_cols)
        )
      ),
      accordion_panel(
        "Geometry",
        selectInput("geom", "Plot type", geom_choices),
        checkboxInput("trend", "Add trend line"),
        checkboxInput("reverse_axes", "Reverse axes")
      ),
      accordion_panel(
        "Theme (4.0.0)",
        selectInput("theme_name", "Base theme", theme_choices),
        selectInput("ink", "Ink (foreground)", ink_choices),
        selectInput("paper", "Paper (background)", paper_choices),
        selectInput("accent", "Accent color", accent_choices)
      )
    )
  ),
  card(
    full_screen = TRUE,
    card_header("Plot"),
    plotOutput("plot", height = "440px")
  ),
  card(
    card_header("ggplot2 Code"),
    verbatimTextOutput("code")
  )
)

server <- function(input, output, session) {
  built <- reactive({
    x_var <- input$x_var
    y_var <- input$y_var
    color_var <- input$color_var
    facet_var <- input$facet_var
    geom <- input$geom
    theme_name <- input$theme_name
    ink <- input$ink
    paper <- input$paper
    accent <- input$accent

    use_color <- color_var != "none"

    # --- Build the plot ---
    if (use_color) {
      p <- ggplot(
        data,
        aes(
          x = .data[[x_var]],
          y = .data[[y_var]],
          colour = .data[[color_var]]
        )
      )
      code_lines <- c(
        "ggplot(penguins, aes(",
        sprintf("  x = %s, y = %s,", x_var, y_var),
        sprintf("  colour = %s", color_var),
        ")) +"
      )
    } else {
      p <- ggplot(
        data,
        aes(
          x = .data[[x_var]],
          y = .data[[y_var]]
        )
      )
      code_lines <- c(
        "ggplot(penguins, aes(",
        sprintf("  x = %s, y = %s", x_var, y_var),
        ")) +"
      )
    }

    # --- Geometry layer ---
    if (geom == "point") {
      p <- p + geom_point(alpha = 0.7, size = 2.5)
      code_lines <- c(code_lines, "  geom_point(alpha = 0.7, size = 2.5) +")
    } else if (geom == "hull") {
      make_hull <- function(df) {
        df <- df[complete.cases(df[, c("x", "y")]), , drop = FALSE]
        if (nrow(df) < 3) {
          return(df)
        }
        hull <- chull(df$x, df$y)
        df[hull, , drop = FALSE]
      }
      p <- p +
        geom_point(alpha = 0.7, size = 2.5) +
        geom_polygon(
          stat = "manual",
          fun = make_hull,
          fill = NA,
          linetype = "dotted"
        )
      code_lines <- c(
        code_lines,
        "  geom_point(alpha = 0.7, size = 2.5) +",
        "  geom_polygon(",
        '    stat = "manual", fun = make_hull,',
        '    fill = NA, linetype = "dotted"',
        "  ) +"
      )
    } else if (geom == "centroids") {
      make_centroids <- function(df) {
        transform(
          df,
          xend = mean(x, na.rm = TRUE),
          yend = mean(y, na.rm = TRUE)
        )
      }
      p <- p +
        geom_point(alpha = 0.7, size = 2.5) +
        stat_manual(
          geom = "segment",
          fun = make_centroids,
          linewidth = 0.3,
          alpha = 0.4
        )
      code_lines <- c(
        code_lines,
        "  geom_point(alpha = 0.7, size = 2.5) +",
        "  stat_manual(",
        '    geom = "segment", fun = make_centroids,',
        "    linewidth = 0.3, alpha = 0.4",
        "  ) +"
      )
    } else if (geom == "connect_step") {
      if (use_color) {
        agg <- aggregate(
          data[[y_var]],
          by = list(group = data[[color_var]], x = data[[x_var]]),
          FUN = median
        )
        names(agg) <- c(color_var, x_var, y_var)
      } else {
        agg <- aggregate(
          data[[y_var]],
          by = list(x = data[[x_var]]),
          FUN = median
        )
        names(agg) <- c(x_var, y_var)
      }
      agg <- agg[order(agg[[x_var]]), ]
      p <- ggplot(agg, aes(x = .data[[x_var]], y = .data[[y_var]]))
      if (use_color) {
        p <- p + aes(colour = .data[[color_var]])
      }
      p <- p + geom_point(size = 3) + stat_connect(connection = "hv")
      code_lines <- c(
        code_lines,
        "  geom_point(size = 3) +",
        '  stat_connect(connection = "hv") +'
      )
    } else if (geom == "connect_smooth") {
      if (use_color) {
        agg <- aggregate(
          data[[y_var]],
          by = list(group = data[[color_var]], x = data[[x_var]]),
          FUN = median
        )
        names(agg) <- c(color_var, x_var, y_var)
      } else {
        agg <- aggregate(
          data[[y_var]],
          by = list(x = data[[x_var]]),
          FUN = median
        )
        names(agg) <- c(x_var, y_var)
      }
      agg <- agg[order(agg[[x_var]]), ]
      x_seq <- seq(0, 1, length.out = 20)[-1]
      smooth_conn <- cbind(
        x_seq,
        scales::rescale(plogis(x_seq, location = 0.5, scale = 0.1))
      )
      p <- ggplot(agg, aes(x = .data[[x_var]], y = .data[[y_var]]))
      if (use_color) {
        p <- p + aes(colour = .data[[color_var]])
      }
      p <- p + geom_point(size = 3) + stat_connect(connection = smooth_conn)
      code_lines <- c(
        code_lines,
        "  geom_point(size = 3) +",
        "  stat_connect(connection = smooth_conn) +"
      )
    } else if (geom == "boxplot") {
      if (use_color) {
        p <- ggplot(
          data,
          aes(
            x = .data[[color_var]],
            y = .data[[y_var]],
            fill = .data[[color_var]]
          )
        )
        code_lines <- c(
          "ggplot(penguins, aes(",
          sprintf("  x = %s, y = %s, fill = %s", color_var, y_var, color_var),
          ")) +"
        )
      } else {
        p <- ggplot(data, aes(y = .data[[y_var]]))
        code_lines <- c(
          "ggplot(penguins, aes(",
          sprintf("  y = %s", y_var),
          ")) +"
        )
      }
      p <- p +
        geom_boxplot(
          alpha = 0.7,
          whisker.linetype = "dashed",
          staplewidth = 0.5
        )
      code_lines <- c(
        code_lines,
        "  geom_boxplot(",
        "    alpha = 0.7,",
        '    whisker.linetype = "dashed",',
        "    staplewidth = 0.5",
        "  ) +"
      )
    } else if (geom == "violin") {
      if (use_color) {
        p <- ggplot(
          data,
          aes(
            x = .data[[color_var]],
            y = .data[[y_var]],
            fill = .data[[color_var]]
          )
        )
        code_lines <- c(
          "ggplot(penguins, aes(",
          sprintf("  x = %s, y = %s, fill = %s", color_var, y_var, color_var),
          ")) +"
        )
      } else {
        p <- ggplot(data, aes(y = .data[[y_var]]))
        code_lines <- c(
          "ggplot(penguins, aes(",
          sprintf("  y = %s", y_var),
          ")) +"
        )
      }
      p <- p +
        geom_violin(
          alpha = 0.6,
          quantiles = c(0.25, 0.5, 0.75),
          quantile.linetype = "dashed",
          quantile.linewidth = 0.5
        )
      code_lines <- c(
        code_lines,
        "  geom_violin(",
        "    alpha = 0.6,",
        "    quantiles = c(0.25, 0.5, 0.75),",
        '    quantile.linetype = "dashed"',
        "  ) +"
      )
    } else if (geom == "label") {
      label_data <- data[seq(1, nrow(data), length.out = min(30, nrow(data))), ]
      if (use_color) {
        p <- ggplot(
          label_data,
          aes(
            x = .data[[x_var]],
            y = .data[[y_var]],
            colour = .data[[color_var]],
            label = .data[[color_var]]
          )
        )
      } else {
        p <- ggplot(
          label_data,
          aes(
            x = .data[[x_var]],
            y = .data[[y_var]],
            label = rownames(label_data)
          )
        )
      }
      p <- p +
        geom_label(
          text.colour = "grey20",
          size = 3,
          alpha = 0.8,
          label.padding = unit(0.15, "lines")
        )
      code_lines <- c(
        code_lines,
        "  geom_label(",
        '    text.colour = "grey20",',
        "    size = 3, alpha = 0.8",
        "  ) +"
      )
    }

    # --- Trend line ---
    if (isTRUE(input$trend)) {
      if (geom %in% c("point", "hull", "centroids", "label")) {
        p <- p + geom_smooth(method = "lm", se = FALSE, linewidth = 0.8)
        code_lines <- c(
          code_lines,
          '  geom_smooth(method = "lm", se = FALSE) +'
        )
      }
    }

    # --- Faceting ---
    if (facet_var != "none" && facet_var %in% names(data)) {
      p <- p +
        facet_wrap(
          vars(.data[[facet_var]]),
          scales = "free_x",
          space = "free_x"
        )
      code_lines <- c(
        code_lines,
        sprintf(
          '  facet_wrap(~ %s, scales = "free_x", space = "free_x") +',
          facet_var
        )
      )
    }

    # --- Coordinate reversal ---
    if (isTRUE(input$reverse_axes)) {
      p <- p + coord_cartesian(reverse = "xy")
      code_lines <- c(code_lines, '  coord_cartesian(reverse = "xy") +')
    }

    # --- Labels ---
    p <- p + labs(dictionary = label_dict)
    code_lines <- c(code_lines, "  labs(dictionary = label_dict) +")

    # --- Theme ---
    theme_args <- list()
    if (ink != "default") {
      theme_args$ink <- ink
    }
    if (paper != "default") {
      theme_args$paper <- paper
    }
    if (accent != "default") {
      theme_args$accent <- accent
    }

    theme_fn <- switch(
      theme_name,
      minimal = theme_minimal,
      gray = theme_gray,
      classic = theme_classic,
      bw = theme_bw,
      light = theme_light,
      dark = theme_dark,
      void = theme_void,
      theme_minimal
    )
    theme_args$base_size <- 13
    p <- p + do.call(theme_fn, theme_args) + theme(legend.position = "bottom")

    theme_arg_strs <- "base_size = 13"
    if (ink != "default") {
      theme_arg_strs <- c(theme_arg_strs, sprintf('ink = "%s"', ink))
    }
    if (paper != "default") {
      theme_arg_strs <- c(theme_arg_strs, sprintf('paper = "%s"', paper))
    }
    if (accent != "default") {
      theme_arg_strs <- c(theme_arg_strs, sprintf('accent = "%s"', accent))
    }
    code_lines <- c(
      code_lines,
      sprintf(
        "  theme_%s(%s)",
        theme_name,
        paste(theme_arg_strs, collapse = ", ")
      )
    )

    code_text <- paste(code_lines, collapse = "\n")
    code_text <- sub("\\+\\s*$", "", code_text)

    list(plot = p, code = code_text)
  })

  output$plot <- renderPlot(built()$plot)
  output$code <- renderText(built()$code)
}

shinyApp(ui, server)
