# Serve an MCP App

Starts an MCP server that serves the app's tools and ui:// resources.

## Usage

``` r
serve(app, type = c("stdio", "http"), port = 8080, ...)
```

## Arguments

- app:

  An McpApp object, or a path to a Shiny app (which will be
  auto-converted via
  [`convert_app()`](https://jameshwade.github.io/shinymcp/reference/convert_app.md)).

- type:

  Server transport type: `"stdio"` or `"http"`.

- port:

  Port for HTTP transport (default 8080).

- ...:

  Additional arguments (currently unused).
