# Mark an element as an output of an app's tools

A tool fills the outputs whose ids match the names of the list it
returns.
[`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md),
[`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)
and the other output functions make those elements; `mcp_output()` turns
any element into one.

## Usage

``` r
mcp_output(
  tag,
  id = NULL,
  type = c("text", "html", "plot", "table", "image", "widget")
)
```

## Arguments

- tag:

  A tag.

- id:

  The output id. Defaults to the element's own id.

- type:

  How to show the value: `"text"`, `"html"`, `"plot"`, `"table"`,
  `"image"`, or `"widget"`.

## Value

`tag`, marked.

## See also

Other components:
[`mcp_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_input.md),
[`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md),
[`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md),
[`mcp_submit_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_submit_button.md)

## Examples

``` r
mcp_output(htmltools::div(class = "summary-card"), id = "summary", type = "html")
#> <div class="summary-card" data-shinymcp-output="summary" data-shinymcp-output-type="html"></div>
```
