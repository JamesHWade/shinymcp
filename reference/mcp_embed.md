# Embed an MCP app inside a live Shiny session

When called inside a Shiny server context, this helper auto-registers a
live host instance and returns ready-to-render UI. Outside a live
session, provide an `id` and pair the result with
[`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_server.md).

## Usage

``` r
mcp_embed(
  app,
  id = NULL,
  trigger = c("debounce", "change", "submit", "manual"),
  debounce_ms = 250,
  height = "auto"
)
```

## Arguments

- app:

  An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  object.

- id:

  Optional DOM or module id.

- trigger:

  Interaction mode: `"debounce"`, `"change"`, `"submit"`, or `"manual"`.

- debounce_ms:

  Debounce interval in milliseconds.

- height:

  Preferred initial height.
