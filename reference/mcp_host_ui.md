# Host an MCP App in a Shiny app

`mcp_host_ui()` and `mcp_host_server()` show an MCP App in a pane of a
Shiny app, as a chat client would: the app's page runs in a sandboxed
frame, and its tool calls go through R to the app's server. Use it to
reuse an app built for chat clients as part of a dashboard, to react in
Shiny to what someone does in it, or to see what an app tells the model
before you give it to one.

The app can come from anywhere: an
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md) in
the same R process, or any MCP server through
[`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md),
including Shiny apps served with Shiny's own MCP support.

`mcp_embed()` does both halves at once, for UI created on the server,
such as inside
[`shiny::renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html).

When the pane opens, R calls the app's tool with `arguments`, as a model
would, and passes the result to the app.

## Usage

``` r
mcp_host_ui(id, height = "auto")

mcp_host_server(
  id,
  source,
  tool = NULL,
  arguments = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto"
)

mcp_embed(
  source,
  id = NULL,
  tool = NULL,
  arguments = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto"
)
```

## Arguments

- id:

  Module id.

- height:

  `"auto"` to follow the app's size, or a CSS height.

- source:

  Where the app comes from: an
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  (or a list of them), or an
  [McpClient](https://jameshwade.github.io/shinymcp/reference/McpClient.md)
  from
  [`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md).

- tool:

  The tool that opens the app. Defaults to the first tool the model may
  call that shows an app. A remote server's tools are listed without
  holding up the session, so a tool it doesn't have is reported in the
  pane rather than as an error.

- arguments:

  Named list of arguments for that call, as a client would send them. A
  vector of one value is one value; write an array of one as `list(x)`.

- trigger, debounce_ms:

  For apps made with shinymcp in this process: override the app's own
  `trigger` and `debounce_ms`. `trigger = "manual"` shows a Run button
  and calls tools only when it's pressed or when `execute()` is called.

## Value

`mcp_host_ui()` and `mcp_embed()` return UI. `mcp_host_server()` returns
a list of reactives and functions:

- `model_context()`: the latest context the app published for the model.

- `last_tool_call()`: the latest tool call, a list with `name`,
  `arguments`, and `result` (the MCP result).

- `last_result()`: the MCP result of the latest tool call.

- `messages()`: messages the app asked to post to the chat.

- `open(arguments = NULL, tool = NULL)`: open the app again, calling the
  tool with new arguments.

- `execute(inputs = NULL)`: for apps made with shinymcp, call the app's
  tools now, optionally setting inputs first.

- `dispose()`: shut the app down.

## See also

Other hosting:
[`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md),
[`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md),
[`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md)

## Examples

``` r
if (FALSE) { # \dontrun{
library(shiny)
ui <- bslib::page_fillable(mcp_host_ui("explorer"))
server <- function(input, output, session) {
  host <- mcp_host_server("explorer", app, arguments = list(species = "Gentoo"))
  observe(print(host$model_context()))
}
shinyApp(ui, server)

# An app on a remote server
server <- function(input, output, session) {
  sales <- mcp_client("https://connect.example.com/sales/mcp")
  mcp_host_server("explorer", sales, arguments = list(region = "West"))
}
} # }
```
