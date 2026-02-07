# Create an MCP text output

Generates a placeholder element for text output with MCP data
attributes. Uses a `<pre>` tag so R console/summary output renders with
monospace font and preserved whitespace.

## Usage

``` r
mcp_text(id)
```

## Arguments

- id:

  Output ID

## Value

An
[htmltools::tag](https://rstudio.github.io/htmltools/reference/builder.html)
object
