# Convert a Shiny app to an MCP App

Parses a Shiny app, analyzes its reactive graph, and generates an MCP
App with tools and UI.

## Usage

``` r
convert_app(
  path,
  output_dir = NULL,
  mode = c("scaffold", "cards"),
  selective = TRUE,
  max_inputs_per_card = 5,
  compact_layout = TRUE
)
```

## Arguments

- path:

  Path to a Shiny app directory

- output_dir:

  Output directory for the generated MCP App. Defaults to `{path}_mcp/`.

- mode:

  Conversion mode. `"scaffold"` generates one scaffold app. `"cards"`
  generates compact per-group scaffold cards.

- selective:

  Whether card mode should split by connected tool groups.

- max_inputs_per_card:

  Preferred chat-card input budget.

- compact_layout:

  Whether generated cards should prefer compact layouts.

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object or list of
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
objects (invisibly). Generated scaffold files are also written to
`output_dir`.
