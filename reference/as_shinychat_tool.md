# Use an MCP App's tools in a shinychat conversation

`as_shinychat_tool()` turns the tools of an app, or of a remote MCP
server, into
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
objects for a chat built with shinychat. When the model calls one that
shows an app, shinychat shows the app, live, in the tool's card. The
model gets the tool's structured result (or the text, if there is none);
the person gets the app.

[`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md)
does this for you and also passes what the person does in the cards on
to the model. Use `as_shinychat_tool()` on its own for cards without
that.

For a remote server, call `as_shinychat_tool()` where the app starts,
outside the server function, and register the tools in each session:
listing a server's tools waits for it. In a Shiny session it uses only
the list the client already has, and is an error without one.

`mcp_content_result()` builds a card by hand, for a result you append to
the chat yourself.

## Usage

``` r
as_shinychat_tool(
  source,
  tool = NULL,
  value_fn = NULL,
  summary = NULL,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE
)

mcp_content_result(
  source,
  value,
  tool = NULL,
  arguments = NULL,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE,
  text = NULL
)
```

## Arguments

- source:

  Where the tools come from: an
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  (or a list of them), or an
  [McpClient](https://jameshwade.github.io/shinymcp/reference/McpClient.md)
  from
  [`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md).

- tool:

  Names of the tools to wrap. Defaults to every tool the model may call.
  For `mcp_content_result()`, the tool that opens the app: by default
  the first the model may call that shows one. Name it for a remote
  server.

- value_fn:

  Optional function computing the value returned to the model. It can
  take any of `result` (the MCP result), `arguments` (the model's, as
  parsed JSON: arrays are lists), and, for apps in this process,
  `raw_result` (what the tool function returned).

- summary:

  Optional text shown in the card when it can't show the app, or a
  function taking the same arguments as `value_fn`.

- title, icon:

  Card title and icon (a string or tag, or a function taking the same
  arguments as `value_fn`). Default to the tool's title.

- open:

  Whether the card starts expanded.

- show_request:

  Whether the card shows the call's arguments.

- full_screen:

  Whether the card offers a full-screen view.

- value:

  For `mcp_content_result()`, the value for the model.

- arguments:

  For `mcp_content_result()`, arguments for the tool that opens the app,
  called when the card is shown, as a client would send them. A vector
  of one value is one value; write an array of one as `list(x)`.

- text:

  Plain-text fallback shown where the app can't render.

## Value

For one tool, an
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html);
for several, a named list of them. `mcp_content_result()` returns an
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html).
In a Shiny session it calls the tool first and returns a promise of the
card, which
[`shinychat::chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html)
waits for; the card is saved with the app's opening result, so a
restored conversation shows the app without calling the tool again.

## See also

Other hosting:
[`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md),
[`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md),
[`mcp_host_ui()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)

## Examples

``` r
if (FALSE) { # \dontrun{
chat <- ellmer::chat("anthropic/claude-sonnet-5")
chat$register_tool(as_shinychat_tool(app, title = "Penguins"))
} # }
```
