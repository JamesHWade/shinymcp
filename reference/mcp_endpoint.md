# Add an MCP endpoint to a Shiny app

`mcp_endpoint()` returns a Shiny app that answers MCP requests at `path`
(default `/mcp`), so an MCP App can be deployed anywhere Shiny apps run:
Posit Connect, Shiny Server, or
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) on your
own machine. Deploy it like any Shiny app, then point MCP clients at
`https://<server>/<app-path>/mcp`.

- Given an
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  (or a list of them), browsers visiting the app get the same preview
  page as
  [`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md).

- Given a Shiny app and `apps`, browsers get the Shiny app and MCP
  clients get the apps. One deployment serves people and models; the
  apps can share the Shiny app's UI and functions.

- Given a Shiny app alone, browsers still get the Shiny app, and the
  endpoint serves it, live, to MCP clients through
  [`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md).

Clients that speak the stateless MCP revision (2026-07-28) can reach any
of several R processes behind a load balancer. Live Shiny apps keep each
view's session in the process that opened it; see
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md)
for what happens when a request lands elsewhere.

On Posit Connect the endpoint sits behind the content's access controls,
and
[`mcp_request()`](https://jameshwade.github.io/shinymcp/reference/mcp_request.md)
reports the signed-in user.

## Usage

``` r
mcp_endpoint(
  x,
  apps = NULL,
  path = "/mcp",
  allowed_origins = NULL,
  allowed_hosts = NULL,
  preview = TRUE,
  ...
)
```

## Arguments

- x:

  An
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md), a
  list of apps, or a Shiny app.

- apps:

  When `x` is a Shiny app, the apps to serve to MCP clients next to it:
  an [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  or a list of them. Without `apps`, the Shiny app itself is served,
  live.

- path:

  Endpoint path.

- allowed_origins:

  Browser origins, besides the app's own, allowed to call the endpoint.
  See
  [`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md).

- allowed_hosts:

  Host names the app is reached at, when it runs somewhere other than
  Posit Connect, shinyapps.io, or Shiny Server (for example in a
  container behind your own proxy). Elsewhere, requests for host names
  other than `localhost` or an IP address are refused; see
  [`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md).

- preview:

  For apps, whether browsers get a preview page at `/`.

- ...:

  Passed to
  [`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md)
  when `x` is a Shiny app served live.

## Value

A Shiny app object.

## Shiny's own MCP support

Shiny is gaining MCP support of its own
(<https://github.com/rstudio/shiny/pull/4407>). Once it is released, it
will be the way to put a live Shiny app in a chat, and shinymcp will
stop serving live apps.
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
`mcp_endpoint()`, and
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)
will take only apps built from tools, and
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
and the helpers for server functions
([`mcp_model_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md),
[`mcp_host_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_context.md),
and the rest) will be removed. For something the model should be able to
use on its own, rewrite that part of the app as tools with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md);
see
[`vignette("rewriting-as-tools")`](https://jameshwade.github.io/shinymcp/articles/rewriting-as-tools.md).

## See also

Other serving:
[`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md),
[`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md),
[`shinymcp-options`](https://jameshwade.github.io/shinymcp/reference/shinymcp-options.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# app.R, deployed to Posit Connect with rsconnect::deployApp()
library(shinymcp)

app <- mcp_app(ui, tools = list(summarize_dataset), name = "datasets")
mcp_endpoint(app)

# A Shiny app for people, and an app built from tools for chat clients
library(shiny)
shinyApp(ui, server) |> mcp_endpoint(apps = app)

# A Shiny app, served live to chat clients and as usual to browsers
shinyApp(ui, server) |> mcp_endpoint(name = "explorer")
} # }
```
