# shinymcp (development version)

This version reworks shinymcp around serving Shiny apps as they are, with
their server functions running live in R, and rewrites the protocol layer,
the page's JavaScript, the hosts, and the documentation.

## Changes in behavior

* `as_mcp_app()` runs a Shiny app's server function, one session per view
  of the app, instead of building tools from its reactive graph. Given
  `tools`, it uses them as before.
* `serve()` and `preview_app()` serve a Shiny app object or an app
  directory live. A path used to be converted with `convert_app()` first.
* `convert_app()` writes `ui.R`, `tools.R`, and `app.R`; it no longer
  writes `server.R`.
* Model-facing text no longer says a plot or widget is "shown in the app":
  a client may not show it.

## Serving Shiny apps

* The model's tool takes the app's inputs as arguments, described from the
  UI (select inputs as choices, sliders as bounded numbers, dates as
  dates, tabsets as the tab to show), and its result reports what each
  output shows, with tables (DT's included) as rows and plots as images. Passing `view` changes a view that is
  already open. `bindMcp()` narrows what the model sees.
* Packages written for Shiny's JavaScript work on the page, which provides
  `window.Shiny`: input bindings (shinyWidgets), `Shiny.setInputValue()`
  (DT row selection, `plotly::event_data()`, leaflet events), custom
  message handlers (shinyjs), and the `shiny:*` events (shinycssloaders).
* `fileInput()` uploads work, within `shiny.maxRequestSize`.
* `conditionalPanel()` works. Chat clients forbid `eval()`, so shinymcp
  reads conditions itself; it understands comparisons, logic, arithmetic,
  `input.x`, `output.x`, `.length`, regular expressions, and common string
  and array methods.
* Clicks, double clicks, hovers, and brushes on plots send what Shiny's
  client sends, so `nearPoints()` and `brushedPoints()` work.
* `varSelectInput()` values arrive as symbols, and outputs set to a
  `reactive()` work.
* `updateSelectizeInput(server = TRUE)` works: the page shows the first
  1,000 choices, with a search box for the rest.
* `invalidateLater()` and `reactivePoll()` run while the app is open, and
  an `ExtendedTask`'s result appears when the task finishes.
* bslib's inputs work: sidebars, accordions, navsets, switches, and task
  buttons, including their `update_*()` and `accordion_panel_open()`
  style functions.
* `renderUI()`, `insertUI()`, modals, notifications, downloads, and
  `insertTab()`, `removeTab()`, `hideTab()`, and `showTab()` reach the page.
* The app starts as `shiny::runApp()` would start it: `global.R`, the
  files in `R/`, and `onStart` run before the UI is built, the app's code
  runs in its directory, and `onStop` runs when the server stops. Files the UI loads
  from `www/` or `addResourcePath()` paths are written into the page.
* New helpers for server functions: `mcp_model_context()` and
  `mcp_send_message()` to reach the model, `mcp_host_context()` for the
  client's theme and display mode, `mcp_request()` for the caller (and the
  signed-in user on Posit Connect), and `is_mcp_session()`.
* Sessions are limited by the `shinymcp.max_views` and
  `shinymcp.view_timeout` options (see `help("shinymcp-options")`). A view
  whose session is gone starts a new one from the page's inputs.
* An error in an observer ends the view's session, as it ends a browser's.
  The model, or the page, gets the error, and the page's next change
  starts a new session.

## Apps built from tools

* Tool arguments from the model are checked against declared schemas;
  a missing or mistyped argument goes back to the model as a tool error.
* `mcp_tool_result()` sets a result's text and structured data.
* A tool that takes a button's id runs when the button is pressed, and no
  longer whenever its other inputs change. The page doesn't run tools
  annotated as changing something to fill in outputs.
* `mcp_submit_button()` places the apply button for
  `mcp_app(trigger = "submit")`.
* `mcp_app(www = )` writes a folder of scripts, stylesheets, and images
  into the page.
* `mcp_app(theme = )` refuses a UI that is already a page, instead of
  nesting two pages.

## Protocol and serving

* The server speaks MCP 2024-11-05 through 2025-11-25 and the stateless
  2026-07-28 revision, and MCP Apps 2026-01-26. It was tested with the
  official MCP TypeScript client and the MCP Apps host SDK.
* New `mcp_endpoint()` adds an MCP endpoint to a Shiny app, for Posit
  Connect, Shiny Server, and shinyapps.io. On Posit Connect, tools and
  server functions see the signed-in user.
* The HTTP transport checks `Origin` and, on a local server, `Host`
  (against DNS rebinding); `serve()` gains `allowed_origins` and
  `allowed_hosts`.
* Results leave out libraries the page already has, and results for the
  model name large libraries instead of carrying them.

## Hosts

* `preview_app()` shows the app as a chat client does, with panels for what
  the model receives, the context the app sends, tool calls, protocol
  messages, and the server's tools.
* `mcp_host_ui()` and `mcp_host_server()` host apps in any Shiny app;
  `as_shinychat_tool()` shows them live in shinychat conversations.

## Rewriting apps as tools

* `convert_app()`'s draft tools take typed arguments with the app's
  defaults, carry the reactive expressions they use, and return their
  outputs by id, so the draft runs straight away.
* `mcp_tool_module()` no longer needs a module server when `handler` is
  given.

## Documentation

* New articles: serving a Shiny app, building an app from tools, running
  an app, apps in shinychat and Shiny, rewriting an app as tools, how
  shinymcp works, and troubleshooting.
