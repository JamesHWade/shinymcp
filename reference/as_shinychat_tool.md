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
  full_screen = TRUE,
  on_app_call = NULL
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
  text = NULL,
  on_app_call = NULL
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

- on_app_call:

  A function that checks each tool call the app's page makes in the card
  before it's sent, to let it through, refuse it, or record it. See
  "Checking the app's calls" below. If the card belongs to an
  [`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md),
  that chat host's function checks the call too. `NULL`, the default,
  lets through every call the app may make.

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

## Checking the app's calls

The app's page calls its tools as the person uses it: to fill its
outputs when an input changes, or when they press a button such as
"Save". `on_app_call` sees each of these calls before it's sent to the
app's server, to let it through, refuse it, or keep a record of who did
what. It's called with a list describing the call:

- `name`: the tool's name.

- `arguments`: its arguments, as the page sent them (parsed JSON: arrays
  are lists).

- `tool`: the tool's definition from the app's server, with its
  `annotations`, such as `destructiveHint`.

- `instance_id`: the id of the pane or card.

- `kind`: `"pane"` or `"card"`.

- `source`: the name of where the app comes from: the
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)'s
  name, or the
  [`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md)'s
  `name`.

- `chat`: for a card, the
  [`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md)
  it belongs to: its `chat_id`, else `"chat-1"`, `"chat-2"`, and so on,
  by its place among the session's chat hosts. Otherwise `NULL`.

- `title`: the app's title.

- `session`: the Shiny session. On Posit Connect, `session$user` is the
  signed-in user.

Return `TRUE` to let the call through, and `FALSE` or a string to refuse
it. The app's page is given the string as the call's error, so write it
for the person using the app. To ask someone first, return a promise
that resolves to one of these: the app waits for the answer, and the
rest of the session carries on. Anything else, an error, or a rejected
promise refuses the call, with a warning. A refused call never reaches
the app's server.

A page can call a tool each time an input changes, so keep the function
quick, and ask a person only about the tools that need it.

Only the tool calls the app's page makes are checked. Reading the app's
resources isn't, and neither is the call that opens the app. The model's
calls are the chat's to check, with ellmer's `on_tool_request()`
callback (see
[`ellmer::tool_reject()`](https://ellmer.tidyverse.org/reference/tool_reject.html)).

A function can't be saved with a conversation. A card restored in a new
session goes through the checks that session gives for the card's app,
through
[`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md)
or `as_shinychat_tool()`. If the card had a check of its own and the new
session gives none, its page's calls are refused. That mark is saved in
the browser with the conversation, so it guards against a missing check,
not against the person who edits their saved conversation: to check
every call, give the check to
[`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md)
or `as_shinychat_tool()`.

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
