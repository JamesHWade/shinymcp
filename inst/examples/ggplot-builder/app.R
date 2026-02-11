# ggplot2 4.0.0 Builder - MCP App example
# Showcases new ggplot2 4.0.0 features:
#   - ink/paper/accent theming
#   - stat_manual() for convex hulls
#   - stat_connect() for step/zigzag connections
#   - labs(dictionary = ...) for automatic labels
#   - facet_wrap(space = "free")
#   - coord_cartesian(reverse = ...)
#   - geom_area() with varying fill gradient
#   - geom_label(text.colour, border.colour)
#   - discrete scale minor_breaks
library(shinymcp)
library(bslib)
library(htmltools)
library(ggplot2)
library(palmerpenguins)

# --- Data setup ---
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

# Label dictionary (ggplot2 4.0.0 feature)
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

# --- UI ---
ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "ggplot2 4.0.0 Builder",
  sidebar = sidebar(
    width = 280,
    accordion(
      open = c("Data Mapping", "Geometry"),
      accordion_panel(
        "Data Mapping",
        shiny::selectInput("x_var", "X axis", numeric_cols),
        shiny::selectInput(
          "y_var",
          "Y axis",
          numeric_cols,
          selected = "bill_depth_mm"
        ),
        shiny::selectInput("color_var", "Color by", categorical_cols),
        shiny::selectInput(
          "facet_var",
          "Facet by",
          c("None" = "none", categorical_cols)
        )
      ),
      accordion_panel(
        "Geometry",
        shiny::selectInput("geom", "Plot type", geom_choices),
        shiny::checkboxInput("trend", "Add trend line"),
        shiny::checkboxInput("reverse_axes", "Reverse axes")
      ),
      accordion_panel(
        "Theme (4.0.0)",
        shiny::selectInput("theme_name", "Base theme", theme_choices),
        shiny::selectInput("ink", "Ink (foreground)", ink_choices),
        shiny::selectInput("paper", "Paper (background)", paper_choices),
        shiny::selectInput("accent", "Accent color", accent_choices)
      )
    )
  ),
  card(
    full_screen = TRUE,
    card_header("Plot"),
    mcp_plot("plot", height = "440px")
  ),
  card(
    card_header("ggplot2 Code"),
    mcp_text("code")
  )
)

# --- Tool ---
tools <- list(
  ellmer::tool(
    fun = function(
      x_var = "bill_length_mm",
      y_var = "bill_depth_mm",
      color_var = "species",
      facet_var = "none",
      geom = "point",
      trend = FALSE,
      reverse_axes = FALSE,
      theme_name = "minimal",
      ink = "default",
      paper = "default",
      accent = "default"
    ) {
      # --- Build the plot ---
      p <- ggplot(
        data,
        aes(
          x = .data[[x_var]],
          y = .data[[y_var]],
          colour = .data[[color_var]]
        )
      )

      # Code tracking for display
      code_lines <- c(
        'ggplot(penguins, aes(',
        sprintf('  x = %s, y = %s,', x_var, y_var),
        sprintf('  colour = %s', color_var),
        ')) +'
      )

      # --- Geometry layer ---
      if (geom == "point") {
        p <- p + geom_point(alpha = 0.7, size = 2.5)
        code_lines <- c(code_lines, '  geom_point(alpha = 0.7, size = 2.5) +')
      } else if (geom == "hull") {
        # stat_manual() for convex hulls (ggplot2 4.0.0)
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
          '  geom_point(alpha = 0.7, size = 2.5) +',
          '  # stat_manual() — new in 4.0.0',
          '  geom_polygon(',
          '    stat = "manual", fun = make_hull,',
          '    fill = NA, linetype = "dotted"',
          '  ) +'
        )
      } else if (geom == "centroids") {
        # stat_manual() for centroid segments (ggplot2 4.0.0)
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
          '  geom_point(alpha = 0.7, size = 2.5) +',
          '  # stat_manual() — new in 4.0.0',
          '  stat_manual(',
          '    geom = "segment", fun = make_centroids,',
          '    linewidth = 0.3, alpha = 0.4',
          '  ) +'
        )
      } else if (geom == "connect_step") {
        # stat_connect() with step pattern (ggplot2 4.0.0)
        agg <- aggregate(
          data[[y_var]],
          by = list(group = data[[color_var]], x = data[[x_var]]),
          FUN = median
        )
        names(agg) <- c(color_var, x_var, y_var)
        agg <- agg[order(agg[[x_var]]), ]
        p <- ggplot(
          agg,
          aes(
            x = .data[[x_var]],
            y = .data[[y_var]],
            colour = .data[[color_var]]
          )
        ) +
          geom_point(size = 3) +
          stat_connect(connection = "hv")
        code_lines <- c(
          code_lines,
          '  geom_point(size = 3) +',
          '  # stat_connect() — new in 4.0.0',
          '  stat_connect(connection = "hv") +'
        )
      } else if (geom == "connect_smooth") {
        # stat_connect() with smooth logistic connection (ggplot2 4.0.0)
        agg <- aggregate(
          data[[y_var]],
          by = list(group = data[[color_var]], x = data[[x_var]]),
          FUN = median
        )
        names(agg) <- c(color_var, x_var, y_var)
        agg <- agg[order(agg[[x_var]]), ]
        x_seq <- seq(0, 1, length.out = 20)[-1]
        smooth_conn <- cbind(
          x_seq,
          scales::rescale(plogis(x_seq, location = 0.5, scale = 0.1))
        )
        p <- ggplot(
          agg,
          aes(
            x = .data[[x_var]],
            y = .data[[y_var]],
            colour = .data[[color_var]]
          )
        ) +
          geom_point(size = 3) +
          stat_connect(connection = smooth_conn)
        code_lines <- c(
          code_lines,
          '  geom_point(size = 3) +',
          '  # stat_connect() with smooth logistic curve — new in 4.0.0',
          '  stat_connect(connection = smooth_conn) +'
        )
      } else if (geom == "boxplot") {
        # Boxplot with new 4.0.0 styling arguments
        p <- ggplot(
          data,
          aes(
            x = .data[[color_var]],
            y = .data[[y_var]],
            fill = .data[[color_var]]
          )
        ) +
          geom_boxplot(
            alpha = 0.7,
            whisker.linetype = "dashed",
            staplewidth = 0.5
          )
        code_lines <- c(
          'ggplot(penguins, aes(',
          sprintf('  x = %s, y = %s, fill = %s', color_var, y_var, color_var),
          ')) +',
          '  # Enhanced boxplot styling — new in 4.0.0',
          '  geom_boxplot(',
          '    alpha = 0.7,',
          '    whisker.linetype = "dashed",',
          '    staplewidth = 0.5',
          '  ) +'
        )
      } else if (geom == "violin") {
        # Violin with quantile lines (ggplot2 4.0.0)
        p <- ggplot(
          data,
          aes(
            x = .data[[color_var]],
            y = .data[[y_var]],
            fill = .data[[color_var]]
          )
        ) +
          geom_violin(
            alpha = 0.6,
            quantiles = c(0.25, 0.5, 0.75),
            quantile.linetype = "dashed",
            quantile.linewidth = 0.5
          )
        code_lines <- c(
          'ggplot(penguins, aes(',
          sprintf('  x = %s, y = %s, fill = %s', color_var, y_var, color_var),
          ')) +',
          '  # Violin with quantile lines — new in 4.0.0',
          '  geom_violin(',
          '    alpha = 0.6,',
          '    quantiles = c(0.25, 0.5, 0.75),',
          '    quantile.linetype = "dashed"',
          '  ) +'
        )
      } else if (geom == "label") {
        # geom_label with text.colour/border.colour (ggplot2 4.0.0)
        # Use a subset so labels aren't overlapping too much
        label_data <- data[
          seq(1, nrow(data), length.out = min(30, nrow(data))),
        ]
        p <- ggplot(
          label_data,
          aes(
            x = .data[[x_var]],
            y = .data[[y_var]],
            colour = .data[[color_var]],
            label = .data[[color_var]]
          )
        ) +
          geom_label(
            text.colour = "grey20",
            size = 3,
            alpha = 0.8,
            label.padding = unit(0.15, "lines")
          )
        code_lines <- c(
          code_lines,
          '  # geom_label text.colour — new in 4.0.0',
          '  geom_label(',
          '    text.colour = "grey20",',
          '    size = 3, alpha = 0.8',
          '  ) +'
        )
      }

      # --- Trend line ---
      if (isTRUE(trend) || identical(trend, "true")) {
        if (geom %in% c("point", "hull", "centroids", "label")) {
          p <- p + geom_smooth(method = "lm", se = FALSE, linewidth = 0.8)
          code_lines <- c(
            code_lines,
            '  geom_smooth(method = "lm", se = FALSE) +'
          )
        }
      }

      # --- Faceting ---
      use_facet <- facet_var != "none" && facet_var %in% names(data)
      if (use_facet) {
        # facet_wrap(space = "free") is new in 4.0.0
        p <- p +
          facet_wrap(
            vars(.data[[facet_var]]),
            scales = "free_x",
            space = "free_x"
          )
        code_lines <- c(
          code_lines,
          sprintf('  # facet_wrap(space = "free_x") %s new in 4.0.0', "\u2014"),
          sprintf(
            '  facet_wrap(~ %s, scales = "free_x", space = "free_x") +',
            facet_var
          )
        )
      }

      # --- Coordinate reversal (ggplot2 4.0.0) ---
      if (isTRUE(reverse_axes) || identical(reverse_axes, "true")) {
        p <- p + coord_cartesian(reverse = "xy")
        code_lines <- c(
          code_lines,
          '  # coord_cartesian(reverse) — new in 4.0.0',
          '  coord_cartesian(reverse = "xy") +'
        )
      }

      # --- Labels via dictionary (ggplot2 4.0.0) ---
      p <- p + labs(dictionary = label_dict)
      code_lines <- c(
        code_lines,
        '  # labs(dictionary) — new in 4.0.0',
        '  labs(dictionary = label_dict) +'
      )

      # --- Theme with ink/paper/accent (ggplot2 4.0.0) ---
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

      # Build theme code line
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
      theme_code <- sprintf(
        "  theme_%s(%s)",
        theme_name,
        paste(theme_arg_strs, collapse = ", ")
      )
      code_lines <- c(
        code_lines,
        paste0(
          "  # ink/paper/accent theming \u2014 new in 4.0.0\n",
          theme_code
        )
      )

      # --- Render ---
      tmp <- tempfile(fileext = ".png")
      ggsave(tmp, p, width = 8, height = 4.5, dpi = 150, bg = "white")
      on.exit(unlink(tmp))
      plot_b64 <- base64enc::base64encode(tmp)

      # Clean up trailing + from code
      code_text <- paste(code_lines, collapse = "\n")
      code_text <- sub("\\+\\s*$", "", code_text)

      list(plot = plot_b64, code = code_text)
    },
    name = "build_ggplot",
    description = paste(
      "Build a ggplot2 visualization of Palmer Penguins data.",
      "Showcases ggplot2 4.0.0 features including ink/paper/accent theming,",
      "stat_manual(), stat_connect(), labs(dictionary), facet_wrap(space),",
      "coord_cartesian(reverse), and enhanced geom styling."
    ),
    arguments = list(
      x_var = ellmer::type_string("Numeric column for X axis"),
      y_var = ellmer::type_string("Numeric column for Y axis"),
      color_var = ellmer::type_string("Categorical column for color mapping"),
      facet_var = ellmer::type_string("Column to facet by, or 'none'"),
      geom = ellmer::type_string(
        "Plot type: point, hull, centroids, connect_step, connect_smooth, boxplot, violin, or label"
      ),
      trend = ellmer::type_boolean("Add a linear trend line"),
      reverse_axes = ellmer::type_boolean("Reverse both axes (4.0.0 feature)"),
      theme_name = ellmer::type_string(
        "Base theme: minimal, gray, classic, bw, light, dark, or void"
      ),
      ink = ellmer::type_string(
        "Foreground color or 'default' (4.0.0 feature)"
      ),
      paper = ellmer::type_string(
        "Background color or 'default' (4.0.0 feature)"
      ),
      accent = ellmer::type_string("Accent color or 'default' (4.0.0 feature)")
    )
  )
)

app <- mcp_app(ui, tools, name = "ggplot-builder")
serve(app)
