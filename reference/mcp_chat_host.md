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

## Usage

``` r
mcp_chat_host(
  chat,
  sources,
  context = TRUE,
  messages = c("compose", "submit", "ignore"),
  chat_id = NULL,
  ...,
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

- session:

  The Shiny session.

## Value

Invisibly, a list with `context()`, which returns the text the model is
given about the open apps (or `NULL`), and `tools`, the ellmer tools
registered with the chat.

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
