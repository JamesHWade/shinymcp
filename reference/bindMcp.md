# Mark a Shiny UI element for MCP exposure

Annotates a Shiny input or output tag with `data-shinymcp-*` attributes
so it can be discovered by the MCP JS bridge. Auto-detects whether the
tag is an input or output by inspecting Shiny's class conventions.

## Usage

``` r
bindMcp(tag, ...)

# S3 method for class 'shiny.tag'
bindMcp(tag, id = NULL, type = NULL, ...)

# S3 method for class 'shiny.tag.list'
bindMcp(tag, id = NULL, type = NULL, ...)

# Default S3 method
bindMcp(tag, ...)
```

## Arguments

- tag:

  A
  [shiny.tag](https://rstudio.github.io/htmltools/reference/builder.html)
  or
  [shiny.tag.list](https://rstudio.github.io/htmltools/reference/tagList.html)
  produced by a Shiny input or output function.

- ...:

  Reserved for future use.

- id:

  Override the input/output ID. If `NULL` (default), the ID is
  auto-detected from the tag structure.

- type:

  Override the output type (`"text"`, `"html"`, `"plot"`, or `"table"`).
  Only used for outputs. If `NULL`, auto-detected.

## Value

The modified
[htmltools::tag](https://rstudio.github.io/htmltools/reference/builder.html)
with MCP attributes stamped.

## Details

Use this as a pipe on standard Shiny UI elements:

    selectInput("x", "X", c("a", "b")) |> bindMcp()
    plotOutput("plot") |> bindMcp()

`bindMcp()` is idempotent: calling it on an element that already has
`data-shinymcp-input` or `data-shinymcp-output` attributes is a no-op.
