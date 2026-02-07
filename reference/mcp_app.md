# Create an MCP App

Convenience function to create an
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object.

## Usage

``` r
mcp_app(
  ui,
  tools = list(),
  name = "shinymcp-app",
  version = "0.1.0",
  theme = NULL,
  ...
)
```

## Arguments

- ui:

  UI definition (htmltools tags). Can be a simple
  [`htmltools::tagList()`](https://rstudio.github.io/htmltools/reference/tagList.html)
  of shinymcp components, or a full
  [`bslib::page()`](https://rstudio.github.io/bslib/reference/page.html)
  with theme.

- tools:

  List of tools

- name:

  App name

- version:

  App version

- theme:

  Optional
  [`bslib::bs_theme()`](https://rstudio.github.io/bslib/reference/bs_theme.html)
  object. Supports `brand` for
  [brand.yml](https://posit-dev.github.io/brand-yml/) theming. Not
  needed if `ui` is already a
  [`bslib::page()`](https://rstudio.github.io/bslib/reference/page.html).

- ...:

  Additional arguments passed to `McpApp$new()`

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object
