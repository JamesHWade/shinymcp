# Automatic Shiny App Conversion

shinymcp includes an automatic conversion pipeline that translates Shiny
apps into MCP Apps. It parses the UI and server code, analyzes the
reactive dependency graph, and generates a working MCP App with tools,
components, and a server entrypoint.

This vignette covers the
[`convert_app()`](https://jameshwade.github.io/shinymcp/reference/convert_app.md)
pipeline and each of its stages.

## Quick start

Point
[`convert_app()`](https://jameshwade.github.io/shinymcp/reference/convert_app.md)
at a Shiny app directory:

``` r
library(shinymcp)

convert_app("path/to/my-shiny-app")
```

    ── Converting Shiny app to MCP App ────────────────────
    Source: path/to/my-shiny-app
    Output: path/to/my-shiny-app_mcp

    ── Parsing
    ℹ Found 4 input(s) and 2 output(s)
    ℹ Complexity: medium

    ── Analyzing
    ℹ Identified 1 tool group(s)

    ── Generating
    ✔ Generated MCP App in path/to/my-shiny-app_mcp

The generated directory contains:

| File                  | Purpose                                                                                                  |
|-----------------------|----------------------------------------------------------------------------------------------------------|
| `app.R`               | Entrypoint that wires up UI and tools                                                                    |
| `ui.html`             | UI built with shinymcp components                                                                        |
| `tools.R`             | [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html) definitions for each reactive group |
| `server.R`            | Server setup with state environment                                                                      |
| `CONVERSION_NOTES.md` | Review notes (complex apps only)                                                                         |

## The pipeline

[`convert_app()`](https://jameshwade.github.io/shinymcp/reference/convert_app.md)
runs three stages in sequence:

    parse_shiny_app() → analyze_reactive_graph() → generate_mcp_app()

You can run each stage independently for finer control.

### Stage 1: Parse

[`parse_shiny_app()`](https://jameshwade.github.io/shinymcp/reference/parse_shiny_app.md)
reads the app’s R source and extracts a structured intermediate
representation (IR):

``` r
ir <- parse_shiny_app("path/to/my-shiny-app")
ir
```

    ── Shiny App IR ───────────────────────────────────────
    Path: path/to/my-shiny-app
    Inputs: 4
    Outputs: 2
    Reactives: 1
    Observers: 0
    Complexity: medium
    Input refs: species, x_var, y_var, trend

The parser handles both `app.R` (single-file) and `ui.R`/`server.R`
(split-file) apps. It walks the AST to extract:

- **Inputs**: All `*Input()` calls with their IDs, types, labels, and
  arguments
- **Outputs**: All `*Output()` calls with their IDs and types
- **Server body**: The body of the `server` function
- **Reactives**: All `reactive()` expressions with their input
  dependencies
- **Observers**: All `observe()` and `observeEvent()` calls
- **Input refs**: Every `input$name` and `input[["name"]]` reference

The parser classifies apps by complexity:

| Complexity  | Criteria                                   |
|-------------|--------------------------------------------|
| **simple**  | Up to 3 inputs, no reactives, no observers |
| **medium**  | Up to 8 inputs, up to 3 reactives          |
| **complex** | Everything else                            |

### Stage 2: Analyze

[`analyze_reactive_graph()`](https://jameshwade.github.io/shinymcp/reference/analyze_reactive_graph.md)
takes the IR and builds a dependency graph:

``` r
analysis <- analyze_reactive_graph(ir)
analysis
```

    ── Reactive Analysis ──────────────────────────────────
    Nodes: 7
    Edges: 6
    Tool groups: 1

The analyzer:

1.  **Builds a dependency graph** — nodes are inputs, reactives, and
    outputs; edges represent data flow (`input$x` used in
    `reactive(...)` used in `renderPlot(...)`)
2.  **Finds connected components** — uses union-find to group nodes that
    are transitively connected
3.  **Maps components to tool groups** — each connected component
    becomes one tool with the component’s inputs as arguments and
    outputs as return values
4.  **Flags unresolvable patterns** — dynamic UI, file uploads, download
    handlers, and observers with side effects

For example, a Shiny app where a `reactive()` feeds both `renderPlot()`
and `renderText()` produces a single tool group containing all related
inputs and both outputs.

### Stage 3: Generate

[`generate_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/generate_mcp_app.md)
writes the MCP App files:

``` r
generate_mcp_app(analysis, ir, output_dir = "my-app-mcp")
```

It generates:

- **UI code** using shinymcp components
  ([`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md),
  [`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md),
  etc.) mapped from the original Shiny inputs and outputs
- **Tool definitions** using
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  with proper argument types (`type_string`, `type_number`,
  `type_boolean`) and tool annotations
- **Server entrypoint** that sources the tools and sets up a state
  environment
- **Conversion notes** (for complex apps) listing what needs manual
  review

## What gets converted automatically

The pipeline handles these Shiny patterns out of the box:

| Shiny pattern                           | MCP App equivalent                                                                                                                                                 |
|-----------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `selectInput()`                         | [`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)                                                                                    |
| `textInput()`                           | [`mcp_text_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_text_input.md)                                                                            |
| `numericInput()`                        | [`mcp_numeric_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_numeric_input.md)                                                                      |
| `checkboxInput()`                       | [`mcp_checkbox()`](https://jameshwade.github.io/shinymcp/reference/mcp_checkbox.md)                                                                                |
| `sliderInput()`                         | [`mcp_slider()`](https://jameshwade.github.io/shinymcp/reference/mcp_slider.md)                                                                                    |
| `radioButtons()`                        | [`mcp_radio()`](https://jameshwade.github.io/shinymcp/reference/mcp_radio.md) (or [`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)) |
| `actionButton()`                        | [`mcp_action_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_action_button.md)                                                                      |
| `plotOutput()`                          | [`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md) with base64 PNG rendering                                                              |
| `textOutput()` / `verbatimTextOutput()` | [`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_text.md)                                                                                        |
| `tableOutput()`                         | [`mcp_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_table.md)                                                                                      |
| `htmlOutput()` / `uiOutput()`           | [`mcp_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_html.md)                                                                                        |
| `reactive()` chains                     | Flattened into tool function body                                                                                                                                  |
| `app.R` (single file)                   | Fully supported                                                                                                                                                    |
| `ui.R` / `server.R` (split files)       | Fully supported                                                                                                                                                    |

## What needs manual review

The generated tools contain **placeholder function bodies**. You need to
copy the actual computation logic from the original `render*()`
functions into the generated tool functions.

For simple apps, this is straightforward — the tool arguments match the
original inputs and the return structure matches the outputs. For
complex apps, review these areas:

### Reactive chain logic

The generator creates the tool skeleton but uses placeholder code like
`paste("Result for:", x)`. Replace this with the actual computation:

``` r
# Generated placeholder:
update_scatter_and_stats <- ellmer::tool(
  fun = function(species, x_var, y_var, trend) {
    # TODO: Insert computation logic from original render function here
    paste("Result for:", species, x_var, y_var, trend)
  },
  # ...
)

# After manual review — fill in the real logic:
update_scatter_and_stats <- ellmer::tool(
  fun = function(species = "All", x_var = "bill_length_mm",
                 y_var = "bill_depth_mm", trend = FALSE) {
    data <- palmerpenguins::penguins[complete.cases(palmerpenguins::penguins), ]
    if (species != "All") data <- data[data$species == species, ]

    p <- ggplot2::ggplot(data, ggplot2::aes(.data[[x_var]], .data[[y_var]])) +
      ggplot2::geom_point()
    if (isTRUE(trend)) p <- p + ggplot2::geom_smooth(method = "lm", se = FALSE)

    tmp <- tempfile(fileext = ".png")
    ggplot2::ggsave(tmp, p, width = 7, height = 4, dpi = 144, bg = "white")
    on.exit(unlink(tmp))

    list(
      scatter = base64enc::base64encode(tmp),
      stats = paste(capture.output(summary(data)), collapse = "\n")
    )
  },
  # ...
)
```

### Dynamic UI

`uiOutput()` / `renderUI()` is flagged as a warning. Replace with
[`mcp_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_html.md)
and return HTML strings from the tool:

``` r
# Instead of renderUI(), return HTML from the tool:
fun = function(show_detail = FALSE) {
  html <- if (show_detail) {
    "<div><h3>Details</h3><p>More info here</p></div>"
  } else {
    ""
  }
  list(detail_panel = html)
}
```

### Observers and side effects

`observe()` and `observeEvent()` calls are flagged since they often
perform side effects (database writes, file operations) that don’t map
cleanly to stateless tool calls. Review each observer and decide:

- Can it be folded into a tool’s return value?
- Does it need to write to the file system? (Use temp files)
- Can it be removed entirely?

### File uploads

`fileInput()` is not supported. The generator warns about this. Use
[`mcp_text_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_text_input.md)
for file paths instead, or have the tool read from a known directory.

## Controlling output

By default,
[`convert_app()`](https://jameshwade.github.io/shinymcp/reference/convert_app.md)
writes to `{path}_mcp/`. Specify a custom output directory:

``` r
convert_app("my-app", output_dir = "output/my-mcp-app")
```

## After conversion

Once you’ve filled in the tool bodies:

1.  **Test locally** with `serve(app)` to verify the UI renders and
    tools respond
2.  **Register with Claude Desktop** by adding the app to your config
3.  **Iterate** — adjust layouts with bslib, tweak tool descriptions for
    better AI interactions

For a detailed walkthrough of building an MCP App from scratch (without
the automatic pipeline), see
[`vignette("converting-shiny-apps")`](https://jameshwade.github.io/shinymcp/articles/converting-shiny-apps.md).
