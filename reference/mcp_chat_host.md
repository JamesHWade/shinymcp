# Host MCP Apps in a shinychat conversation

`mcp_chat_host()` gives the model in a shinychat conversation the tools
of one or more MCP Apps, and shows each app it opens in the
conversation, live. The apps can be
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)s in
the same R process, or come from any MCP server through
[`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md).

It also does what an app expects of the chat that hosts it:

- **What the person does in an app reaches the model.** Before each
  message the person sends, the model is told what each open app reports
  about what it shows (its model context). The model sees the apps'
  current state, not earlier ones, and the saved conversation doesn't
  keep it.

- **Apps can suggest messages.** A message an app asks to post goes into
  the chat's input box, for the person to read and send.

- **Saved conversations come back live.** Cards restored with a
  conversation show their apps again, without calling the tools again.

What apps report is written by the apps, so treat it like anything else
a tool returns: the model is told where it came from, and each app's
report is cut to 2,000 characters, from the five apps that changed most
recently.

A session can have several chats, each with its own `mcp_chat_host()`.
Each chat's model is told about, and gets messages from, only the cards
its tools opened. A card built with
[`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
belongs to the session's chat when there's only one.

`on_app_call` checks the tool calls that apps' pages make in the chat's
cards, such as when the person presses a button in one; the model's own
calls aren't passed to it. It applies to the cards the chat's tools
open, cards restored with the conversation, and cards built with
[`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
while it's the session's only chat.

## Usage

``` r
mcp_chat_host(
  chat,
  sources,
  context = TRUE,
  messages = c("compose", "submit", "ignore"),
  chat_id = NULL,
  ...,
  on_app_call = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- chat:

  The value of
  [`shinychat::chat_server()`](https://posit-dev.github.io/shinychat/r/reference/chat_app.html),
  or an ellmer chat. With an ellmer chat, pass `chat_id` too, so apps'
  messages can reach the input box.

- sources:

  Where the apps come from: an
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md),
  an
  [McpClient](https://jameshwade.github.io/shinymcp/reference/McpClient.md),
  or a list of them.

- context:

  Whether to tell the model what the open apps show. The report goes to
  the model as a message of its own, just before the person's, and some
  providers (AWS Bedrock) refuse two user messages in a row. For those,
  set `context = FALSE` and add `host$context()` to the person's message
  yourself.

- messages:

  What to do with messages apps ask to post: `"compose"` puts them in
  the input box, `"submit"` sends them at once (for apps you trust),
  `"ignore"` drops them.

- chat_id:

  With an ellmer chat, the id of the
  [`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html).

- ...:

  Passed to
  [`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md):
  `value_fn`, `summary`, `title`, `icon`, `open`, `show_request`, and
  `full_screen`.

- on_app_call:

  A function that checks each tool call the pages of the chat's cards
  make before it's sent, to let it through, refuse it, or record it. See
  "Checking the app's calls" below. `NULL`, the default, lets through
  every call the apps may make.

- session:

  The Shiny session.

## Value

Invisibly, a list with `context()`, which returns the text the model is
given about the open apps (or `NULL`), and `tools`, the ellmer tools
registered with the chat.

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

- `chat`: for a card, the `mcp_chat_host()` it belongs to: its
  `chat_id`, else `"chat-1"`, `"chat-2"`, and so on, by its place among
  the session's chat hosts. Otherwise `NULL`.

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
through `mcp_chat_host()` or
[`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md).
If the card had a check of its own and the new session gives none, its
page's calls are refused. That mark is saved in the browser with the
conversation, so it guards against a missing check, not against the
person who edits their saved conversation: to check every call, give the
check to `mcp_chat_host()` or
[`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md).

## See also

Other hosting:
[`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md),
[`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md),
[`mcp_host_ui()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)

## Examples

``` r
if (FALSE) { # \dontrun{
library(shiny)
library(shinychat)

ui <- bslib::page_fillable(chat_ui("chat"))
server <- function(input, output, session) {
  chat <- chat_server("chat", ellmer::chat("anthropic/claude-sonnet-5"))
  mcp_chat_host(chat, list(
    cars_app,
    mcp_client("https://connect.example.com/sales/mcp")
  ))
}
shinyApp(ui, server)
} # }
```
