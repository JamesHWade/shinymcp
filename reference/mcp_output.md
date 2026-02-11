# Mark an element as an MCP output

Stamps `data-shinymcp-output` and `data-shinymcp-output-type` on a tag.
Use this to turn any container element into a target for tool result
output.

## Usage

``` r
mcp_output(tag, id = NULL, type = c("text", "html", "plot", "table"))
```

## Arguments

- tag:

  An
  [htmltools::tag](https://rstudio.github.io/htmltools/reference/builder.html)
  object.

- id:

  The output ID. If `NULL` (the default), reads the element's existing
  `id` attribute.

- type:

  Output type: `"text"`, `"html"`, `"plot"`, or `"table"`.

## Value

The modified
[htmltools::tag](https://rstudio.github.io/htmltools/reference/builder.html)
with output attributes stamped.
