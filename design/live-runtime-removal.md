# Removing live Shiny serving

Planned 2026-09-28. Nothing is removed yet.

**Trigger:** Shiny's own MCP support ([rstudio/shiny#4407]) is released on
CRAN. When that happens, shinymcp stops serving live Shiny apps and keeps
what Shiny doesn't do: MCP Apps built from tools, serving them, and hosting
them in Shiny and shinychat.

[rstudio/shiny#4407]: https://github.com/rstudio/shiny/pull/4407

## Why

Shiny's branch runs the real shiny.js against a real session. shinymcp's
live runtime reimplements Shiny's browser side (the bridge's live paths and
the `window.Shiny` stand-in) and runs each view on `MockShinySession`, which
Shiny built for tests. Shiny's branch gets the browser side right by
construction; ours has gaps to close (`withProgress()`, output bindings
from packages, server pushes between interactions). It is also the largest part of the
package: `R/runtime.R` and `R/runtime-inputs.R` are 3,600 of its 11,700
lines of R, and their tests are 4,700 lines.

Tool apps don't overlap with Shiny. The branch's `registerMcpTool()` tools
have no UI, and its only UI is a whole live session. Released R packages
(mcptools 1.0.3, ellmer 0.5.0, shinychat 0.5.0) don't support MCP Apps at
all.

## Until then

- The live runtime is frozen: bug fixes, no new features.
- The docs lead with tool apps. Live serving is documented as transitional,
  with a pointer to Shiny's support, in `vignette("shiny-apps")` and in the
  "Shiny's own MCP support" section of the reference pages it affects.
- New examples are tool apps.

## Before removing

Take these to the Shiny team first, so that removal loses as little as
possible. As of the branch's last commit (c394d5b, 2026-07-17), Shiny
doesn't do them:

1. **A real result from the call that opens the app.** The branch returns
   fixed text ("The Shiny app is now displayed in the conversation"),
   because its session starts only when the page connects. shinymcp runs
   the server function during the call, so the result reports what the
   outputs show, the model can read it, and clients that can't show apps
   still get an answer.
2. **The model's arguments applied before the first render.** The branch
   delivers them through `mcpUpdates()` after the page has rendered, and
   its notes call the flash of defaults unavoidable.
3. **`conditionalPanel()` without `eval()`.** The MCP Apps default CSP has
   no `'unsafe-eval'`, and shiny.js evaluates conditions with
   `new Function()`. The bridge's condition reader (`parseCondition()`,
   `evaluateCondition()`) is a working reference.
4. **MCP 2025-11-25 and the stateless 2026-07-28 revision.** The branch
   stops at 2025-06-18.
5. **Choosing what the model sees.** `bindMcp()` began as a suggestion
   from the Shiny team; the branch declares arguments by hand in
   `mcpConfigure(arguments = )`.

And in shinymcp:

- `mcp_endpoint()` needs a way to serve tool apps next to a Shiny app, for
  example `mcp_endpoint(shiny_app, apps = list(tool_app))`. Today a Shiny
  app given to it is always served live, so without this the "one
  deployment for people and models" story ends with the removal.
- Write the migration notes below into NEWS and the Shiny article, checked
  against the released API.

## What goes

R:

- `ShinyRuntime` and the live session class (`R/runtime.R`), and
  `R/runtime-inputs.R`.
- `as_mcp_app()` for Shiny apps and app directories. Its methods for an
  `McpApp`, and for a file or directory whose `app.R` builds one, stay.
- `mcp_model_context()`, `mcp_send_message()`, `is_mcp_session()`,
  `mcp_host_context()`.
- `mcp_tool_module()` without `handler` (the module's server running
  live). The `handler` form stays.
- `mcp_endpoint()` for a Shiny app on its own (see above).
- `bindMcp()`. Its purpose is choosing what the model sees of a live app;
  in tool apps it duplicates `mcp_input()` and `mcp_output()`.
- The live-only options: `shinymcp.max_views`, `shinymcp.view_timeout`,
  `shinymcp.max_download_bytes`.

JavaScript:

- The bridge's live paths: the view protocol (revisions, restarting a
  view from the page's inputs, timers), uploads, downloads, messages from
  the server (notifications, modals, inserted UI, custom messages, tab
  changes), and the data transport for DT and server-side selectize. Audit
  every branch on the bridge's `MODE` (14 today) and the functions only
  the live branches call. Plot clicks and brushes can stay if tool apps
  can use them as arguments; decide then.
- The `window.Shiny` stand-in stays: tool-app pages use it for input
  bindings from packages. Trim what only live views use.

Tests, examples, docs:

- `test-runtime.R`, `test-runtime-inputs.R`, `helper-runtime.R`, and the
  live tests in `test-as-mcp-app.R`, `test-endpoint.R`,
  `test-mcp-tool-module.R`, and `test-examples.R`.
- Examples: `faithful`, `fuel-economy`, `shiny-packages`, `shiny-module`,
  and `posit-connect` (rewrite it for tool apps next to a Shiny app).
- `vignette("shiny-apps")` becomes a short page on moving to Shiny's
  support. The live sections of `vignette("troubleshooting")` and the
  skill's "serving the app as it is" route go.
- Suggests used only by the live runtime or its examples and tests:
  `later` (check the hosts first; `R/host-shiny.R` and `R/shinychat.R`
  use it too), `shinyWidgets`, and `DT`.

No deprecation release: shinymcp isn't on CRAN, and NEWS carries the
migration notes.

## Migration

Names as of the branch; check them against the release.

| shinymcp | Shiny |
|---|---|
| `as_mcp_app(shinyApp(ui, server), name = , description = )` | `mcpConfigure(appId = , description = )` in the app |
| Tool arguments read from the UI | `mcpConfigure(arguments = )`, applied with `mcpUpdates()` and `update*Input()` |
| `view` to change an open view | the `update_<appId>_app` tool |
| `as_mcp_app(tools = )` | `registerMcpTool()` |
| `mcp_model_context()` | `mcpUpdateModelContext()` |
| `mcp_send_message()` | `mcpSendMessage()` |
| `mcp_host_context()` | `mcpHostContext()` |
| `is_mcp_session()` | `isMcpSession()` |
| `bindMcp()` on a live app | `mcpConfigure(arguments = )` |
| `mcp_endpoint(shiny_app)` | Shiny serves `/mcp` itself |
| Outputs in the result of the call that opens the app | none; rewrite what the model must read as tools |
| Clients that can't show apps | none; tools |
