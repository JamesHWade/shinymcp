# Generate MCP App from analysis

Produces HTML, tools, and server code for an MCP App based on the
analysis of a Shiny app.

## Usage

``` r
generate_mcp_app(analysis, ir, output_dir)
```

## Arguments

- analysis:

  A `ReactiveAnalysis` object from
  [`analyze_reactive_graph()`](https://jameshwade.github.io/shinymcp/reference/analyze_reactive_graph.md)

- ir:

  The original `ShinyAppIR` object

- output_dir:

  Directory to write generated files

## Value

The output directory path (invisibly)
