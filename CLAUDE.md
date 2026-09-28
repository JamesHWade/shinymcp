# CLAUDE.md

This file provides guidance for AI assistants working with the shinymcp codebase.

## Project Overview

**shinymcp** is an R package that builds MCP Apps from R functions and
Shiny UI. An MCP App is a tool whose result comes with a page (a `ui://`
resource) that chat clients such as Claude, ChatGPT, and VS Code show in a
sandboxed iframe and talk to over postMessage JSON-RPC.

- **Apps built from tools.** `mcp_app()` pairs a UI with stateless tools
  (ellmer tools or plain lists). Inputs match tool arguments by id; the
  lists tools return fill outputs by id. This is the package's core.
- **Serving.** `serve()` (stdio and Streamable HTTP), `mcp_endpoint()`
  (an endpoint inside a Shiny app, for Posit Connect), both MCP eras: the
  handshake versions 2024-11-05 to 2025-11-25 and stateless 2026-07-28.
- **Hosting.** `mcp_chat_host()` (shinychat conversations) and
  `mcp_host_ui()`/`mcp_host_server()` (a pane of any Shiny app) show MCP
  Apps the way a chat client does, from apps in this process or any MCP
  server through `mcp_client()`. R holds every connection; the page's
  requests reach R over the Shiny session. `preview_app()` is a separate,
  browser-side host for development. `design/hosting.md` is the design.
- **Live Shiny apps (transitional).** `as_mcp_app()` serves a Shiny app as
  it is: the server function runs in R, one `MockShinySession` per view of
  the app, and the page sends input changes to it through an app-only view
  tool.

### Scope

Shiny is gaining its own MCP support (rstudio/shiny#4407, the `mcp`
branch). When that is released on CRAN, shinymcp stops serving live Shiny
apps; `design/live-runtime-removal.md` is the plan (what goes, what stays,
what to take upstream first, the migration table). Until then the live
runtime is frozen: fix bugs in it, but add no features, and write new
examples and docs as tool apps. Rewriting an app as tools is a guide and a
skill, not code: the `convert_app()` pipeline was removed.

## Directory Structure

```
shinymcp/
├── R/
│   │   # Apps
│   ├── mcp-app.R              # McpApp R6 class and mcp_app()
│   ├── tools.R                # Normalize ellmer/list tools; run handlers
│   ├── schema.R               # JSON Schema for tools; argument checks
│   ├── results.R              # mcp_result_*(), mcp_tool_result(); three-level results
│   ├── components-input.R     # mcp_select() and relatives, mcp_input(), mcp_output()
│   ├── components-output.R    # mcp_text(), mcp_plot(), mcp_table(), mcp_html()
│   ├── detect.R               # Classify rendered tags as inputs/outputs
│   ├── mcp-tool-module.R      # mcp_tool_module(): serve a Shiny module
│   │   # Live Shiny apps (transitional; see design/live-runtime-removal.md)
│   ├── as-mcp-app.R           # as_mcp_app(): Shiny app, directory, or McpApp -> McpApp
│   ├── runtime.R              # ShinyRuntime: live sessions, the model and view tools
│   ├── runtime-inputs.R       # Describe a Shiny UI's inputs (kinds, defaults, schema)
│   ├── bind-mcp.R             # bindMcp(): choose what the model sees
│   │   # The page
│   ├── html.R                 # Build the ui:// page and the bridge config
│   ├── assets.R               # Inline www/ and addResourcePath() files, CSS urls
│   │   # Serving
│   ├── protocol.R             # McpServer: versions, JSON-RPC dispatch
│   ├── transport-stdio.R      # stdio transport
│   ├── transport-http.R       # Streamable HTTP handler; Origin/Host checks
│   ├── serve.R                # serve()
│   ├── endpoint.R             # mcp_endpoint() for Posit Connect and Shiny Server
│   │   # Hosts
│   ├── client.R               # mcp_client(), McpClient: remote servers, both eras
│   ├── host-source.R          # Sources: in-process apps or a client, one interface
│   ├── host-base.R            # Instance state shared by panes and cards
│   ├── host-shiny.R           # The session registry, attach, the page's requests; panes
│   ├── shinychat.R            # as_shinychat_tool(), mcp_content_result(): cards
│   ├── chat-host.R            # mcp_chat_host(): tools, context before each message
│   ├── preview.R              # preview_app()
│   │   # Shared
│   ├── utils.R
│   ├── errors.R               # shinymcp_abort() and error classes
│   └── shinymcp-package.R
├── inst/
│   ├── js/shinymcp-bridge.js  # The page's bridge (ES5): protocol, inputs, outputs
│   ├── js/shinymcp-shiny.js   # window.Shiny stand-in for packages written for Shiny
│   ├── js/shinymcp-host.js    # Host side, for mcp_host_ui() and shinychat cards
│   ├── preview/host.html      # preview_app()'s host page
│   ├── skills/convert-shiny-app/SKILL.md  # Agent skill: rewrite or serve an app
│   └── examples/              # Runnable apps; README.md indexes them
├── vignettes/                 # Articles (see _pkgdown.yml for the site's menus)
├── design/                    # Design notes and plans, not built into the package
├── tests/testthat/            # testthat edition 3
└── man/                       # Generated by roxygen2
```

## Common Commands

### Testing

```bash
NOT_CRAN=true Rscript -e "devtools::test()"
Rscript -e "testthat::test_file('tests/testthat/test-runtime.R')"
Rscript -e "devtools::test(filter = 'runtime')"
```

### Code Quality

```bash
Rscript -e "devtools::check()"
air format R/ tests/testthat/
Rscript -e "devtools::document()"
npx --yes acorn --ecma5 --silent inst/js/shinymcp-bridge.js   # the bridge must stay ES5
```

The browser side has no automated tests. After changing the bridge or the
shim, check the app in a browser: `preview_app()`, or Playwright against it.

### Building

```bash
Rscript -e "devtools::build()"
Rscript -e "devtools::install()"
Rscript -e "pkgdown::build_site()"
```

## Code Conventions

- **Formatter**: Air (config in `air.toml`)
- **Documentation**: roxygen2 with markdown. Public docs say what a function
  does and when to use it, for R users; internal design goes in comments.
- **Classes**: R6 for mutable runtime owners (`McpApp`, `McpServer`,
  `ShinyRuntime`)
- **Errors**: `shinymcp_abort()` with a `shinymcp_error_*` class (see
  `R/errors.R`); tool errors go back to the model as `isError` results
- **Style**: tidyverse conventions, `%||%` from rlang
- **JavaScript**: vanilla ES5 in an IIFE, no build step (no `const`, `let`,
  arrow functions, classes, or `Set`)

### Inputs and outputs on the page

The bridge finds inputs by id: an element with the id of a tool argument
(tools mode) or of a Shiny input (live mode). It draws Shiny's built-in
inputs itself through adapters (`inputKind()`, `makeAdapter()`); inputs
from packages that register a Shiny input binding go through that binding,
via the `window.Shiny` stand-in. `data-shinymcp-input` and
`data-shinymcp-output` attributes (from `mcp_*()` components, `bindMcp()`,
`mcp_input()`, `mcp_output()`) mark elements explicitly.

A tool that takes an action button's id runs when the button is pressed,
not when its other inputs change. The page never runs tools annotated
`readOnlyHint: false` or `destructiveHint: true` on its own, to fill
outputs or because their inputs changed: only from a button they take
(`toolsForInputs()`, `refreshesOutputs()`).

Hosts' CSP forbids `eval()` and `new Function()`, so nothing on the page may
use them. `conditionalPanel()` conditions go through a small interpreter in
the bridge (`parseCondition()`, `evaluateCondition()`); plot clicks, hovers,
and brushes are a port of Shiny's `imageutils` (`setupPlotInteractions()`),
fed by the coordmap each plot payload carries. Check changes to either
against the same app in real Shiny: the input values should match.

## Architecture

### MCP Apps Protocol

MCP Apps (extension version 2026-01-26) use:
- `ui://` resource URIs to declare HTML content
- `text/html;profile=mcp-app` MIME type
- postMessage/JSON-RPC between host and iframe
- `_meta.ui.resourceUri` on a tool to link it to its page, and
  `_meta.ui.visibility` for tools only the page may call
- A Content Security Policy that blocks what the app doesn't declare
  (`csp` in `mcp_app()`); fonts in the page can't load

Clients without UI support get no app-only tools and no `_meta.ui`.

### Results

Every tool result has three levels: `content` (text for the model),
`structuredContent` (data for the model), and `_meta["shinymcp/view"]`
(what the page draws: HTML, images, widget data, dependencies), which
clients keep from the model. Dependencies the page already has are left
out; in results for the model, large ones go by name and the page fetches
them through the view tool.

Each call the page makes carries `_meta["shinymcp/sizes"]` (its plot
outputs' sizes: `plotOutput()` and `mcp_plot()`; an `mcp_plot()` without a
height gives only its width) and `_meta["shinymcp/pixelRatio"]`. A plot
without a size of its own is drawn at its output's (keeping its shape when
only a width is given) and marked `fit`; the page calls a tool again when
its fitted plots don't match their outputs (after the model's call opens
the app, and on resize).

### Hosts

A card (shinychat) or pane carries a descriptor, not the page: instance
id, source key, tool, arguments, and the result when there is one. The
host script sends it to R to attach (`shinymcp_host_event` input, type
`attach`); R answers with the page from `resources/read` (cached per
session) over the `shinymcp-host-attached` message. A card restored with
a saved conversation attaches the same way: R recreates the instance if
the session registered its source, and never calls the tool for it. The
page's requests come in as `request` events and go to the instance's
source (`R/host-source.R`: an in-process `McpServer` run from `later()`,
or an `McpClient`), only for `tools/call` of tools visible to the app,
resource reads, and `ping`. Everything is asynchronous (promises), so a
remote long poll doesn't block the session. Never call a remote source's
`tools()` from a session: an instance's tool is checked through
`host_ready()`, a promise its call and attach wait on (apps in the same
process are checked at registration, so mistakes stay errors). Only
`mcp_chat_host()` lists tools synchronously, because ellmer needs them and
it is called in the session. `as_shinychat_tool()` in a session takes a
remote server's tools only from its client's kept list
(`tools(wait = FALSE)`), and is an error without one.

`mcp_chat_host()` adds each open card's model context to the model's
input from `Chat$on_request_start()`: a user turn of its own before the
person's message (never before tool results), removed in
`on_request_end()` once the reply has no tool requests left. Each chat
host has a key (`chat_id`, else `chat-<n>` by its place in the session);
its cards carry it as `owner`, in their descriptors too, and only its own
cards' context and messages reach it (`registry$chat_hosts`). A card built
by hand belongs to the session's only chat host.

### Live runtime (transitional)

`ShinyRuntime` gives each live app two tools: the model's tool (named
after the app), which opens a view, and `<name>_view`, app-only, with the
actions `update`, `download`, `data`, `dependency`, and `close`. Each view
is a subclass of `shiny::MockShinySession` that records what the server
sends to the browser (outputs, input updates, notifications, modals,
inserted UI, custom messages, tab changes). Views carry a revision; a page
that missed updates, or whose session is gone, sends all its inputs.
Timers (`invalidateLater()`) run when the page calls back at the time each
result gives. Limits: `shinymcp.max_views`, `shinymcp.view_timeout`.

The app starts as `shiny::runApp()` would: `global.R`, `R/`, and
`onStart`, in the app's directory (`app_lifecycle()` in `R/runtime.R`).

### The page

`McpApp$html_resource()` renders the UI once and writes everything into
one self-contained document (hosts may load it from `srcdoc`):
dependencies, `www/` files, stylesheets with their images as `data:` URIs,
the `window.Shiny` stand-in at the top of `<head>`, and the bridge with its
config (`#shinymcp-config`) at the end of `<body>`.

### Key Design Decisions

1. **No Shiny client on the page.** The bridge replaces shiny.js; the
   stand-in provides only the parts of `window.Shiny` packages use.
2. **Tools first.** Every call stands alone, so any R process can answer
   it and every tool is useful without the page. Serving a live Shiny app
   is transitional (see Scope).
3. **Self-contained pages and JS.** No npm build step, no network.
4. **Approval stays with the person.** Tools that change something can be
   app-only (`tool_visibility`), run from a button in the page.

## Dependencies

**Core** (Imports): cli, grDevices, htmltools, jsonlite, methods, R6,
rlang, stats, tools, utils
**Optional** (Suggests): base64enc, bslib, curl, DT, ellmer, ggplot2,
htmlwidgets, httpuv, httr2, knitr, later (>= 1.4.0), palmerpenguins,
promises, rmarkdown, S7, shiny, shinychat, shinyWidgets, testthat, withr

Suggests must be guarded at every call site (`rlang::check_installed()` or
`requireNamespace()`), since R CMD check builds without them.

## Issue Tracking

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

### Session Completion

When ending a work session, complete ALL steps below. Work is NOT complete until `git push` succeeds.

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Push to remote**:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
