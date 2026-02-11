# Convert Shiny App to MCP App

You are converting a Shiny application into an MCP App powered by shinymcp.
Follow these steps carefully.

## Conversion Approach

MCP Apps replace Shiny's reactive server with AI-invoked tools. Instead of
`reactive()` and `observe()`, the AI calls tools that return values which the
JS bridge routes to output elements in the browser. The UI is plain HTML with
data attributes; no Shiny server is required.

## Step-by-Step Process

### 1. Read the Shiny Source

Read the entire app (either `app.R` or the `ui.R`/`server.R` pair). Identify:

- All inputs (`selectInput`, `numericInput`, `textInput`, `sliderInput`, etc.)
- All outputs (`textOutput`, `plotOutput`, `tableOutput`, `uiOutput`, etc.)
- Reactive expressions and observers that connect inputs to outputs

### 2. Map Inputs to MCP Components

| Shiny Input           | MCP Component                                      |
|-----------------------|----------------------------------------------------|
| `selectInput`         | `mcp_select(id, label, choices)`                   |
| `numericInput`        | `mcp_numeric_input(id, label, value, min, max)`    |
| `textInput`           | `mcp_text_input(id, label)`                        |
| `sliderInput`         | `mcp_slider(id, label, min, max, value)`           |
| `checkboxInput`       | `mcp_checkbox(id, label)`                          |
| `actionButton`        | `mcp_button(id, label)`                            |
| `radioButtons`        | `mcp_select(id, label, choices)` (use select)      |
| `fileInput`           | See "File Uploads" below                           |

### 3. Map Outputs to MCP Components

| Shiny Output          | MCP Component                                      |
|-----------------------|----------------------------------------------------|
| `textOutput`          | `mcp_text(id)`                                     |
| `verbatimTextOutput`  | `mcp_text(id)`                                     |
| `plotOutput`          | `mcp_plot(id)`                                     |
| `tableOutput`         | `mcp_table(id)`                                    |
| `htmlOutput`          | `mcp_html(id)`                                     |
| `uiOutput`            | `mcp_html(id)` (render as HTML string)             |

### 4. Convert Reactive Logic to Tools

Group related reactive chains into tools. Each tool should:

- Accept the relevant input values as arguments
- Perform the computation that the reactive expressions did
- Return a named list mapping output IDs to their rendered values

**Simple apps**: One tool per output, or one tool that returns all outputs.

**Reactive chains**: If output B depends on reactive A, which depends on
inputs X and Y, create a single tool that takes X and Y and returns B.
Flatten the chain -- tools are stateless function calls.

**Example**: A Shiny app with `reactive({ filter(data, col == input$x) })`
feeding both a text summary and a table becomes one tool:

```r
ellmer::tool(
  fun = function(x = "default") {
    filtered <- dplyr::filter(data, col == x)
    list(
      summary_text = paste(nrow(filtered), "rows"),
      data_table = render_table_html(filtered)
    )
  },
  name = "filter_data",
  description = "Filter data by column value and return summary and table",
  arguments = list(
    x = ellmer::type_string("Column filter value")
  )
)
```

### 5. Assemble the MCP App

```r
library(shinymcp)

ui <- htmltools::tagList(
  # Inputs
  mcp_select("x", "Filter by:", choices),
  # Outputs
  mcp_text("summary_text"),
  mcp_table("data_table")
)

tools <- list(filter_data_tool)

app <- mcp_app(ui, tools, name = "my-app")
serve(app)
```

## Special Cases

### Dynamic UI (`uiOutput` / `renderUI`)

MCP Apps do not support dynamic UI generation from the server. Instead:

- Use `mcp_html(id)` and return rendered HTML strings from tools
- For conditional visibility, return empty strings when hidden
- For dynamic choices, see "Dynamic Select Updates" below

### Accepting Session Data (`data_path` / `data_csv` Pattern)

When the Shiny app works with a fixed dataset but the MCP App should let
the AI pass data from the conversation, add `data_path` and/or `data_csv`
tool arguments. This is common for analysis/visualization apps where the
user may want to explore their own data.

**Why persistence matters:** The JS bridge only sends tool arguments that
have matching DOM elements. `data_path` and `data_csv` have no DOM elements
(the AI provides them directly), so UI-triggered calls (e.g. user changes a
dropdown) arrive *without* them. You must persist the active dataset
server-side so it survives across calls.

#### Setup

1. **Keep a default dataset** so the app works standalone:

```r
default_data <- palmerpenguins::penguins[complete.cases(palmerpenguins::penguins), ]

# Persists across tool calls — the bridge can't send data_path/data_csv
# on UI-triggered calls, so we remember the last loaded data here.
active_data_env <- new.env(parent = emptyenv())
active_data_env$df <- default_data
active_data_env$path <- NULL
```

2. **Add `data_path` and `data_csv` as tool arguments** with no matching
   DOM element. `data_path` supports multiple file formats; `data_csv` is
   a convenience for small inline data:

```r
arguments = list(
  data_path = ellmer::type_string(
    "Path to a data file (CSV, TSV, Excel .xlsx/.xls, or Parquet).
     Once loaded, persists for subsequent calls."
  ),
  data_csv = ellmer::type_string(
    "Data as inline CSV text. Once loaded, persists for subsequent calls."
  ),
  # ... other arguments ...
)
```

3. **Load data with a clear priority chain** in the tool function:

```r
fun = function(data_path = "", data_csv = "", x_var = "col1", ...) {
  # Priority: data_path > data_csv > last active data > default
  new_data_loaded <- FALSE
  if (nzchar(data_path)) {
    if (!file.exists(data_path)) {
      rlang::abort(c(
        sprintf("Data file not found: '%s'", data_path),
        "i" = "Supported formats: CSV, TSV, Excel (.xlsx/.xls), Parquet."
      ))
    }
    ext <- tolower(tools::file_ext(data_path))
    supported <- c("csv", "tsv", "xlsx", "xls", "parquet")
    if (!ext %in% supported) {
      rlang::abort(c(
        sprintf("Unsupported file extension: '.%s'", ext),
        "i" = sprintf("Supported formats: %s.", paste(supported, collapse = ", "))
      ))
    }
    data <- tryCatch(
      switch(ext,
        csv = read.csv(data_path, stringsAsFactors = TRUE),
        tsv = read.delim(data_path, stringsAsFactors = TRUE),
        xlsx = , xls = { readxl::read_excel(data_path) },
        parquet = { as.data.frame(arrow::read_parquet(data_path)) }
      ),
      error = function(e) {
        rlang::abort(c(
          sprintf("Failed to read data file: '%s'", data_path),
          "x" = conditionMessage(e)
        ), parent = e)
      }
    )
    data <- as.data.frame(data)
    new_data_loaded <- TRUE
  } else if (nzchar(data_csv)) {
    data <- tryCatch(
      read.csv(text = data_csv, stringsAsFactors = TRUE),
      error = function(e) {
        rlang::abort(c(
          "Failed to parse inline CSV data.",
          "x" = conditionMessage(e)
        ), parent = e)
      }
    )
    new_data_loaded <- TRUE
  } else {
    data <- active_data_env$df
  }

  if (nrow(data) == 0L) {
    rlang::abort("Loaded data has zero rows.")
  }

  # Validate data suitability, then persist
  # (defer persistence so bad data doesn't get stuck in active_data_env)
  if (new_data_loaded) {
    active_data_env$df <- data
    active_data_env$path <- if (nzchar(data_path)) data_path else {
      tmp <- tempfile(fileext = ".csv")
      write.csv(data, tmp, row.names = FALSE)
      tmp
    }
  }
  # ... use data ...
}
```

This handles all the ways data can arrive:
- **User uploads a file** (Excel, CSV, etc.) → AI passes `data_path`
- **AI generates data with code** → saves to temp file → passes `data_path`
- **Small inline data** → AI passes `data_csv`
- **User changes a dropdown** → bridge sends UI inputs only → tool reuses
  `active_data_env$df`

4. **Validate column arguments** against the actual data. Error early if
   the data lacks the required column types (e.g. at least 2 numeric columns
   for a scatter plot). Fall back to the first appropriate column only when
   a specific column name is stale after a data change
5. **Return column metadata** so select dropdowns can update (see next section)

### Dynamic Select Updates

When data changes at runtime (e.g. via `data_csv`), select inputs need to
reflect the new columns. Use a hidden output + MutationObserver pattern:

1. **Add a hidden `mcp_text` output** to the UI:

```r
tags$div(style = "display:none;", mcp_text("_columns"))
```

2. **Return column metadata as JSON** from the tool alongside other results:

```r
col_info <- jsonlite::toJSON(list(
  numeric = names(data)[vapply(data, is.numeric, logical(1))],
  categorical = names(data)[vapply(data, function(x)
    is.character(x) || is.factor(x), logical(1))]
), auto_unbox = FALSE)

list(plot = plot_b64, code = code_text, `_columns` = as.character(col_info))
```

3. **Add a `<script>` that watches the hidden output** and rebuilds select
   options using safe DOM methods (no innerHTML):

```r
tags$script(HTML("
  (function() {
    var colEl = document.querySelector(
      '[data-shinymcp-output=\"_columns\"]'
    );
    if (!colEl) return;
    new MutationObserver(function() {
      var raw = colEl.textContent;
      if (!raw || !raw.trim()) return;
      try { var info = JSON.parse(raw); } catch(e) {
        console.error('[shinymcp] Failed to parse column metadata:', e.message);
        return;
      }
      updateSelect('x_var', info.numeric);
      updateSelect('y_var', info.numeric);
      updateSelectWithNone('color_var', info.categorical);
      updateSelectWithNone('facet_var', info.categorical);
    }).observe(colEl, { childList: true, characterData: true, subtree: true });

    function clearSelect(sel) {
      while (sel.firstChild) sel.removeChild(sel.firstChild);
    }
    function updateSelect(id, values) {
      var sel = document.getElementById(id);
      if (!sel) { console.warn('[shinymcp] Select not found: #' + id); return; }
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
    }
    function updateSelectWithNone(id, values) {
      var sel = document.getElementById(id);
      if (!sel) { console.warn('[shinymcp] Select not found: #' + id); return; }
      if (!Array.isArray(values)) return;
      var cur = sel.value;
      clearSelect(sel);
      var none = document.createElement('option');
      none.value = 'none'; none.textContent = 'None';
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
"))
```

The key insight: the existing `structuredContent` → `updateOutput()` pipeline
pushes the JSON into the hidden element, and the MutationObserver picks it up
to refresh the selects. No new bridge changes needed.

See `inst/examples/ggplot-builder/app.R` for a full working example.

### File Uploads

MCP Apps run inside an AI tool-use context and cannot handle file uploads
the way Shiny does. Instead, use the `data_path` / `data_csv` pattern above:

- **Uploaded files**: The AI receives the file path and passes it as
  `data_path`. The tool auto-detects format by extension (CSV, TSV, Excel,
  Parquet)
- **Inline data**: The AI passes small datasets as `data_csv` text
- **AI-generated data**: The AI writes to a temp file and passes `data_path`

The `data_path` argument replaces Shiny's `fileInput()` — instead of the
user uploading directly to the app, the AI mediates the file access.

### Shiny Modules

Flatten modules into the top-level app. Each module's server logic becomes
one or more tools. Prefix tool names with the module name for clarity:

- `mod_chart_server` -> tool named `chart_update`
- `mod_filter_server` -> tool named `filter_apply`

### Plots

For `plotOutput`, use `mcp_plot(id)` and return a base64-encoded PNG from
the tool. The bridge wraps it in an `<img>` tag automatically. Example:

```r
fun = function(...) {
  tmp <- tempfile(fileext = ".png")
  grDevices::png(tmp, width = 600, height = 400, res = 96)
  plot(...)
  grDevices::dev.off()
  on.exit(unlink(tmp))
  base64enc::base64encode(tmp)
}
```

For ggplot2 plots, use `ggsave()`:

```r
fun = function(...) {
  p <- ggplot2::ggplot(...) + ggplot2::geom_point()
  tmp <- tempfile(fileext = ".png")
  ggplot2::ggsave(tmp, p, width = 7, height = 4, dpi = 144, bg = "white")
  on.exit(unlink(tmp))
  base64enc::base64encode(tmp)
}
```

When returning multiple outputs (plot + text), use a named list:

```r
fun = function(...) {
  # ... generate plot_b64 and summary_text ...
  list(my_plot = plot_b64, my_text = summary_text)
}
```

The keys must match the output IDs in the UI (`mcp_plot("my_plot")`,
`mcp_text("my_text")`). The server returns these as `structuredContent`
and the bridge routes each value to the correct output element.

### Tables

For `tableOutput`, use `mcp_table(id)` and return an HTML table string.
You can use `htmltools::tags$table(...)` or `knitr::kable(df, format = "html")`.

## Important Notes

- The JS bridge handles all input-to-tool-to-output communication automatically
- Tools are generally stateless. The exception is session data persistence
  (e.g. `active_data_env`) for the `data_path`/`data_csv` pattern, where
  data must survive across UI-triggered tool calls that cannot resend it
- Keep tool argument types simple (strings, numbers, booleans)
- Provide clear descriptions for each tool argument so the AI knows what to pass
- Test the converted app with `serve(app)` to verify it works
