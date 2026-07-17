# Path forward: shinymcp alongside Shiny's first-party MCP Apps support

*Drafted July 2026, in response to rstudio/shiny PRs #4407/#4409/#4412/#4414/#4418
(SEP-1865) and the Shiny team's `mcp/comparison-shinymcp.md`.*

## Context

The Shiny team has merged first-party MCP Apps support: the full Shiny runtime
runs server-side and its websocket protocol is tunneled through MCP tools
(`_shiny_send` / `_shiny_receive` / `_shiny_http`), so existing apps render in
Claude and other MCP hosts unchanged. Their comparison doc concludes the two
projects are "legitimately different products" whose overlap is
"undifferentiated protocol plumbing, which is the natural place to converge."

This document takes them up on that. The plan: keep shinymcp's differentiated
product, adopt the pieces of Shiny's work we need, and delegate the redundant
plumbing to mcptools instead of maintaining it in parallel.

## Principles

1. **One plumbing, two products.** JSON-RPC dispatch, transports, and resource
   handling should exist once in the R ecosystem (mcptools). The programming
   models — Shiny's live-session tunnel and shinymcp's stateless tools — stay
   distinct because they solve different problems.
2. **Cede the "dashboard in chat" use case.** Zero-rewrite rendering of an
   existing app belongs to shiny. shinymcp stops pitching `convert_app()` as
   the way to get a dashboard into Claude; it becomes a scaffolding aid for
   authoring tool-first apps.
3. **Interoperate, don't parallel-build.** Where shiny grows a surface we need
   (deployment discovery, CSP conventions, `registerMcpTool()`), we target it
   rather than reimplementing it.
4. **Name the sunset condition up front.** If Posit ships a first-party
   stateless/tool mode and MCP App hosting for Shiny/shinychat, shinymcp's
   remaining surface goes to zero; the right move then is to upstream what is
   left and archive with a pointer. Writing this down keeps every intermediate
   decision honest.

## What shinymcp is, going forward

**Typed R capabilities with a UI, plus MCP App hosting for Shiny.**

- Tools are the product; the interactive card is an enhancement. Results work
  in every MCP client, including text-only ones.
- Stateless by design: no Shiny session per viewer, deployable anywhere an R
  process runs, including stdio on a laptop.
- The only R-side host for MCP Apps: embed apps from any server (including
  shiny's own tunneled apps) inside Shiny and shinychat via
  `mcp_embed()` / `mcp_host_ui()`.

## Component disposition

| Component | Files | Disposition |
|---|---|---|
| Convert pipeline | `parse.R`, `detect.R`, `analyze.R`, `generate.R`, `convert.R` | **Keep, reframe.** Scaffolding for tool-first apps and migration aid, not the headline. Generator additionally emits `ellmer::tool()` definitions compatible with shiny's `registerMcpTool()`. |
| Components + binding | `components-*.R`, `bind-mcp.R`, `mcp-tool-module.R` | **Keep.** Core authoring surface for the stateless model. |
| Typed results | `results.R` | **Keep.** Graceful degradation is a strength the shiny team flagged for adoption; offer it upstream. |
| Runtime | `mcp-app.R`, `as-mcp-app.R` | **Keep.** |
| JS bridge (iframe side) | `js-bridge.R`, `inst/js/shinymcp-bridge.js` | **Keep.** It is the stateless model's client; not redundant with shiny's tunnel bridge. |
| Host / embed | `host-base.R`, `host-shiny.R`, `preview.R`, `inst/js/shinymcp-host.js` | **Keep, elevate to flagship.** No first-party equivalent; value grows as first-party MCP Apps proliferate. Verify it can host shiny-tunneled apps. |
| Resources protocol | `mcp-resources.R` | **Upstream to mcptools.** Already designed as an extractable module; mcptools has no resources support today. |
| Server transports | `serve.R` (stdio + HTTP JSON-RPC dispatch) | **Delegate to mcptools.** Once resources land upstream, `serve()` becomes a thin wrapper over `mcptools::mcp_server()`; delete the bespoke transport code. Public API stays stable. |

### What we bring in from shiny

- **`registerMcpTool()` / ellmer alignment** — both projects use
  `ellmer::tool()`; make shinymcp-generated tools drop-in registrable in a
  `mcpConfigure()`'d app so authors can mix models.
- **Deployment discovery** — their deployment-record / Quarto-metadata URL
  logic, if/when shinymcp targets Connect and shinyapps.io.
- **Protocol conventions** — `_meta.ui.csp.*`, appId namespacing, and display
  handling, so apps from either stack behave identically in hosts (including
  ours).

### What we offer upstream

- The `ResourceRegistry` + resources JSON-RPC handling (to mcptools).
- Graceful text/structured degradation for non-Apps hosts (to shiny).
- Automatic input-state → `ui/update-model-context` reporting (to shiny; theirs
  is opt-in via `mcpUpdateModelContext()`).
- Host-side experience: `preview_app()`'s protocol log is useful tooling for
  anyone developing MCP Apps in R.

## Phases

**Phase 0 — Outreach (now, while #4409 is still a draft).**
Respond to `mcp/comparison-shinymcp.md` on rstudio/shiny: agree with the
convergence framing, commit to paths 2–4 from their doc. Open an issue on
posit-dev/mcptools proposing resources support, offering `mcp-resources.R` as
the seed. Exit: maintainers aligned on where the shared core lives.

**Phase 1 — Upstream the plumbing.**
PR the resources module to mcptools; propose the shared JSON-RPC dispatch core
there too (both shinymcp and shiny carry small dispatchers). Exit: mcptools
release with resources support.

**Phase 2 — Delegate.**
Rebuild `serve()` on mcptools; delete `serve_stdio()` / `serve_http()` and the
duplicated dispatch; move mcptools from Suggests toward a required dependency
for serving. Exit: no transport code in shinymcp; tests green against the
mcptools-backed server.

**Phase 3 — Interoperate with shiny.**
Generator emits `registerMcpTool()`-ready tool definitions; `mcp_embed()`
verified against a shiny-tunneled MCP App; adopt shared `_meta.ui.*`
conventions; borrow deployment discovery if pursuing Connect/shinyapps.io.
Exit: a converted app's tools load in a `mcpConfigure()`'d shiny app; a
first-party MCP App renders inside a shinymcp host.

**Phase 4 — Reposition.**
README rewritten around tools-first + hosting; add a "shinymcp vs. Shiny's
built-in MCP support" vignette mirroring and cross-linking their comparison
doc; demote `convert_app()` in the pkgdown structure. Exit: a user landing on
either project's docs is routed to the right one in under a minute.

## What we explicitly stop doing

- Marketing conversion as the path to "your dashboard in chat."
- Building session-like or tunnel-like features; anything stateful belongs to
  shiny's model.
- Maintaining bespoke transports once mcptools covers them.

## Success and sunset metrics

Watch *what* users build, not download counts. Success: people authoring
tool-first apps and embedding MCP Apps in Shiny. Sunset trigger: usage is
dominated by dashboard conversion (that audience belongs upstream), or Posit
ships first-party stateless tools + hosting — in which case, upstream the
remainder and archive gracefully.

## Open questions

- Does mcptools want the resources module and a shared dispatch core, or does
  the shiny team prefer that core elsewhere? (Their doc suggests mcptools.)
- Should the host/embed surface eventually live in shinychat rather than
  shinymcp? Revisit after Phase 3 with the shinychat maintainers.
- Timeline for `mcpConfigure()` API stability — Phase 3 interop targets an
  experimental surface and may need to track breaking changes.
