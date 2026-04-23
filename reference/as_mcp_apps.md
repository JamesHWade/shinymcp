# Split a parsed Shiny app into chat-sized MCP App scaffolds

Split a parsed Shiny app into chat-sized MCP App scaffolds

## Usage

``` r
as_mcp_apps(
  app,
  split = c("tool_group", "manual"),
  max_inputs_per_card = 5,
  compact_layout = TRUE
)
```

## Arguments

- app:

  A path to a Shiny app directory or a parsed `ShinyAppIR` object.

- split:

  Split strategy.

- max_inputs_per_card:

  Preferred chat-card input budget.

- compact_layout:

  Whether the generated UIs should prefer compact cards.

## Value

A list of
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
scaffold apps.
