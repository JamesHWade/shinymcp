# Serve a Shiny module as an MCP App

Wraps a Shiny module (a UI function, and a server function, that take an
`id`) as an
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md). The
module's UI is the page.

With `handler`, a function of your own computes the module's outputs, as
tools for
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
do: its arguments are the module's input ids, without the namespace, and
it returns a list named by output ids.

Without it, the module's server function runs live, as with
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
and the tool the model calls takes the module's inputs by their
un-namespaced ids.

The same module can be shown in a shinychat conversation with
`shinychat::chat_tool_module()` and served here to MCP clients.

## Usage

``` r
mcp_tool_module(
  module_ui,
  module_server = NULL,
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

  A module UI function, `function(id)`.

- module_server:

  A module server function, `function(id, ...)`, that calls
  [`shiny::moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html).
  Not needed with `handler`.

- name:

  App and tool name.

- description:

  What the module does, for the model.

- handler:

  Optional function to use instead of running `module_server`.

- arguments:

  With `handler`, optional
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  argument types. Without them, the input schema is guessed from the
  handler's defaults.

- version:

  App version string.

- ...:

  Extra arguments passed to `module_server`.

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md).

## Shiny's own MCP support

Shiny is gaining MCP support of its own
(<https://github.com/rstudio/shiny/pull/4407>). Once it is released, it
will be the way to put a live Shiny app in a chat, and shinymcp will
stop serving live apps.
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md),
and `mcp_tool_module()` will take only apps built from tools, and
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
and the helpers for server functions
([`mcp_model_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md),
[`mcp_host_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_context.md),
and the rest) will be removed. For something the model should be able to
use on its own, rewrite that part of the app as tools with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md);
see
[`vignette("rewriting-as-tools")`](https://jameshwade.github.io/shinymcp/articles/rewriting-as-tools.md).

## See also

Other apps:
[`McpApp`](https://jameshwade.github.io/shinymcp/reference/McpApp.md),
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md),
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)

## Examples

``` r
if (FALSE) { # \dontrun{
library(shiny)

hist_ui <- function(id) {
  ns <- NS(id)
  tagList(
    sliderInput(ns("bins"), "Bins", min = 5, max = 50, value = 20),
    plotOutput(ns("plot"), height = "250px")
  )
}

# The module's UI, with a function in place of its server.
app <- mcp_tool_module(
  hist_ui,
  name = "eruptions",
  description = "Histogram of Old Faithful eruption times.",
  handler = function(bins = 20) {
    list(plot = mcp_result_plot(function() hist(faithful$eruptions, breaks = bins)))
  }
)
preview_app(app)

# The module's own server function, running live.
hist_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    output$plot <- renderPlot(hist(faithful$eruptions, breaks = input$bins))
  })
}
app <- mcp_tool_module(
  hist_ui,
  hist_server,
  name = "eruptions",
  description = "Histogram of Old Faithful eruption times."
)
} # }
```
