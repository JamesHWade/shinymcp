# Inputs for apps built from tools

Small form controls for
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
UIs, drawn by the page itself. Shiny's and bslib's inputs work just as
well in an MCP App; these need neither package and keep the page light.

- `mcp_select()`: a drop-down list.

- `mcp_text_input()`: a line of text.

- `mcp_numeric_input()`: a number.

- `mcp_checkbox()`: `TRUE` or `FALSE`.

- `mcp_slider()`: a number on a range.

- `mcp_radio()`: one of a few choices.

- `mcp_action_button()`: a button; a tool taking its id runs when it's
  pressed.

## Usage

``` r
mcp_select(id, label, choices, selected = choices[[1]])

mcp_text_input(id, label, value = "", placeholder = NULL)

mcp_numeric_input(id, label, value, min = NA, max = NA, step = NA)

mcp_checkbox(id, label, value = FALSE)

mcp_slider(id, label, min, max, value = min, step = 1)

mcp_radio(id, label, choices, selected = choices[[1]])

mcp_action_button(id, label)
```

## Arguments

- id:

  The input id, which is the name of the tool argument it feeds.

- label:

  The label shown with the input.

- choices:

  The values to choose from. Names, if any, are shown in their place.

- selected:

  The value selected at first. Defaults to the first choice.

- value:

  The value at first.

- placeholder:

  Text shown while the input is empty.

- min, max:

  The smallest and largest values allowed.

- step:

  The step between values.

## Value

A tag.

## See also

Other components:
[`mcp_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_input.md),
[`mcp_output()`](https://jameshwade.github.io/shinymcp/reference/mcp_output.md),
[`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md),
[`mcp_submit_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_submit_button.md)

## Examples

``` r
htmltools::tagList(
  mcp_select("species", "Species", c("Adelie", "Gentoo", "Chinstrap")),
  mcp_slider("alpha", "Opacity", min = 0, max = 1, value = 0.7, step = 0.1),
  mcp_checkbox("smooth", "Add a trend line")
)
#> <div class="shinymcp-input-group">
#>   <label for="species">Species</label>
#>   <select id="species" data-shinymcp-input="species" data-shinymcp-type="select">
#>     <option value="Adelie" selected>Adelie</option>
#>     <option value="Gentoo">Gentoo</option>
#>     <option value="Chinstrap">Chinstrap</option>
#>   </select>
#> </div>
#> <div class="shinymcp-input-group">
#>   <label for="alpha">Opacity</label>
#>   <input type="range" id="alpha" data-shinymcp-input="alpha" data-shinymcp-type="slider" min="0" max="1" value="0.7" step="0.1"/>
#> </div>
#> <div class="shinymcp-input-group">
#>   <label>
#>     <input type="checkbox" id="smooth" data-shinymcp-input="smooth" data-shinymcp-type="checkbox"/>
#>     Add a trend line
#>   </label>
#> </div>
```
