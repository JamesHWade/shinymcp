# Mark an element as an input of an app's tools

In an app built with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md),
a tool's argument takes its value from the input whose id matches the
argument's name. Shiny's and bslib's inputs are found that way on their
own. `mcp_input()` marks anything else: an element whose id differs from
the argument name, or a form element shinymcp doesn't recognize.

## Usage

``` r
mcp_input(tag, id = NULL)
```

## Arguments

- tag:

  A tag or tag list. The mark goes on the tag if it is a form element or
  an input group (radio buttons, a date input), otherwise on the first
  one inside it.

- id:

  The tool argument the element feeds. Defaults to the element's own id.

## Value

`tag`, marked.

## See also

Other components:
[`mcp_output()`](https://jameshwade.github.io/shinymcp/reference/mcp_output.md),
[`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md),
[`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md),
[`mcp_submit_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_submit_button.md)

## Examples

``` r
mcp_input(htmltools::tags$input(id = "q", type = "search"), id = "query")
#> <input id="q" type="search" data-shinymcp-input="query"/>
```
