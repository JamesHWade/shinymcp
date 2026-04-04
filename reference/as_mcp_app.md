# Convert an object to an MCP App

S3 generic that converts various Shiny-related objects into an
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md). The
primary method converts `shiny.appobj` (from
[`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html)) by
parsing its UI and server to build tool definitions automatically.

## Usage

``` r
as_mcp_app(x, ...)

# S3 method for class 'shiny.appobj'
as_mcp_app(
  x,
  name = NULL,
  tools = NULL,
  selective = NULL,
  version = "0.1.0",
  ...
)

# S3 method for class 'McpApp'
as_mcp_app(x, ...)

# Default S3 method
as_mcp_app(x, ...)
```

## Arguments

- x:

  An object to convert. Currently supports:

  - `shiny.appobj` (from
    [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html))

  - `McpApp` (returned as-is)

  - A character path to a directory containing `app.R`, or a direct path
    to an app file

- ...:

  Additional arguments passed to methods.

- name:

  App name (used in resource URIs). Defaults to `"shinymcp-app"`.

- tools:

  Optional list of explicit
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  definitions. If provided, these are used instead of auto-generating
  tools from the reactive graph.

- selective:

  Logical. If `TRUE` (default when
  [`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
  annotations are present), only annotated elements are exposed. If
  `FALSE`, all detected inputs/outputs are exposed.

- version:

  App version string. Defaults to `"0.1.0"`.

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object.

## Examples

``` r
if (FALSE) { # \dontrun{
library(shiny)

ui <- fluidPage(
  selectInput("dataset", "Choose", c("mtcars", "iris")) |> bindMcp(),
  plotOutput("plot") |> bindMcp(),
  textOutput("summary") |> bindMcp()
)

server <- function(input, output, session) {
  output$plot <- renderPlot(plot(get(input$dataset)))
  output$summary <- renderText(paste("Rows:", nrow(get(input$dataset))))
}

# Convert and serve
shinyApp(ui, server) |> as_mcp_app(name = "explorer") |> serve()
} # }
```
