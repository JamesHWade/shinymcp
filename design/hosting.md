# Hosting MCP Apps in Shiny

2026-09-28. The plan for how a Shiny app shows MCP Apps: in a pane, or as
cards in a shinychat conversation where a model calls the tools. It replaces
hosts that only showed apps made with shinymcp in the same R process.

## The story

Shiny's own MCP support will serve Shiny apps to chat clients. shinymcp
builds apps from tools, and it hosts MCP Apps in Shiny: any app, from any
MCP server, in any Shiny app. Hosting doesn't depend on who made the app. A
shinymcp app in the same process, one deployed on Posit Connect, a Shiny
app served by Shiny's MCP support, and an app written in TypeScript are
shown the same way.

Three uses, in order of how much of the host they need:

1. **A chat app.** A shinychat conversation with ellmer. The model calls an
   app's tool and the person sees the app in the conversation. What the
   person then does in the app reaches the model with their next message,
   and the app can suggest a message for them to send.
2. **A dashboard.** An app in a pane of a Shiny app, with no model. The
   Shiny app opens it with arguments and reacts to what happens in it. An
   app built for Claude can be reused as a component.
3. **Reviewing an app.** Seeing exactly what a model would be told, before
   giving the app to one. `preview_app()` does this for development; a pane
   does it inside an app.

## Who does what

- **R** holds the connection to every MCP server, and any credentials.
  Every tool call and resource read goes through R: those the model makes
  (through ellmer), those the Shiny app makes, and those the app's page
  makes.
- **The host script** in the Shiny page draws the frame, speaks the MCP
  Apps protocol to the page, and passes the page's requests to R over the
  Shiny session.
- **The app's page** runs in a sandboxed iframe with an opaque origin, under
  the Content Security Policy the app declares. It is untrusted: it reaches
  nothing but the host script, and the host script lets it do only what the
  protocol allows.

This is how a desktop chat client works, with R in the place of the
client's MCP connection. Keeping the connection in R has three
consequences: credentials never reach the browser; the browser needs no
network access to the server, so CORS and cookies don't matter; and R
enforces which tools the page may call.

## Sources

A source is where an app's tools and page come from.

- **Apps in the same process.** An `McpApp` or a list of them. Requests go
  to an in-process `McpServer`, run from `later`, outside the reactive
  flush (an app served live runs reactive sessions of its own, which can't
  flush inside another flush).
- **Remote servers.** `mcp_client(url, headers)` connects over Streamable
  HTTP. It tries the stateless 2026-07-28 protocol first (`server/discover`)
  and falls back to the `initialize` handshake (2025-11-25 and earlier),
  keeping the `Mcp-Session-Id`. It declares the MCP Apps extension, keeps
  `_meta` on every result (mcptools drops it, which is why hosts can't use
  it), and reads JSON or SSE response bodies. In a Shiny session, requests
  are asynchronous (httr2 and promises), so a slow tool or a long poll
  doesn't hold up the session or the other requests; outside one they
  block. `headers` is a list or a function returning one, called for each
  request, so each visitor's requests can carry their own credentials:
  create the client in the server function for that.

  The same client works on its own, to call a deployed server's tools from
  R with their `_meta` intact.

Not planned for now: stdio servers (a server you run locally can be served
over HTTP), and OAuth flows (bring the token in `headers`).

## Surfaces

- **A pane.** `mcp_host_ui(id)` and `mcp_host_server(id, source, tool,
  arguments)`. The Shiny app decides which tool opens the app and with what
  arguments; `open()` opens it again with others.
- **Chat cards.** `mcp_chat_host(chat, sources)` gives the model the
  sources' tools, shows a card when one opens an app, and passes context
  and messages between the cards and the conversation.
  `as_shinychat_tool()` stays as the lower-level piece: ellmer tools whose
  results are cards, with no context or messages.
- `mcp_embed()` for UI created on the server, as now.
- `preview_app()` stays a separate host whose page connects to the
  endpoint itself. It's for looking at one app during development.

## Opening an app

1. The tool is called in R: by the model, through ellmer, or by the pane
   when it starts. R knows from `tools/list` whether the tool declares a
   page (`_meta.ui.resourceUri`) and who may call it (`visibility`).
2. The card or pane carries a small descriptor: the instance id, the
   source's key, the tool, its arguments, and its result. Not the page:
   pages with their dependencies inlined run to hundreds of kilobytes, and
   a card is stored with the conversation.
3. The host script sends `attach` for the instance. R finds or recreates
   it and answers with the page, read with `resources/read` (and cached for
   the session by source and URI), and its `_meta.ui` (CSP, permissions,
   border).
4. The host loads the page and, once it has initialized, sends it
   `ui/notifications/tool-input` and `ui/notifications/tool-result`. A pane
   whose tool hasn't been called yet gets the result when R has it.

A tool that declares no page returns its result to the model as usual, with
no card.

Nothing in the session waits on a remote server. A pane or card on an
`mcp_client()` checks its tool against the server's `tools/list` without
blocking, before its call and before its attach, and a tool that isn't
there, or declares no page, is reported where the app would be; a failed
listing is tried again at the next attach. Apps in the same process are
checked when the pane registers, so a wrong name is an error at once. The
chat host is the exception: ellmer needs the model's tools when it starts,
so `mcp_chat_host()` lists a client's tools then.

## Requests from the page

R answers the page's requests only for:

- `tools/call`, for tools whose visibility includes `"app"` (the default
  visibility includes it);
- `resources/read`, `resources/list`, `resources/templates/list`;
- `ping`.

Anything else is `Method not found`. The host script checks the same list,
so a refused call never reaches R; R checks again because it holds the
source of truth. Requests are asynchronous end to end, so an app that
long-polls (Shiny's tunnel does) works.

Shiny applies each input message in its own reactive cycle
(`cycleStartAction()`), so a burst of requests over the one input the host
uses isn't coalesced.

## The model loop

**Tools.** Each source's tools the model may call become ellmer tools
(`schema_to_ellmer_types()` keeps their schemas). The model gets the
structured content, or the text when there is none, as it would from any
MCP client. Tool annotations carry over.

**Context.** An app tells the host what the model should know about it
with `ui/update-model-context`; each update replaces the one before. Before
the person's next message, the host gives the model the latest context of
each open app, as a user message placed just before theirs:

```
<app-context app="Cars by cylinders" id="cars-3">
Showing the 8-cylinder cars: 14 of them, median 15.2 mpg.
</app-context>
```

It is added from `Chat$on_request_start()`, which can change the turns
before the one being sent but not that one. So the context is its own
message, not a prefix of the person's. It is added only before a message
from the person, not before tool results (which must follow their tool
calls), and taken out of the history again when the reply is complete
(`on_request_end()` with no tool requests left). So the model always sees
each open app's current state, never an old one, and the saved
conversation holds only what the person and the model said. Prompt caching
is unaffected: the context is always after the cached prefix.

Limits: each app's context is cut to 2,000 characters, and at most the five
apps whose context changed most recently are included. The text is framed
as coming from the app, and it is untrusted: an app's page could say
anything.

Providers that require strictly alternating roles (AWS Bedrock's Converse
API) reject two user messages in a row. For those, `context = FALSE`, and
put `host$context()` in the message yourself.

**Messages.** `ui/message` asks the host to post a message as the person.
By default it goes into the chat's input box, focused, for the person to
read and send; `messages = "submit"` sends it at once, for apps you trust.
Outside a chat, `messages()` returns them.

**Calls the page makes.** Tool calls the page makes (a button in the app)
reach the model only through the app's context. That's the app's decision.

## Lifecycle

- One instance per card or pane, in a registry kept for each Shiny
  session. An instance is disposed when its element leaves the page (after
  a second's grace, since UI frameworks move nodes), when `dispose()` is
  called, or when the session ends. Disposing an instance of a live Shiny
  app closes its views.
- **Restored conversations.** shinychat saves each card's display with the
  conversation (`jsonlite::serializeJSON()` keeps the HTML dependencies).
  When a restored card attaches and R doesn't know its instance, R recreates
  it from the descriptor, provided the source's key is registered in this
  session. The stored result is replayed; the tool isn't called again,
  since calls needn't be safe to repeat. A card whose source isn't
  registered shows its text fallback and an error.
- A page that reloads inside its frame gets the tool input and result
  again.

## Security

- The frame is sandboxed without `allow-same-origin`, so the page can't
  reach the Shiny page, its cookies, or the Shiny session. Its CSP comes
  from `_meta.ui.csp`, as the specification describes; with none, the page
  has no network access.
- The descriptor comes from the browser. R trusts it only to name a
  registered source and a tool of that source; `attach` never calls a tool.
  The result it carries only reaches that card's own page.
- The page's model context and messages are untrusted input: bounded,
  framed as data, and messages go to the person before the model by
  default.
- Links open only for `http`, `https`, and `mailto`, with `noopener`.
  Downloads are saved from blobs in the host page.
- The model can call only the tools of the sources the Shiny app gave it.

## API

```r
# A pane
ui <- page_sidebar(mcp_host_ui("sales"))
server <- function(input, output, session) {
  sales <- mcp_client("https://connect.example.com/sales/mcp",
    headers = list(Authorization = paste("Key", Sys.getenv("CONNECT_API_KEY")))
  )
  pane <- mcp_host_server("sales", sales, tool = "open_sales_app",
    arguments = list(region = "West"))
  observe(print(pane$model_context()))
}

# A chat
server <- function(input, output, session) {
  client <- ellmer::chat("anthropic/claude-sonnet-5")
  chat <- shinychat::chat_server("chat", client)
  mcp_chat_host(chat, list(cars_app, mcp_client("https://.../mcp")))
}
```

`mcp_chat_host()` takes the value of `shinychat::chat_server()` (which gives
it the chat's input box) or an ellmer chat and a `chat_id`.

## Relation to Shiny's MCP support

A Shiny app served with `shiny::mcpConfigure()` is hosted through
`mcp_client()` like any other server. That is the path for people who host
live Shiny apps with `as_mcp_app()` today: serve the app with Shiny, host it
with shinymcp. The fork's example implementations (arguments set before the
first render, a result from the call that opens the app) make those apps
behave well in these hosts.

## Tests

- The client against shinymcp's own endpoint in both protocol eras,
  including a server that answers with SSE, session expiry, and errors.
- The proxy policy: refused methods and tools, visibility from a remote
  server, attach for unknown instances and sources.
- Context injection with a scripted ellmer chat: added before a message,
  not before tool results, removed after the reply, bounded.
- In a browser: a pane and a chat card for an in-process app, for a remote
  shinymcp endpoint, and for a Shiny app served by Shiny's MCP support
  (both of its transports), and a restored conversation.
