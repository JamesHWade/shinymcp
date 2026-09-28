# The chat client around a Shiny app served with shinymcp

`mcp_host_context()` reports what the chat client showing the app has
told it: the color theme, whether the app is inline or full screen, and
the user's locale and time zone. Reading it inside a reactive
expression, observer, or render function makes that code run again when
it changes, so a plot can switch to dark colors when the user switches
the chat to dark mode.

The values arrive with the app's first request from the page, so the
first render, for the model's call that opened the app, sees an empty
list.

## Usage

``` r
mcp_host_context(session = shiny::getDefaultReactiveDomain())
```

## Arguments

- session:

  The Shiny session. The default works inside a server function and in
  modules.

## Value

A named list with any of `theme` (`"light"` or `"dark"`), `display_mode`
(`"inline"`, `"fullscreen"`, or `"pip"`), `locale`, `time_zone`, and
`platform`. An empty list before the page has reported them, and `NULL`
outside shinymcp's runtime.

## Shiny's own MCP support

Shiny is gaining MCP support of its own
(<https://github.com/rstudio/shiny/pull/4407>). Once it is released, it
will be the way to put a live Shiny app in a chat, and shinymcp will
stop serving live apps.
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md),
and
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)
will take only apps built from tools, and
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
and the helpers for server functions
([`mcp_model_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md),
`mcp_host_context()`, and the rest) will be removed. For something the
model should be able to use on its own, rewrite that part of the app as
tools with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md);
see
[`vignette("rewriting-as-tools")`](https://jameshwade.github.io/shinymcp/articles/rewriting-as-tools.md).

## See also

Other server function helpers:
[`mcp_model_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md)

## Examples

``` r
server <- function(input, output, session) {
  output$plot <- shiny::renderPlot({
    dark <- identical(mcp_host_context()$theme, "dark")
    par(bg = if (dark) "#1f1f1e" else "white", fg = if (dark) "grey90" else "black")
    plot(mtcars$wt, mtcars$mpg, col.axis = par("fg"), col.lab = par("fg"))
  })
}
```
