# Create an MCP App from a Shiny module

Wraps a standard Shiny module (UI function + server function) as an
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md). The
module UI is rendered with MCP-compatible attributes, and a tool
definition is created that maps to the module's inputs and outputs. If a
`handler` is provided, the tool is fully functional; otherwise, a stub
handler is generated as a placeholder.

## Usage

``` r
mcp_tool_module(
  module_ui,
  module_server,
  name,
  description,
  handler = NULL,
  arguments = NULL,
  version = "0.1.0",
  ...
)
```

## Arguments

- module_ui:

  A Shiny module UI function that accepts an `id` argument (e.g.,
  `function(id) { ns <- NS(id); tagList(...) }`).

- module_server:

  A Shiny module server function. Currently stored as metadata for
  future headless Shiny session support, which will allow the module
  server to execute reactively when tools are called.

- name:

  Tool/app name. Used in `ui://` resource URIs.

- description:

  Human-readable description of what the tool does.

- handler:

  Optional tool handler function. If provided, this function is called
  when the MCP tool is invoked. Its arguments should match the module's
  input IDs. If `NULL`, a stub handler is generated.

- arguments:

  Optional list of
  [`ellmer::type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html),
  [`ellmer::type_number()`](https://ellmer.tidyverse.org/reference/type_boolean.html),
  etc. for the tool's input schema. If `NULL`, arguments are
  auto-detected from the rendered module UI.

- version:

  App version string.

- ...:

  Additional arguments stored as module metadata (e.g., shared reactive
  values to pass to the module server when headless support lands).

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object.

## Details

This mirrors `shinychat::chat_tool_module()` for the MCP runtime — the
same module can be used in both contexts.

## Examples

``` r
if (FALSE) { # \dontrun{
library(shiny)

# Define a standard Shiny module
hist_ui <- function(id) {
  ns <- NS(id)
  tagList(
    sliderInput(ns("bins"), "Bins:", min = 5, max = 50, value = 25),
    plotOutput(ns("plot"), height = "250px")
  )
}

hist_server <- function(id, dataset) {
  moduleServer(id, function(input, output, session) {
    output$plot <- renderPlot({
      hist(dataset(), breaks = input$bins, col = "#007bc2")
    })
  })
}

# Create and serve as MCP App
app <- mcp_tool_module(
  hist_ui, hist_server,
  name = "histogram",
  description = "Show an interactive histogram",
  handler = function(bins = 25) {
    tmp <- tempfile(fileext = ".png")
    grDevices::png(tmp, width = 600, height = 250)
    hist(faithful$eruptions, breaks = bins, col = "#007bc2")
    grDevices::dev.off()
    list(plot = base64enc::base64encode(tmp))
  }
)
serve(app)
} # }
```
