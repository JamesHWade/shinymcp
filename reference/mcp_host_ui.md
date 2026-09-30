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
  height = "auto",
  on_app_call = NULL
)

mcp_embed(
  source,
  id = NULL,
  tool = NULL,
  arguments = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto",
  on_app_call = NULL
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

- on_app_call:

  A function that checks each tool call the app's page makes before it's
  sent, to let it through, refuse it, or record it. See "Checking the
  app's calls" below. `NULL`, the default, lets through every call the
  app may make.

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
or
[`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md).
If the card had a check of its own and the new session gives none, its
page's calls are refused. That mark is saved in the browser with the
conversation, so it guards against a missing check, not against the
person who edits their saved conversation: to check every call, give the
check to
[`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md)
or
[`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md).

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

# Record each call the app's page makes, and refuse one tool
server <- function(input, output, session) {
  mcp_host_server("explorer", app, on_app_call = function(call) {
    message(call$session$user, " called ", call$name)
    if (call$name == "delete_notes") "Notes can't be deleted here." else TRUE
  })
}
} # }
```
