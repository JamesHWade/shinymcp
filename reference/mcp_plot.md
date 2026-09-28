# Output placeholders for tool results

These make the elements a tool's results are drawn into, for apps built
with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md).
Each is matched to a tool result by `id`: a tool that returns
`list(summary = ..., plot = ...)` fills `mcp_text("summary")` and
`mcp_plot("plot")`.

- `mcp_text()` shows text in a monospaced block, as R prints it.

- `mcp_plot()` shows an image, usually from
  [`mcp_result_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md).

- `mcp_table()` shows a data frame as an HTML table.

- `mcp_html()` shows HTML: tags,
  [`mcp_result_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md),
  or an htmlwidget.

Shiny's own output functions
([`shiny::textOutput()`](https://rdrr.io/pkg/shiny/man/textOutput.html),
[`shiny::plotOutput()`](https://rdrr.io/pkg/shiny/man/plotOutput.html),
and the rest) work too; their ids are matched the same way.

## Usage

``` r
mcp_plot(id, width = "100%", height = NULL)

mcp_text(id)

mcp_table(id)

mcp_html(id)
```

## Arguments

- id:

  Output id, matching a name in the tool's result.

- width, height:

  CSS size of the plot area; numbers are pixels. A plot from
  [`mcp_result_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
  without a size of its own is drawn to fill it: at this size, or with
  `height = NULL`, at its width and in the plot's own shape (800 by 500
  unless it says otherwise).

## Value

An htmltools tag.

## See also

Other components:
[`mcp_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_input.md),
[`mcp_output()`](https://jameshwade.github.io/shinymcp/reference/mcp_output.md),
[`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md),
[`mcp_submit_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_submit_button.md)

## Examples

``` r
htmltools::tagList(
  mcp_text("summary"),
  mcp_plot("histogram"),
  mcp_table("rows")
)
#> <pre id="summary" class="shinymcp-output shinymcp-text" data-shinymcp-output="summary" data-shinymcp-output-type="text"></pre>
#> <div id="histogram" class="shinymcp-output shinymcp-plot" data-shinymcp-output="histogram" data-shinymcp-output-type="plot" style="width:100%;"></div>
#> <div id="rows" class="shinymcp-output" data-shinymcp-output="rows" data-shinymcp-output-type="table"></div>
```
