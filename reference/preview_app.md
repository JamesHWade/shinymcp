# Preview an MCP App in a browser

`preview_app()` serves the app over MCP on a local port and opens a page
that hosts it the way a chat client does: the app runs in a sandboxed
iframe under the same Content Security Policy a client would apply, and
every message goes through the app's real MCP endpoint. Alongside the
app the page shows what the model would see (the text and structured
content of each tool result), the context the app publishes for the
model, and a log of the protocol messages.

When the page opens it calls the app's first tool (or `tool`) with
`arguments`, as a model would, and shows the app with the result. Use
the arguments box on the page to call it again with other values.

## Usage

``` r
preview_app(
  app,
  arguments = NULL,
  tool = NULL,
  port = NULL,
  launch = interactive()
)
```

## Arguments

- app:

  An
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md), a
  list of apps, a Shiny app, or a path to one.

- arguments:

  Named list of arguments for the first call, as a client would send
  them. A vector of one value is one value; write an array of one as
  `list(x)`.

- tool:

  Name of the tool to call first. Defaults to the first tool the model
  can call.

- port:

  Port to listen on. `NULL` picks a free one.

- launch:

  Whether to open the page in a browser.

## Value

Invisibly, a list with the preview's `url` and a
[`stop()`](https://rdrr.io/r/base/stop.html) function.

## See also

Other serving:
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md),
[`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md),
[`shinymcp-options`](https://jameshwade.github.io/shinymcp/reference/shinymcp-options.md)

## Examples

``` r
if (FALSE) { # \dontrun{
preview <- preview_app(app, arguments = list(species = "Gentoo"))
preview$stop()
} # }
```
