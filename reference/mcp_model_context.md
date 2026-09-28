# Talk to the model from a Shiny app served with shinymcp

In a Shiny app served as an MCP App with
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
the server function runs in shinymcp's live runtime. These helpers let
it reach the model and the chat. In a normal Shiny session they do
nothing and return `FALSE`, so the same app still runs with
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

- `mcp_model_context()` sets what the model knows about this view of the
  app. Hosts give it to the model on its next turn. Each call replaces
  the last. Without it, shinymcp sends the input values and a short
  summary of each output. Keep it small and factual: identifiers and the
  numbers the user is looking at, not whole data sets.

- `mcp_send_message()` posts a message into the chat as the user, which
  usually prompts a reply from the model. Hosts may ask the user first.

- `is_mcp_session()` is `TRUE` when the server function is running in
  shinymcp's runtime.

## Usage

``` r
mcp_model_context(
  text = NULL,
  data = NULL,
  session = shiny::getDefaultReactiveDomain()
)

mcp_send_message(text, session = shiny::getDefaultReactiveDomain())

is_mcp_session(session = shiny::getDefaultReactiveDomain())
```

## Arguments

- text:

  Text for the model (or the chat message).

- data:

  A named list of structured data for the model.

- session:

  The Shiny session. The default works inside a server function and in
  modules.

## Value

`mcp_model_context()` and `mcp_send_message()` invisibly return `TRUE`
when the message will be delivered, `FALSE` otherwise.
`is_mcp_session()` returns a logical.

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
and the helpers for server functions (`mcp_model_context()`,
[`mcp_host_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_context.md),
and the rest) will be removed. For something the model should be able to
use on its own, rewrite that part of the app as tools with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md);
see
[`vignette("rewriting-as-tools")`](https://jameshwade.github.io/shinymcp/articles/rewriting-as-tools.md).

## See also

Other server function helpers:
[`mcp_host_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_context.md)

## Examples

``` r
server <- function(input, output, session) {
  filtered <- shiny::reactive(mtcars[mtcars$cyl == input$cyl, ])

  shiny::observe({
    mcp_model_context(
      text = paste("Showing", nrow(filtered()), "cars with", input$cyl, "cylinders."),
      data = list(cyl = input$cyl, n = nrow(filtered()))
    )
  })
}
```
