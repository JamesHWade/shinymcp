# Path forward: shinymcp alongside Shiny's first-party MCP Apps support

*Drafted July 2026 in response to rstudio/shiny PRs #4407/#4409/#4412/#4414/#4418
(SEP-1865) and the Shiny team's `mcp/comparison-shinymcp.md`. Revised after a
full codebase review and upstream survey; corrections from that review are
folded in throughout and itemized in the appendix.*

## Context

The Shiny team has merged first-party MCP Apps support: the full Shiny runtime
runs server-side and its websocket protocol is tunneled through MCP tools
(`_shiny_send` / `_shiny_receive` / `_shiny_http`), so existing apps render in
Claude and other MCP hosts unchanged. Their comparison doc concludes the two
projects are "legitimately different products" whose overlap is
"undifferentiated protocol plumbing, which is the natural place to converge."

Two upstream facts make this plan concrete rather than speculative:

1. **The mcptools convergence is already scoped — by the Shiny team.**
   schloerke filed posit-dev/mcptools #115 (tracking) plus #116 (resources),
   #117 (tool `_meta`), #118 (async tool handlers), #119 (embeddable JSON-RPC
   dispatch), and #120 (non-blocking stdio) on July 13, explicitly so
   frameworks "like Shiny and Plumber" can delegate protocol handling to
   mcptools. Related pre-existing gaps: #103 (outputSchema), #104
   (structuredContent). Shiny's `mcp/QUESTIONS.md` marks upstreaming as
   *resolved via those issues*. We do not need to propose a shared core; we
   need to show up to an invitation that already exists, with working code.

2. **The host/embed upstream path already exists — we opened it.**
   posit-dev/shinychat #175 ("Support MCP Apps protocol for rendering
   interactive UIs inline", filed February 2026 by @JamesHWade, referencing
   shinymcp) has no linked PR or maintainer response yet. shinymcp's host code
   is the natural reference implementation for our own issue.

rstudio/shiny #4409 (the integration PR) is still a draft with no reviews or
assignees — the window for influencing the experimental API is open.

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
4. **Be honest about what exists.** The review below found real gaps between
   this plan's ambitions and today's code (remote hosting, async execution,
   the size of the serve() delegation). Phases are gated on those gaps, not
   written as if they were closed.
5. **Name the sunset condition up front.** If Posit ships a first-party
   stateless/tool mode and MCP App hosting for Shiny/shinychat, shinymcp's
   remaining surface goes to zero; the right move then is to upstream what is
   left and archive with a pointer.

## What shinymcp is, going forward

**Typed R capabilities with a UI, plus MCP App hosting for Shiny.**

- Tools are the product; the interactive card is an enhancement. Results work
  in every MCP client, including text-only ones (per-session capability
  negotiation in `serve.R:398` / `utils.R:213` already withholds `_meta.ui`
  from non-Apps clients automatically).
- Stateless by design: no Shiny session per viewer, deployable anywhere an R
  process runs, including stdio on a laptop.
- The only R-side host for MCP Apps: embed apps inside Shiny and shinychat via
  `mcp_embed()` / `mcp_host_ui()`. Today this hosts **local McpApp tools
  only**; remote-server hosting is Phase 3 work (see gaps below).

## Component disposition

| Component | Files | Disposition |
|---|---|---|
| Convert pipeline | `parse.R`, `detect.R`, `analyze.R`, `generate.R`, `convert.R` | **Keep, reframe.** Scaffolding for tool-first apps and migration aid, not the headline. `generate.R` *already emits* `ellmer::tool()` source with typed arguments and `tool_annotations()`; remaining work is `registerMcpTool()` signature compatibility, not ellmer emission. |
| Components + binding | `components-*.R`, `bind-mcp.R`, `mcp-tool-module.R` | **Keep.** Core authoring surface for the stateless model. |
| Typed results | `results.R` | **Keep.** The three-faced result (`value` / `model_value` / `text`) is the graceful-degradation design the shiny team flagged for adoption; offer it upstream. The shinychat integration (`as_shinychat_tool()`, `ellmer::ContentToolResult`) already exists here. |
| Runtime | `mcp-app.R`, `as-mcp-app.R` | **Keep.** Consider promoting `ellmer::ToolDef` from optional path to canonical tool format (see open questions) — today the default runtime format is a bespoke plain list and ellmer is Suggests-gated. |
| JS bridge (iframe side) | `js-bridge.R`, `inst/js/shinymcp-bridge.js` | **Keep.** It is the stateless model's client; not redundant with shiny's tunnel bridge. |
| Host / embed | `host-base.R`, `host-shiny.R`, `preview.R`, `inst/js/shinymcp-host.js` | **Keep, elevate — with eyes open.** The JS transport is promise-based end to end and implements the full protocol surface (`ui/initialize`, `tools/call`, `resources/read`, display modes, host-context/theme, teardown). But tool dispatch resolves only against local R functions, R-side execution is synchronous, and the iframe is `srcdoc`-only. Remote/tunneled hosting requires Phase 3 work. Long-term home may be shinychat (#175 — our issue). |
| Resources protocol | `mcp-resources.R` | **Upstream to mcptools (#116).** Extractable at the design level; three internal helpers (`shinymcp_error_resource`, `coerce_resource_text`, `compact_list`) must travel with it. |
| Server transports | `serve.R` (stdio + HTTP JSON-RPC dispatch) | **Delegate to mcptools — but this is more than "duplicated dispatch."** See the delegation inventory below. Public `serve()` API stays stable. |

### The serve() delegation, honestly scoped

The bespoke server layer carries shinymcp behavior beyond transports. For
`serve()` to become a thin wrapper over mcptools without regressions, mcptools
needs (mapped to schloerke's filed issues where one exists):

| shinymcp behavior (today) | mcptools issue |
|---|---|
| `resources/list` / `resources/read` (`mcp-resources.R`) | #116 |
| `_meta.ui` on tools in `tools/list` (`mcp-app.R:333`) | #117 |
| `outputSchema` on tools (`mcp-app.R:307`) | #103 |
| `structuredContent` in tool results | #104 |
| Embeddable dispatch / streamable-HTTP session mgmt (`Mcp-Session-Id` lifecycle, `serve.R:160-294`) | #119 |
| Non-blocking stdio (`serve.R:70-114`) | #120 |
| Async tool handlers | #118 |
| **Per-session capability negotiation** — record client MCP Apps support at `initialize`, conditionally attach/withhold `_meta.ui` per session (`serve.R:398`, `utils.R:213`) | **not filed — we should raise it** |
| Protocol-version negotiation 2024-11-05 … 2025-11-25 (`utils.R:155`) | presumably in scope for mcptools core; verify |

The unfiled item is the important one: automatic graceful degradation is a
shinymcp strength the shiny team explicitly flagged for adoption, and it lives
in this layer. Raising it on #115 both protects the behavior through the
migration and contributes the design upstream.

### What we bring in from shiny

- **`registerMcpTool()` / ellmer alignment** — make the generator's emitted
  `ellmer::tool()` definitions drop-in registrable in a `mcpConfigure()`'d
  app, and accept the same objects at runtime, so authors can mix models.
- **Deployment discovery** — their deployment-record / Quarto-metadata URL
  logic, if/when shinymcp targets Connect and shinyapps.io.
- **Protocol conventions** — `_meta.ui.csp.*`, appId namespacing, and display
  handling, so apps from either stack behave identically in hosts (including
  ours). shinymcp already targets MCP Apps spec `2026-01-26` and core protocol
  through `2025-11-25`; keep tracking theirs.

### What we offer upstream

- `ResourceRegistry` + resource handlers → mcptools #116 (with the three
  helper functions inlined).
- Streamable-HTTP session management and dispatch experience → #119/#120.
- Per-session capability negotiation / graceful degradation → raise on #115;
  the three-faced `mcp_result_*()` design → shiny (their tools return "the app
  is now displayed" to non-Apps hosts today).
- Automatic input-state → `ui/update-model-context` reporting → shiny (theirs
  is opt-in via `mcpUpdateModelContext()`).
- Host implementation → shinychat #175, where we already made the case.

## Phases

**Phase 0 — Engage on the open threads (now; #4409 is still a draft).**
Comment on mcptools #115: shinymcp has working implementations for #116
(resources), #119 (HTTP session dispatch), and field experience on #104/#103;
raise the missing capability-negotiation item. Respond to
`mcp/comparison-shinymcp.md` on rstudio/shiny agreeing with the convergence
framing. Nudge shinychat #175 with an offer of the host implementation.
Exit: maintainers aligned on where each piece lands.

**Phase 1 — Upstream the plumbing.**
PR the resources module against mcptools #116 (inline the three helpers).
Contribute to or review the #117/#119/#120 work. Exit: mcptools release
covering at least #116/#117/#119.

**Phase 2 — Delegate, behind a stable API.**
Rebuild `serve()` on mcptools; delete `serve_stdio()`/`serve_http()` and the
bespoke dispatch. Gate: the delegation inventory above is covered upstream
(especially capability negotiation) — if an item lags, keep only that shim
locally and say so in NEWS. Move mcptools from Suggests toward a required
dependency for serving. Exit: no transport code in shinymcp; tests green
against the mcptools-backed server, including a text-only-client degradation
test.

**Phase 3 — Interoperate with shiny; make the host real for remote apps.**
Three workstreams, ordered by effort:

1. *Tool interop (small):* verify/adjust the generator's emitted
   `ellmer::tool()` defs against `registerMcpTool()` (shiny requires ellmer >=
   0.4.0); add a round-trip test loading a converted app's tools in a
   `mcpConfigure()`'d shiny app.
2. *Remote hosting (medium):* extend the host to fetch `ui://` resources and
   proxy `tools/call` to a remote MCP server — the JS side is already
   promise-based and has an unused `appSrc` hook (`host.js:575`); the R side
   needs an MCP client and async execution (promises/ExtendedTask —
   mcptools #118 and ellmer's client work are relevant).
3. *Tunnel hosting (stretch, gated on 2):* verify `mcp_embed()` against a
   shiny-tunneled app. **Known-impossible today**: tunnel tools
   (`_shiny_send`/`_shiny_receive`) would hit "Tool not found" in the local
   dispatcher, and a long-polled `_shiny_receive` would block the
   single-threaded R session. Requires remote proxying *and* async dispatch.

Exit: (1) round-trip test passes; (2) a first-party or third-party remote MCP
App renders inside a shinymcp host; (3) explicitly re-evaluated, not assumed.

**Phase 4 — Reposition the package surface.**
None of this has landed yet; today's docs are consistently convert-first and
must all move together:

- `DESCRIPTION` Title ("Convert Shiny Apps to MCP Apps") and Description →
  tools-first framing.
- README hero ("dashboard inside Claude Desktop", "Automatic conversion"
  section) → tools-first + hosting; conversion demoted to a migration section.
- `_pkgdown.yml` home text and reference grouping (Conversion Pipeline is
  currently a top-level group) → reorder around authoring, results, hosting.
- Vignettes: add "shinymcp vs. Shiny's built-in MCP support" mirroring and
  cross-linking their comparison doc; reframe `automatic-conversion.Rmd` /
  `converting-shiny-apps.Rmd` / `choose-the-right-migration-path.Rmd` to route
  dashboard-in-chat readers to shiny.

Exit: a user landing on either project's docs is routed correctly in under a
minute.

## What we explicitly stop doing

- Marketing conversion as the path to "your dashboard in chat."
- Building session-like or tunnel-like features; anything stateful belongs to
  shiny's model.
- Maintaining bespoke transports once mcptools covers the delegation
  inventory.

## Success and sunset metrics

Watch *what* users build, not download counts. Success: people authoring
tool-first apps and embedding MCP Apps in Shiny. Sunset trigger: usage is
dominated by dashboard conversion (that audience belongs upstream), or Posit
ships first-party stateless tools + hosting — in which case, upstream the
remainder and archive gracefully. If shinychat adopts the host code (#175),
that is success, not sunset: the host graduating upstream is the plan working.

## Open questions

- **Canonical tool format.** Today the runtime default is a bespoke plain
  list; `ellmer::ToolDef` is an optional Suggests-gated path, while the
  generator, shinychat integration, and shiny's `registerMcpTool()` are all
  ellmer-based. Promote ToolDef to the canonical format (ellmer to Imports)?
  Leaning yes at the next breaking-change window; it collapses the dual
  dispatch in `mcp-app.R` and makes interop free.
- **Where the host lands.** shinychat #175 is our issue and the natural
  destination. Decide after Phase 3 workstream 2 whether shinymcp keeps a
  host or becomes shinychat's dependency for it.
- **`mcpConfigure()` API stability.** Phase 3 targets an experimental surface
  (#4409 unmerged); track breaking changes rather than pinning.
- **mcptools timeline.** #115–#120 are days old with no maintainer response
  yet; Phase 2 timing depends on their roadmap (a 1.0.0 milestone, #112, is
  in flight).

## Appendix: corrections from the codebase review (July 2026)

Findings that changed this document from its first draft:

1. `generate.R` already emits `ellmer::tool()` source (typed arguments,
   `tool_annotations()`); the first draft claimed this as new work.
2. ellmer is optional (Suggests), and the default runtime tool format is a
   plain list — "both projects use ellmer" was overstated; hence the canonical
   tool format question.
3. `mcp-resources.R` is extractable but depends on three internal helpers
   that must move with it.
4. The serve() → mcptools delegation is materially larger than "duplicated
   dispatch": per-session capability negotiation, `_meta.ui`, `outputSchema`,
   protocol-version negotiation, and HTTP session management all live in that
   layer; one required capability (session-aware `_meta` withholding) has no
   filed mcptools issue yet.
5. The host cannot host remote or shiny-tunneled apps today: `srcdoc`-only
   embedding, local-function-only tool dispatch (`host-base.R:136`), and
   synchronous R execution. The JS layer is async-ready; the R layer is not.
6. Upstream: the mcptools shared core was already scoped by schloerke
   (#115–#120, July 13); shinychat #175 (our own issue, February) is the
   host's upstream path; shiny #4409 remains an unreviewed draft.
