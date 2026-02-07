# Convert a Shiny app to an MCP App

Parses a Shiny app, analyzes its reactive graph, and generates an MCP
App with tools and UI.

## Usage

``` r
convert_app(path, output_dir = NULL)
```

## Arguments

- path:

  Path to a Shiny app directory

- output_dir:

  Output directory for the generated MCP App. Defaults to `{path}_mcp/`.

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object (invisibly). Generated files are also written to `output_dir`.
