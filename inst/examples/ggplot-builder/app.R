# ggplot2 4.0.0 Builder - MCP App example
# Showcases new ggplot2 4.0.0 features:
#   - ink/paper/accent theming
#   - stat_manual() for convex hulls
#   - stat_connect() for step/zigzag connections
#   - labs(dictionary = ...) for automatic labels
#   - facet_wrap(space = "free")
#   - coord_cartesian(reverse = ...)
#   - geom_label(text.colour)
library(shinymcp)
library(bslib)
library(htmltools)
library(ggplot2)

# --- Default data (Palmer Penguins) for standalone use ---
library(palmerpenguins)
default_data <- penguins[complete.cases(penguins), ]

# Persists the active dataset across tool calls. The JS bridge only sends
# arguments that have DOM elements; data_csv and data_path don't, so
# UI-triggered calls (dropdown changes) arrive without them. This env
# keeps the last loaded data in memory. For data loaded via data_csv, a
# temp file is also written so the AI can reference the path.
active_data_env <- new.env(parent = emptyenv())
active_data_env$df <- default_data
active_data_env$path <- NULL # set when data is loaded from csv/path

numeric_cols <- names(default_data)[vapply(
  default_data,
  is.numeric,
  logical(1)
)]
categorical_cols <- names(default_data)[
  vapply(default_data, function(x) is.character(x) || is.factor(x), logical(1))
]

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
          selected = numeric_cols[min(2, length(numeric_cols))]
        ),
        shiny::selectInput(
          "color_var",
          "Color by",
          c("None" = "none", categorical_cols)
        ),
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
  ),
  # Hidden output for dynamic column updates
  tags$div(
    style = "display:none;",
    mcp_text("_columns")
  ),
  # JS to watch _columns and update selects dynamically
  tags$script(HTML(
    "
    (function() {
      var colEl = document.querySelector('[data-shinymcp-output=\"_columns\"]');
      if (!colEl) return;
      var obs = new MutationObserver(function() {
        var raw = colEl.textContent || colEl.innerText;
        if (!raw || !raw.trim()) return;
        try { var info = JSON.parse(raw); } catch(e) { console.error('[shinymcp] Failed to parse column metadata:', e.message); return; }
        updateSelect('x_var', info.numeric);
        updateSelect('y_var', info.numeric);
        updateSelectWithNone('color_var', info.categorical);
        updateSelectWithNone('facet_var', info.categorical);
      });
      obs.observe(colEl, { childList: true, characterData: true, subtree: true });

      function clearSelect(sel) {
        while (sel.firstChild) { sel.removeChild(sel.firstChild); }
      }

      function updateSelect(id, values) {
        var sel = document.getElementById(id);
        if (!sel) { console.warn('[shinymcp] Select element not found: #' + id); return; }
        if (!Array.isArray(values)) return;
        var cur = sel.value;
        clearSelect(sel);
        for (var i = 0; i < values.length; i++) {
          var opt = document.createElement('option');
          opt.value = values[i];
          opt.textContent = values[i];
          if (values[i] === cur) opt.selected = true;
          sel.appendChild(opt);
        }
        if (cur && values.indexOf(cur) === -1 && values.length > 0) {
          sel.value = values[0];
        }
      }

      function updateSelectWithNone(id, values) {
        var sel = document.getElementById(id);
        if (!sel) { console.warn('[shinymcp] Select element not found: #' + id); return; }
        if (!Array.isArray(values)) return;
        var cur = sel.value;
        clearSelect(sel);
        var none = document.createElement('option');
        none.value = 'none';
        none.textContent = 'None';
        if (cur === 'none') none.selected = true;
        sel.appendChild(none);
        for (var i = 0; i < values.length; i++) {
          var opt = document.createElement('option');
          opt.value = values[i];
          opt.textContent = values[i];
          if (values[i] === cur) opt.selected = true;
          sel.appendChild(opt);
        }
      }
    })();
  "
  ))
)

# --- Tool ---
tools <- list(
  ellmer::tool(
    fun = function(
      data_path = "",
      data_csv = "",
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
      # --- Resolve data ---
      # Priority: data_path > data_csv > last active data > default
      new_data_loaded <- FALSE
      if (nzchar(data_path)) {
        if (!file.exists(data_path)) {
          rlang::abort(c(
            sprintf("Data file not found: '%s'", data_path),
            "i" = "Check that the file path is correct and the file exists.",
            "i" = "Supported formats: CSV, TSV, Excel (.xlsx/.xls), Parquet."
          ))
        }
        ext <- tolower(tools::file_ext(data_path))
        supported <- c("csv", "tsv", "xlsx", "xls", "parquet")
        if (!ext %in% supported) {
          rlang::abort(c(
            sprintf("Unsupported file extension: '.%s'", ext),
            "i" = sprintf(
              "Supported formats: %s.",
              paste(supported, collapse = ", ")
            )
          ))
        }
        data <- tryCatch(
          {
            switch(
              ext,
              csv = read.csv(data_path, stringsAsFactors = TRUE),
              tsv = read.delim(data_path, stringsAsFactors = TRUE),
              xlsx = ,
              xls = {
                rlang::check_installed("readxl", "to read Excel files")
                readxl::read_excel(data_path)
              },
              parquet = {
                rlang::check_installed("arrow", "to read Parquet files")
                as.data.frame(arrow::read_parquet(data_path))
              }
            )
          },
          error = function(e) {
            rlang::abort(
              c(
                sprintf("Failed to read data file: '%s'", data_path),
                "x" = conditionMessage(e),
                "i" = "Verify the file is not corrupt and matches its extension."
              ),
              parent = e
            )
          }
        )
        data <- as.data.frame(data)
        new_data_loaded <- TRUE
      } else if (nzchar(data_csv)) {
        data <- tryCatch(
          read.csv(text = data_csv, stringsAsFactors = TRUE),
          error = function(e) {
            rlang::abort(
              c(
                "Failed to parse inline CSV data.",
                "x" = conditionMessage(e),
                "i" = "Ensure the data_csv argument is valid CSV with consistent columns."
              ),
              parent = e
            )
          }
        )
        new_data_loaded <- TRUE
      } else {
        data <- active_data_env$df
      }

      if (nrow(data) == 0L) {
        rlang::abort(c(
          "Loaded data has zero rows.",
          "i" = "Provide data with at least a header row and one data row.",
          "i" = sprintf(
            "Columns found: %s",
            paste(names(data), collapse = ", ")
          )
        ))
      }

      # Auto-detect column types
      cur_numeric <- names(data)[vapply(data, is.numeric, logical(1))]
      cur_categorical <- names(data)[
        vapply(
          data,
          function(x) is.character(x) || is.factor(x),
          logical(1)
        )
      ]
      all_cols <- names(data)

      if (length(cur_numeric) < 2) {
        rlang::abort(c(
          sprintf(
            "Dataset needs at least 2 numeric columns for plotting, found %d.",
            length(cur_numeric)
          ),
          "i" = sprintf(
            "Numeric columns found: %s",
            if (length(cur_numeric) == 0) {
              "none"
            } else {
              paste(cur_numeric, collapse = ", ")
            }
          ),
          "i" = sprintf("All columns: %s", paste(all_cols, collapse = ", "))
        ))
      }

      # Persist data only after validation passes
      if (new_data_loaded) {
        if (nzchar(data_path)) {
          active_data_env$df <- data
          active_data_env$path <- data_path
        } else {
          # data_csv branch — also persist to disk so the AI can reference the path
          tmp <- tempfile(fileext = ".csv")
          write.csv(data, tmp, row.names = FALSE)
          active_data_env$df <- data
          active_data_env$path <- tmp
        }
      }

      # Column metadata for dynamic select updates
      col_info <- jsonlite::toJSON(
        list(
          numeric = cur_numeric,
          categorical = cur_categorical,
          all = all_cols
        ),
        auto_unbox = FALSE
      )

      # Validate column selections against current data
      if (!x_var %in% all_cols) {
        x_var <- cur_numeric[1]
      }
      if (!y_var %in% all_cols) {
        y_var <- cur_numeric[min(2, length(cur_numeric))]
      }
      use_color <- color_var != "none"
      if (use_color && !color_var %in% all_cols) {
        color_var <- if (length(cur_categorical) > 0) {
          cur_categorical[1]
        } else {
          cur_numeric[1]
        }
      }
      if (facet_var != "none" && !facet_var %in% all_cols) {
        facet_var <- if (length(cur_categorical) > 0) {
          cur_categorical[1]
        } else {
          "none"
        }
      }

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
          "ggplot(data, aes(",
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
          "ggplot(data, aes(",
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
          "  # stat_manual() \u2014 new in 4.0.0",
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
          "  # stat_manual() \u2014 new in 4.0.0",
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
        p <- p +
          geom_point(size = 3) +
          stat_connect(connection = "hv")
        code_lines <- c(
          code_lines,
          "  geom_point(size = 3) +",
          "  # stat_connect() \u2014 new in 4.0.0",
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
        p <- p +
          geom_point(size = 3) +
          stat_connect(connection = smooth_conn)
        code_lines <- c(
          code_lines,
          "  geom_point(size = 3) +",
          "  # stat_connect() with smooth logistic curve \u2014 new in 4.0.0",
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
            "ggplot(data, aes(",
            sprintf("  x = %s, y = %s, fill = %s", color_var, y_var, color_var),
            ")) +"
          )
        } else {
          p <- ggplot(data, aes(y = .data[[y_var]]))
          code_lines <- c(
            "ggplot(data, aes(",
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
          "  # Enhanced boxplot styling \u2014 new in 4.0.0",
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
            "ggplot(data, aes(",
            sprintf("  x = %s, y = %s, fill = %s", color_var, y_var, color_var),
            ")) +"
          )
        } else {
          p <- ggplot(data, aes(y = .data[[y_var]]))
          code_lines <- c(
            "ggplot(data, aes(",
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
          "  # Violin with quantile lines \u2014 new in 4.0.0",
          "  geom_violin(",
          "    alpha = 0.6,",
          "    quantiles = c(0.25, 0.5, 0.75),",
          '    quantile.linetype = "dashed",',
          "    quantile.linewidth = 0.5",
          "  ) +"
        )
      } else if (geom == "label") {
        label_data <- data[
          seq(1, nrow(data), length.out = min(30, nrow(data))),
        ]
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
          "  # geom_label text.colour \u2014 new in 4.0.0",
          "  geom_label(",
          '    text.colour = "grey20",',
          "    size = 3, alpha = 0.8,",
          '    label.padding = unit(0.15, "lines")',
          "  ) +"
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
          '  # coord_cartesian(reverse) \u2014 new in 4.0.0',
          '  coord_cartesian(reverse = "xy") +'
        )
      }

      # --- Labels (use column names as-is for dictionary) ---
      label_dict <- stats::setNames(all_cols, all_cols)
      p <- p + labs(dictionary = label_dict)
      code_lines <- c(
        code_lines,
        '  # labs(dictionary) \u2014 new in 4.0.0',
        "  labs(dictionary = label_dict) +"
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
      plot_b64 <- tryCatch(
        {
          tmp <- tempfile(fileext = ".png")
          on.exit(unlink(tmp), add = TRUE)
          ggsave(tmp, p, width = 8, height = 4.5, dpi = 150, bg = "white")
          base64enc::base64encode(tmp)
        },
        error = function(e) {
          rlang::abort(
            c(
              "Failed to render the plot.",
              "x" = conditionMessage(e),
              "i" = "This may be caused by incompatible column types or missing data."
            ),
            parent = e
          )
        }
      )

      # Clean up trailing + from code
      code_text <- paste(code_lines, collapse = "\n")
      code_text <- sub("\\+\\s*$", "", code_text)

      list(
        plot = plot_b64,
        code = code_text,
        `_columns` = as.character(col_info)
      )
    },
    name = "build_ggplot",
    description = paste(
      "Build a ggplot2 visualization from provided data or built-in Palmer Penguins.",
      "Pass data_path (file path to CSV/Excel/Parquet) or data_csv (inline",
      "CSV text) to load session data. Once loaded, data persists across UI",
      "interactions. Column selects update automatically.",
      "Showcases ggplot2 4.0.0 features including ink/paper/accent theming,",
      "stat_manual(), stat_connect(), labs(dictionary), facet_wrap(space),",
      "coord_cartesian(reverse), and enhanced geom styling."
    ),
    arguments = list(
      data_path = ellmer::type_string(
        paste(
          "Path to a data file (CSV, TSV, Excel .xlsx/.xls, or Parquet).",
          "Once loaded, persists for subsequent calls."
        )
      ),
      data_csv = ellmer::type_string(
        "Data as inline CSV text. Once loaded, persists for subsequent calls."
      ),
      x_var = ellmer::type_string(
        "Numeric column for X axis (from the provided data)"
      ),
      y_var = ellmer::type_string(
        "Numeric column for Y axis (from the provided data)"
      ),
      color_var = ellmer::type_string(
        "Categorical column for color mapping (from the provided data)"
      ),
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
