# An apply button for apps that wait for it

In an app made with `mcp_app(trigger = "submit")`, input changes wait
until the user presses an apply button. Without one in the UI, the page
adds its own at the bottom; use `mcp_submit_button()` to choose where it
goes and what it says. The button is disabled until something changes.

## Usage

``` r
mcp_submit_button(label = "Apply", class = "btn btn-primary")
```

## Arguments

- label:

  Button text.

- class:

  CSS classes for the button.

## Value

An htmltools `<button>` tag.

## See also

Other components:
[`mcp_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_input.md),
[`mcp_output()`](https://jameshwade.github.io/shinymcp/reference/mcp_output.md),
[`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md),
[`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)

## Examples

``` r
mcp_submit_button("Run analysis")
#> <button type="button" class="btn btn-primary" data-shinymcp-submit="">Run analysis</button>
```
