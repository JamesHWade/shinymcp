# shinymcp

shinymcp converts [Shiny](https://shiny.posit.co/) apps into [MCP
Apps](https://modelcontextprotocol.io/) — interactive UIs that render
directly inside AI chat interfaces like Claude Desktop.

## Installation

You can install the development version of shinymcp from
[GitHub](https://github.com/) with:

``` r
# install.packages("pak")
pak::pak("JamesHWade/shinymcp")
```

## Quick start

An MCP App has two parts: **UI components** that render in the chat
interface, and **tools** that run R code when inputs change.

``` r
library(shinymcp)
library(bslib)

ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "Dataset Explorer",
  sidebar = sidebar(
    mcp_select("dataset", "Choose dataset", c("mtcars", "iris", "pressure"))
  ),
  card(
    card_header("Summary"),
    mcp_text("summary")
  )
)

tools <- list(
  ellmer::tool(
    fun = function(dataset = "mtcars") {
      data <- get(dataset, envir = asNamespace("datasets"))
      paste(capture.output(summary(data)), collapse = "\n")
    },
    name = "get_summary",
    description = "Get summary statistics for the selected dataset",
    arguments = list(
      dataset = ellmer::type_string("Dataset name")
    )
  )
)

app <- mcp_app(ui, tools, name = "dataset-explorer")
serve(app)
```

Save this as `app.R`, then register it in your Claude Desktop config:

``` json
{
  "mcpServers": {
    "dataset-explorer": {
      "command": "Rscript",
      "args": ["/path/to/app.R"]
    }
  }
}
```

Restart Claude Desktop. When the tool is invoked, an interactive UI
appears inline in the conversation. Changing the dropdown calls the tool
and updates the output — no page reload needed.

## Converting a Shiny app

The core idea: **flatten your reactive graph into tool functions**.

Each connected group of inputs → reactives → outputs becomes a single
tool that takes input values as arguments and returns a named list of
outputs.

``` r
# --- Shiny ---
server <- function(input, output, session) {
  filtered <- reactive({
    penguins[penguins$species == input$species, ]
  })
  output$scatter <- renderPlot({
    ggplot(filtered(), aes(x, y)) + geom_point()
  })
  output$stats <- renderPrint({
    summary(filtered())
  })
}

# --- MCP App tool ---
ellmer::tool(
  fun = function(species = "Adelie") {
    filtered <- penguins[penguins$species == species, ]

    # Render plot to base64 PNG
    tmp <- tempfile(fileext = ".png")
    ggplot2::ggsave(tmp, my_plot, width = 7, height = 4, dpi = 144)
    on.exit(unlink(tmp))

    list(
      scatter = base64enc::base64encode(tmp),
      stats = paste(capture.output(summary(filtered)), collapse = "\n")
    )
  },
  name = "explore",
  description = "Filter and visualize penguins",
  arguments = list(
    species = ellmer::type_string("Penguin species")
  )
)
```

Return keys (`scatter`, `stats`) must match output IDs in the UI
(`mcp_plot("scatter")`, `mcp_text("stats")`). The bridge routes each
value to the correct output element.

For a full worked example converting a Shiny app step-by-step, see
[`vignette("converting-shiny-apps")`](https://jameshwade.github.io/shinymcp/articles/converting-shiny-apps.md).

## Automatic conversion

shinymcp includes a parse-analyze-generate pipeline that can scaffold an
MCP App from an existing Shiny app:

``` r
convert_app("path/to/my-shiny-app")
```

This parses the UI and server code, maps the reactive dependency graph
into tool groups, and writes a working MCP App with tools, components,
and a server entrypoint. The generated tool bodies contain placeholders
that you fill in with the actual computation logic.

For details, see
[`vignette("automatic-conversion")`](https://jameshwade.github.io/shinymcp/articles/automatic-conversion.md).

### AI-assisted conversion

For complex Shiny apps, shinymcp ships a
[deputy](https://github.com/JamesHWade/deputy) skill that guides an AI
agent through the conversion process. The skill handles dynamic UI,
modules, file uploads, and other patterns that require human judgment.
See `inst/skills/convert-shiny-app/SKILL.md` for the full instructions.

## Component reference

shinymcp provides input and output components that mirror Shiny
functions:

### Inputs

| Shiny             | shinymcp                                                                                      |
|-------------------|-----------------------------------------------------------------------------------------------|
| `selectInput()`   | [`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)               |
| `textInput()`     | [`mcp_text_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_text_input.md)       |
| `numericInput()`  | [`mcp_numeric_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_numeric_input.md) |
| `checkboxInput()` | [`mcp_checkbox()`](https://jameshwade.github.io/shinymcp/reference/mcp_checkbox.md)           |
| `sliderInput()`   | [`mcp_slider()`](https://jameshwade.github.io/shinymcp/reference/mcp_slider.md)               |
| `radioButtons()`  | [`mcp_radio()`](https://jameshwade.github.io/shinymcp/reference/mcp_radio.md)                 |
| `actionButton()`  | [`mcp_action_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_action_button.md) |

### Outputs

| Shiny                                   | shinymcp                                                                      | Notes                                  |
|-----------------------------------------|-------------------------------------------------------------------------------|----------------------------------------|
| `textOutput()` / `verbatimTextOutput()` | [`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_text.md)   | Renders in `<pre>` with monospace font |
| `plotOutput()`                          | [`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)   | Tool returns base64-encoded PNG        |
| `tableOutput()`                         | [`mcp_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_table.md) | Tool returns HTML table string         |
| `htmlOutput()`                          | [`mcp_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_html.md)   | Tool returns raw HTML                  |

Each component generates HTML with `data-shinymcp-*` attributes that the
JS bridge reads at runtime:

``` r
mcp_select("color", "Color", c("red", "green", "blue"))
# <select data-shinymcp-input="color" ...>

mcp_plot("my_plot")
# <div data-shinymcp-output="my_plot" data-shinymcp-output-type="plot" ...>
```

## Examples

shinymcp ships with example apps:

``` r
# Minimal: select input + text output
system.file("examples", "hello-mcp", "app.R", package = "shinymcp")

# Full dashboard: Palmer Penguins with ggplot2 scatter plot, multiple
# inputs (species filter, axis selectors, trend line toggle), and
# summary statistics
system.file("examples", "penguins", "app.R", package = "shinymcp")
```

## How it works

MCP Apps render inside sandboxed iframes in the AI chat interface. A
lightweight JavaScript bridge (no npm dependencies) handles
communication via postMessage/JSON-RPC:

1.  User changes an input → bridge collects all input values
2.  Bridge sends a `tools/call` request to the host
3.  Host proxies the call to the MCP server (your R process)
4.  R tool function runs, returns results
5.  Bridge updates output elements with the response

The bridge also implements the MCP Apps initialization handshake
(`ui/initialize`), auto-resize notifications, and teardown handling.

## Related packages

- [ellmer](https://ellmer.tidyverse.org/) — LLM framework that shinymcp
  uses for tool definitions
- [bslib](https://rstudio.github.io/bslib/) — Bootstrap-based layout and
  theming for the UI
- [mcptools](https://github.com/posit-dev/mcptools) — MCP server
  framework (shinymcp extends this with resource support)
- [deputy](https://github.com/JamesHWade/deputy) — Agentic AI framework
  with a bundled skill for AI-assisted Shiny conversion
