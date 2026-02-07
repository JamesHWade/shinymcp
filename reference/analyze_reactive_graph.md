# Analyze reactive graph from parsed Shiny app

Builds a dependency graph from inputs through reactives to outputs, and
groups connected components into tool groups.

## Usage

``` r
analyze_reactive_graph(ir)
```

## Arguments

- ir:

  A `ShinyAppIR` object from
  [`parse_shiny_app()`](https://jameshwade.github.io/shinymcp/reference/parse_shiny_app.md)

## Value

A `ReactiveAnalysis` list with components: `graph`, `tool_groups`,
`warnings`
