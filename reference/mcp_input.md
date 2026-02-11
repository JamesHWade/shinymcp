# Mark an element as an MCP input

Stamps `data-shinymcp-input` on a tag or its first form-element
descendant. Use this as an escape hatch when auto-detection by tool
argument name doesn't work (e.g., custom widgets or elements whose `id`
doesn't match the tool argument name).

## Usage

``` r
mcp_input(tag, id = NULL)
```

## Arguments

- tag:

  An
  [htmltools::tag](https://rstudio.github.io/htmltools/reference/builder.html)
  object (e.g., from
  [`shiny::selectInput()`](https://rdrr.io/pkg/shiny/man/selectInput.html)
  or `bslib::input_select()`).

- id:

  The input ID to register. If `NULL` (the default), reads the element's
  existing `id` attribute.

## Value

The modified
[htmltools::tag](https://rstudio.github.io/htmltools/reference/builder.html)
with `data-shinymcp-input` stamped.
