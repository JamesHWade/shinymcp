# Typed output values for tool results

A tool that feeds an app returns a named list: one element per output,
named by the output's id. Plain values work (a string for
[`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md),
a data frame for
[`mcp_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)),
but the typed constructors say more:

- `mcp_result_text()`: text, rendered in a `<pre>` by
  [`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md).

- `mcp_result_html()`: HTML or an htmltools tag.

- `mcp_result_table()`: a data frame, rendered as an HTML table.

- `mcp_result_plot()`: a plot, rendered to PNG.

- `mcp_result_image()`: an image file or raw PNG/JPEG data.

- `mcp_result_pdf()`: a PDF the user can download from the app.

- `mcp_result_widget()`: an htmlwidget or other tag with JavaScript
  dependencies, such as a plotly chart.

Each takes a `model_value`, the value the model sees for this output in
the tool result's structured content, and a `text`, the plain-text
version used when the model or host can only read text. By default the
model gets a table's rows and a plot's description; set them when it
needs something more specific: identifiers, a decision, the numbers
behind a chart.

## Usage

``` r
mcp_result_text(value, model_value = NULL, text = NULL)

mcp_result_html(html, model_value = NULL, text = NULL)

mcp_result_table(data, model_value = NULL, text = NULL)

mcp_result_plot(
  plot,
  model_value = NULL,
  text = NULL,
  width = NULL,
  height = NULL,
  res = 96,
  scale = NULL
)

mcp_result_image(path_or_data, model_value = NULL, text = NULL)

mcp_result_pdf(path_or_data, model_value = NULL, text = NULL, filename = NULL)

mcp_result_widget(ui, model_value = NULL, text = NULL)
```

## Arguments

- value, html, data, plot, path_or_data, ui:

  The content to render.

- model_value:

  What the model sees for this output. Defaults to the text for text and
  HTML outputs, the rows for tables, and `text` for plots, images, PDFs,
  and widgets.

- text:

  Plain-text version of the output.

- width, height:

  Plot size in CSS pixels. By default, the size of the output the plot
  goes to, which the app's page reports when it calls the tool, and 800
  by 500 for calls it didn't make (such as the model's). The page draws
  a plot of the wrong size to fit, then calls the tool again for one of
  the right size.

- res:

  Plot resolution in pixels per inch at 1x.

- scale:

  Pixel density multiplier; `2` gives sharp plots on high density
  screens at four times the file size. By default, the screen's, as the
  page reports it, else the `shinymcp.plot_scale` option (1.5).

- filename:

  File name offered when the user downloads a PDF.

## Value

A typed output value, to be returned from a tool inside a named list or
on its own.

## See also

Other writing tools:
[`mcp_request()`](https://jameshwade.github.io/shinymcp/reference/mcp_request.md),
[`mcp_tool_result()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_result.md)

## Examples

``` r
summarise_cars <- function(cyl = 4) {
  cars <- mtcars[mtcars$cyl == cyl, ]
  list(
    summary = mcp_result_text(
      paste(nrow(cars), "cars with", cyl, "cylinders"),
      model_value = list(cyl = cyl, n = nrow(cars))
    ),
    cars = mcp_result_table(head(cars)),
    scatter = mcp_result_plot(
      function() plot(cars$wt, cars$mpg),
      text = "Weight against fuel economy"
    )
  )
}
```
