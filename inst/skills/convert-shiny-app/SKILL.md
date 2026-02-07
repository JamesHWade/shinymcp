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
- For dynamic choices, use a fixed `mcp_select` and document valid choices
  in the tool description

### File Uploads

MCP Apps run inside an AI tool-use context and cannot handle file uploads
the way Shiny does. Alternatives:

- Accept file paths as text input (`mcp_text_input("file_path", "File path:")`)
- Have the tool read from a known directory
- Use `mcp_text_input` for pasting data directly

### Shiny Modules

Flatten modules into the top-level app. Each module's server logic becomes
one or more tools. Prefix tool names with the module name for clarity:

- `mod_chart_server` -> tool named `chart_update`
- `mod_filter_server` -> tool named `filter_apply`

### Plots

For `plotOutput`, use `mcp_plot(id)` and return a base64-encoded PNG from
the tool. The bridge will set it as an `<img>` src. Example:

```r
fun = function(...) {
  tmp <- tempfile(fileext = ".png")
  png(tmp, width = 600, height = 400)
  plot(...)
  dev.off()
  base64 <- base64enc::base64encode(tmp)
  unlink(tmp)
  paste0("data:image/png;base64,", base64)
}
```

### Tables

For `tableOutput`, use `mcp_table(id)` and return an HTML table string.
You can use `htmltools::tags$table(...)` or `knitr::kable(df, format = "html")`.

## Important Notes

- The JS bridge handles all input-to-tool-to-output communication automatically
- Tools are stateless -- do not rely on global mutable state between calls
- Keep tool argument types simple (strings, numbers, booleans)
- Provide clear descriptions for each tool argument so the AI knows what to pass
- Test the converted app with `serve(app)` to verify it works
