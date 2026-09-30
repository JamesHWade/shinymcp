# Changelog

## shinymcp (development version)

This version makes shinymcp about MCP Apps built from R functions and
Shiny UI, and rewrites the protocol layer, the page’s JavaScript, the
hosts, and the documentation. Code written for earlier versions needs
changes.

Serving an existing Shiny app live, with
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
still works, but it is transitional: Shiny is gaining MCP support of its
own (rstudio/shiny#4407), and once that is released shinymcp will stop
serving live apps. The reference pages it affects have a “Shiny’s own
MCP support” section.

### Apps built from tools

- Tool arguments from the model are checked against declared schemas; a
  missing or mistyped argument, including one value where the schema
  asks for an array, goes back to the model as a tool error. Arguments
  passed from R count as a client would send them: write an array of one
  value as `list(x)`.
- [`mcp_tool_result()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_result.md)
  sets a result’s text and structured data.
- A tool that takes a button’s id runs when the button is pressed, not
  whenever its other inputs change. The page doesn’t run tools annotated
  as changing something on its own, to fill in outputs or because an
  input they take changed: they run when a button they take is pressed.
- [`mcp_submit_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_submit_button.md)
  places the apply button for `mcp_app(trigger = "submit")`.
- `mcp_app(www = )` writes a folder of scripts, stylesheets, and images
  into the page. A relative `www` is read from the working directory the
  app is made in.
- An app built in an `app.R` and loaded from its directory
  ([`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md),
  [`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
  [`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md))
  runs its tools and builds its page in that directory, as a Shiny app’s
  code runs in its own.
- `mcp_app(theme = )` refuses a UI that is already a page, instead of
  nesting two pages.
- Plots are drawn at the size of their output. The page tells each tool
  call how big its plot outputs are and how dense the screen is, and
  calls again when an output changes size; an
  [`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)
  without a height keeps the plot’s shape.
  [`mcp_result_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)’s
  `width`, `height`, and `scale` set a size and density of their own.

### Protocol and serving

- The server speaks MCP 2024-11-05 through 2025-11-25 and the stateless
  2026-07-28 revision, and MCP Apps 2026-01-26. It was tested with the
  official MCP TypeScript client and the MCP Apps host SDK.
- New
  [`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md)
  turns apps into a Shiny app that answers MCP at `/mcp`, for Posit
  Connect, Shiny Server, and shinyapps.io. Given a Shiny app and `apps`,
  it serves the Shiny app to browsers and the apps to chat clients, from
  one deployment; given a Shiny app alone, it serves that app live to
  chat clients and as usual to browsers. On Posit Connect, tools and
  server functions see the signed-in user.
- The HTTP transport checks `Origin` and, on a local server, `Host`
  (against DNS rebinding);
  [`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md)
  gains `allowed_origins` and `allowed_hosts`.
- Results leave out libraries the page already has, and results for the
  model name large libraries instead of carrying them.
- A client that doesn’t show MCP Apps is neither told of nor allowed to
  call tools that only an app may call.

### Hosts

- New
  [`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md)
  hosts apps in a shinychat conversation. The model opens them with
  their tools; before each message the person sends, it is told what
  each open app reports about what it shows; a message an app suggests
  goes to the chat’s input box; and a restored conversation shows its
  apps again without calling their tools. Several chats in one session
  each keep to their own apps.
- New
  [`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md)
  connects to any MCP server over HTTP, in either protocol era, keeping
  the `_meta` MCP Apps rely on. Every host takes a client where it takes
  an app, so a Shiny app can show apps deployed on Posit Connect, Shiny
  apps served with Shiny’s own MCP support, and apps written in other
  languages. The connection and its credentials stay in
  18. 
- [`mcp_host_ui()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)
  and
  [`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)
  host an app in a pane of any Shiny app. The pane’s tool is called in
  R, and [`open()`](https://rdrr.io/r/base/connections.html) calls it
  again with other arguments.
  [`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
  makes the cards on their own. Panes and cards never hold up the
  session waiting on a remote server: for a remote server, call
  [`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
  where the app starts, since in a session it takes the tools only from
  the list the client already has. `McpClient$tools(wait = FALSE)`
  returns that list without asking the server.
- [`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md),
  [`mcp_embed()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md),
  [`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md),
  and
  [`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
  take a `source`, an app or an
  [`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md),
  where they took `app`. A pane’s `execute()` takes `inputs`, and
  `value_fn`’s `raw_result` is there only for apps in the same process.
  [`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
  needs its `tool` named for a remote server, and in a Shiny session it
  calls the tool first and returns a promise of the card, so the card is
  saved with the app’s result.
- A host passes on only the requests an app’s page may make: tools
  visible to the app, resource reads, and `ping`.
- [`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md),
  [`mcp_embed()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md),
  [`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md),
  [`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md),
  and
  [`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
  take `on_app_call`, a function that sees each tool call an app’s page
  makes before it’s sent, to let it through, refuse it with a reason the
  app is given, or record who did what. It can return a promise, to ask
  someone first. A function that fails, or doesn’t answer `TRUE`,
  `FALSE`, or a reason, refuses the call.
- A chat host passes the model’s arguments on as it sent them, so an
  array of one value reaches the app, or a remote server, as an array.
  `value_fn` gets them as parsed JSON, with arrays as lists.
- [`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md)
  shows the app as a chat client does, with panels for what the model
  receives, the context the app sends, tool calls, protocol messages,
  and the server’s tools.

### Rewriting apps as tools

- `convert_app()`, `as_mcp_apps()`, and the functions behind them
  (`parse_shiny_app()`, `analyze_reactive_graph()`, and
  `generate_mcp_app()`) are removed. Their drafts guessed at an app’s
  structure from its code and still left every tool to be written.
  [`vignette("rewriting-as-tools")`](https://jameshwade.github.io/shinymcp/articles/rewriting-as-tools.md)
  and the bundled skill take a person or a coding agent through the
  rewrite instead.
- [`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)
  serves a module’s UI with its server function, or with a `handler`
  function in its place.

### Serving Shiny apps as they are

- The model’s tool takes the app’s inputs as arguments, described from
  the UI (select inputs as choices, sliders as bounded numbers, dates as
  dates, tabsets as the tab to show). Its result reports what each
  output shows, with tables (DT’s included) as rows and plots as images.
  Passing `view` changes a view that is already open.
  [`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
  narrows what the model sees.
- New helpers for server functions:
  [`mcp_model_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md)
  and
  [`mcp_send_message()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md)
  to reach the model,
  [`mcp_host_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_context.md)
  for the client’s theme and display mode,
  [`mcp_request()`](https://jameshwade.github.io/shinymcp/reference/mcp_request.md)
  for the caller (and the signed-in user on Posit Connect), and
  [`is_mcp_session()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md).
- The app starts as
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) would
  start it: `global.R`, the files in `R/`, and `onStart` run before the
  UI is built, the app’s code runs in its directory, and `onStop` runs
  when the server stops. Files the UI loads from `www/` or
  [`addResourcePath()`](https://rdrr.io/pkg/shiny/man/resourcePaths.html)
  paths are written into the page.
- Sessions are limited by the `shinymcp.max_views` and
  `shinymcp.view_timeout` options (see
  [`help("shinymcp-options")`](https://jameshwade.github.io/shinymcp/reference/shinymcp-options.md)).
  A view whose session is gone starts a new one from the page’s inputs,
  whether the page was sending a change, downloading a file, or fetching
  a table’s rows, and the page then shows what the new session shows.
- An error in an observer ends the view’s session, as it ends a
  browser’s. The model, or the page, gets the error, and the page’s next
  change starts a new session.

### What works on a live app’s page

- Packages written for Shiny’s JavaScript work, because the page
  provides `window.Shiny`: input bindings (shinyWidgets, bslib’s
  sidebars, accordions, switches, and task buttons),
  `Shiny.setInputValue()` (DT row selection, `plotly::event_data()`,
  leaflet events), custom message handlers (shinyjs), and the `shiny:*`
  events (shinycssloaders).
- [`conditionalPanel()`](https://rdrr.io/pkg/shiny/man/conditionalPanel.html)
  works. Chat clients forbid
  [`eval()`](https://rdrr.io/r/base/eval.html), so shinymcp reads
  conditions itself; it understands comparisons, logic, arithmetic,
  `input.x`, `output.x`, `.length`, regular expressions, and common
  string and array methods.
- Clicks, double clicks, hovers, and brushes on plots send what Shiny’s
  client sends, so
  [`nearPoints()`](https://rdrr.io/pkg/shiny/man/brushedPoints.html) and
  [`brushedPoints()`](https://rdrr.io/pkg/shiny/man/brushedPoints.html)
  work.
- [`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html),
  [`insertUI()`](https://rdrr.io/pkg/shiny/man/insertUI.html), modals,
  notifications, downloads, and
  [`insertTab()`](https://rdrr.io/pkg/shiny/man/insertTab.html),
  [`removeTab()`](https://rdrr.io/pkg/shiny/man/insertTab.html),
  [`hideTab()`](https://rdrr.io/pkg/shiny/man/showTab.html), and
  [`showTab()`](https://rdrr.io/pkg/shiny/man/showTab.html) reach the
  page.
- [`fileInput()`](https://rdrr.io/pkg/shiny/man/fileInput.html) uploads
  work, within `shiny.maxRequestSize`.
- `updateSelectizeInput(server = TRUE)` works: the page shows the first
  1,000 choices, with a search box for the rest.
- [`invalidateLater()`](https://rdrr.io/pkg/shiny/man/invalidateLater.html)
  and
  [`reactivePoll()`](https://rdrr.io/pkg/shiny/man/reactivePoll.html)
  run while the app is open, and an `ExtendedTask`’s result appears when
  the task finishes.
- [`varSelectInput()`](https://rdrr.io/pkg/shiny/man/varSelectInput.html)
  values arrive as symbols, and outputs set to a
  [`reactive()`](https://rdrr.io/pkg/shiny/man/reactive.html) work.
- Leaflet’s default markers show. The leaflet package loads their images
  from a CDN, which chat clients block; the page carries them instead.

### Documentation

- New articles: building an app from tools, running an app, hosting MCP
  Apps in Shiny, rewriting a Shiny app as tools, serving a Shiny app as
  it is, how shinymcp works, and troubleshooting. The README and “Get
  started” build an app from a tool.
