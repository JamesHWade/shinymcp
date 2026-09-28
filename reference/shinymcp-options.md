# Options

These options change the limits shinymcp works within. Set them with
[`options()`](https://rdrr.io/r/base/options.html) before the app is
served.

- `shinymcp.max_views`: the most views of a live Shiny app that one R
  process keeps open (default 50). Opening another closes the one used
  least recently.

- `shinymcp.view_timeout`: seconds a view's session stays open without
  use (default 3600).

- `shinymcp.max_text_chars`: the most characters of each output's text
  in what the model reads (default 4000).

- `shinymcp.max_model_rows`: the most rows of a table the model gets
  (default 100).

- `shinymcp.max_display_rows`: the most rows of a table a tool's result
  shows on the page (default 1000).

- `shinymcp.plot_scale`: pixel density of plots in tools' results when
  the page hasn't said what the screen's is (default 1.5); see
  [`mcp_result_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md).

- `shinymcp.max_inline_dependency_bytes`: in results for the model, a
  JavaScript or CSS library larger than this (default 256 KB) goes by
  name, and the page fetches it separately. Clients keep results in the
  conversation, so large libraries in them would fill it up.

- `shinymcp.max_download_bytes`: the largest file a live app's download
  button delivers (default 25 MB).

Uploads to a live Shiny app are limited by Shiny's own
`shiny.maxRequestSize` option (default 5 MB).

## See also

Other serving:
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md),
[`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md),
[`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md)
