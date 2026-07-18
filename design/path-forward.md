# Path forward: shinymcp alongside Shiny's first-party MCP Apps support

> - **Status:** Proposed strategy
> - **Owner / decision-maker:** shinymcp maintainer
>   [@JamesHWade](https://github.com/JamesHWade)
> - **Execution system:** `bd`; create one epic with Track A/B/C child issues
>   when this strategy is accepted
> - **Last verified:** 2026-07-18
> - **Code baseline:**
>   [shinymcp `2221af7`](https://github.com/JamesHWade/shinymcp/commit/2221af7ce363f6eb39feafe8428a293fa7b9ad0d);
>   [Shiny `mcp` branch `c394d5b`](https://github.com/rstudio/shiny/commit/c394d5b8bc46229938dbae1dcfca0ad45c5d3d71)
> - **Review trigger:** 2026-08-15, or when
>   [rstudio/shiny#4409](https://github.com/rstudio/shiny/pull/4409)
>   changes state

## Decision summary

1. **Make one product promise.** shinymcp is the tool-first, sessionless way
   to expose an R capability as an ordinary MCP tool and, in Apps-capable
   clients, as an interactive card. It does not run a Shiny session per
   viewer.
2. **Route unchanged Shiny apps to Shiny.** Shiny's first-party path owns the
   zero-rewrite, fully reactive "put this existing app in chat" job.
   `convert_app()` remains useful when the desired result is intentionally
   tool-first, sessionless, model-callable, or useful in text-only clients.
3. **Converge protocol plumbing conditionally.** mcptools is the preferred
   long-term home for generic MCP server behavior, but shinymcp does not delete
   its server until a released mcptools backend passes the same contract suite
   and has a rollback path.
4. **Keep hosting secondary and trusted-local for now.** The current Shiny host
   is a supported integration for locally constructed `McpApp` objects and a
   useful upstream seed. Hosting arbitrary remote MCP Apps is a separate,
   security-gated product decision, not an assumed next feature.
5. **Sunset components, not the package by slogan.** Upstream a component when
   a maintained replacement passes its contracts. Archive shinymcp only if
   maintained replacements cover its tool-first authoring model, meaningful
   non-Apps fallback, UI bridge, and conversion scaffolding.

## Upstream baseline

As of 2026-07-18, the Shiny team has assembled experimental MCP Apps support
on its `mcp` integration branch. The feature PRs
([#4407](https://github.com/rstudio/shiny/pull/4407),
[#4412](https://github.com/rstudio/shiny/pull/4412),
[#4414](https://github.com/rstudio/shiny/pull/4414), and
[#4418](https://github.com/rstudio/shiny/pull/4418)) are merged into that
branch, while [#4409](https://github.com/rstudio/shiny/pull/4409), which
promotes `mcp` to `main`, remains a draft. The feature is therefore not yet on
Shiny's main branch or in a release.

Shiny apps opt in with `mcpConfigure()`. Once enabled, the full Shiny runtime
stays server-side. The iframe attempts a direct WebSocket when CSP and
reachability allow it; otherwise WebSocket traffic falls back to the
`_shiny_*` tool tunnel. HTTP side channels remain tunneled through
`_shiny_http` in either mode. `registerMcpTool()` accepts `ellmer::ToolDef`
objects. When `mcpConfigure(arguments = ...)` is declared, the generated
`update_<appId>_app` tool can steer a running MCP-backed Shiny session by
token. The durable distinction is therefore not "the model can drive only
shinymcp"; it is shinymcp's request/response, text-capable tool contract versus
Shiny's live per-viewer reactive session.

Shiny's
[`comparison-shinymcp.md`](https://github.com/rstudio/shiny/blob/c394d5b8bc46229938dbae1dcfca0ad45c5d3d71/mcp/comparison-shinymcp.md)
gets that product split right: these are "legitimately different products,"
and the overlap is "undifferentiated protocol plumbing." Treat the document as
framing, not current API documentation; it predates the latest integration
work.

Barret Schloerke translated server convergence into concrete mcptools
proposals:
[#115](https://github.com/posit-dev/mcptools/issues/115) tracks
[#116](https://github.com/posit-dev/mcptools/issues/116) (resources),
[#117](https://github.com/posit-dev/mcptools/issues/117) (tool `_meta`),
[#118](https://github.com/posit-dev/mcptools/issues/118) (async handlers),
[#119](https://github.com/posit-dev/mcptools/issues/119) (embeddable
dispatch), and [#120](https://github.com/posit-dev/mcptools/issues/120)
(non-blocking stdio). These are useful proposals, but they are still open,
unassigned, and without an accepted implementation sequence. Shiny's
[`QUESTIONS.md`](https://github.com/rstudio/shiny/blob/c394d5b8bc46229938dbae1dcfca0ad45c5d3d71/mcp/QUESTIONS.md)
records that the issues were filed; it does not establish a mcptools roadmap.

mcptools 1.0.0
[shipped](https://github.com/posit-dev/mcptools/releases/tag/v1.0.0) before
the
[#115-#120 proposal set](https://github.com/posit-dev/mcptools/issues/115)
was filed. Convergence therefore depends on a post-1.0.0 release, not the
still-open
[#112 release checklist](https://github.com/posit-dev/mcptools/issues/112).

We also opened
[posit-dev/shinychat#175](https://github.com/posit-dev/shinychat/issues/175)
for hosting MCP Apps inside shinychat. It is a candidate upstream venue, not
an agreed destination: there is no maintainer commitment or linked PR.

## Route users by the job

| User need | Recommended route |
|---|---|
| Render an existing, stateful Shiny app with full reactivity and minimal changes | Shiny's `mcpConfigure()` path once available in a supported Shiny release |
| Expose a typed R function that remains useful in text-only clients and gains a UI in Apps hosts | Author an `mcp_app()` with shinymcp |
| Transform an existing app into a sessionless, model-callable capability | Use `convert_app()` as a scaffold, then review and finish the generated tools |
| Embed a locally authored, trusted `McpApp` in Shiny or shinychat | Use `mcp_host_ui()` / `mcp_host_server()` / `mcp_embed()` |
| Render an arbitrary remote MCP App inside Shiny | Not supported today; follow the host discovery workstream below |

This routing preserves conversion's real value without marketing it as the
default way to place an unchanged dashboard in chat.

## Product boundary

### Core promise

shinymcp lets an R author define an explicit tool contract once:

- supported typed and named result contracts provide meaningful text and,
  where supported, structured or image content;
- an MCP Apps host can render a card over the same tool;
- inputs and results cross a request/response boundary rather than depending
  on a continuously live Shiny reactive session.

"Sessionless" is deliberate. Tool handlers may capture process-local state or
use durable storage, and the HTTP server keeps protocol session metadata.
shinymcp does not promise pure or stateless functions; it promises no
per-viewer Shiny runtime and an explicit tool interface.

### Non-goals

- Reproduce Shiny's live-session tunnel or compete on zero-rewrite app
  fidelity.
- Claim production remote deployment from the current HTTP server, which
  binds to loopback and has no deployment, authentication, or TLS layer.
- Load third-party HTML in the current trusted-local Shiny iframe.
- Keep a bespoke MCP stdio/HTTP server after a released shared backend has
  demonstrated parity and a safe migration.

## Component disposition

| Area | Decision | Next proof |
|---|---|---|
| Authoring components and bindings (`components-*.R`, `bind-mcp.R`, `mcp-tool-module.R`) | **Keep as core.** They express the tool-first UI contract. | External authored-app examples and stable input/output contract tests. |
| Typed results (`results.R`) | **Keep and tighten.** `shinymcp_result` carries display `value`, `model_value`, and text fallback, but standard MCP serving currently uses display value plus text while the full three-representation path is used by shinychat. It is a candidate implementation of the graceful degradation Shiny highlighted, not yet a shared ecosystem contract. | Define and test the result semantics across native MCP, mcptools, and shinychat before proposing an upstream abstraction. |
| Convert pipeline (`parse.R`, `detect.R`, `analyze.R`, `generate.R`, `convert.R`) | **Keep, reframe.** It is migration and scaffolding for an intentional tool-first rewrite, not the headline route for existing dashboards. | Generated output passes the same interop fixture as hand-authored tools; docs state where human review remains required. |
| Runtime and tool formats (`mcp-app.R`, `as-mcp-app.R`) | **Keep with an adapter boundary.** There is no canonical format today: the runtime accepts both `ellmer::ToolDef` and plain-list tools. Do not make a third-party S7 class the internal representation without evidence. | Normalize both formats into one internal contract and compare rich schemas, annotations, calls, and results. |
| Iframe bridge (`js-bridge.R`, `inst/js/shinymcp-bridge.js`) | **Keep.** It is the client for the sessionless model and is not redundant with Shiny's live-runtime bridge. | Track the stable MCP Apps spec and run host conformance tests. |
| Trusted local host (`host-base.R`, `host-shiny.R`, `preview.R`, `inst/js/shinymcp-host.js`) | **Keep as a secondary integration.** It implements a substantial protocol subset for local `McpApp` objects, not a general remote host. | Document the supported subset and close lifecycle gaps such as timeouts, cancellation, and pending-request rejection on disposal. |
| General remote host | **Discovery only.** The current implementation is not a hardened boundary for third-party HTML. | Threat model, ownership decision, raw MCP client API, and an end-to-end security design before implementation. |
| Resources (`mcp-resources.R`) | **Contribute behavior and tests upstream.** `ResourceRegistry` is useful reference code, but [mcptools#116](https://github.com/posit-dev/mcptools/issues/116) proposes a different `mcp_resource()` shape. Do not assume a class transplant. | Agree on the upstream API, then contribute generic conformance tests and implementation pieces, including required helper behavior. |
| MCP stdio/HTTP server (`serve.R`) | **Converge reversibly.** Preserve `serve()` while introducing a backend seam and differential tests. | A released mcptools backend passes the complete contract suite before becoming the default. |

## Server convergence: what is actually required

The original plan mixed current behavior that must survive delegation with
future capabilities needed only for embedding or remote hosting. They have
different gates.

| Capability | shinymcp today | mcptools status | Roadmap role |
|---|---|---|---|
| Core protocol-version negotiation through `2025-11-25` | Implemented | Implemented in 1.0.0 | Covered; verify identical behavior in contract tests |
| `resources/list` / `resources/read`, including resource `_meta` | Implemented | [#116](https://github.com/posit-dev/mcptools/issues/116) open | Delegation blocker |
| Tool `_meta.ui`, visibility, and legacy compatibility | Metadata implemented; server and local-host enforcement have known edge cases | [#117](https://github.com/posit-dev/mcptools/issues/117) open | Delegation blocker |
| `outputSchema` | Implemented for declared outputs | [#103](https://github.com/posit-dev/mcptools/issues/103) open | Delegation blocker |
| `structuredContent` and typed image/text fallback | Implemented | Base `structuredContent` exists in 1.0.0; [#104](https://github.com/posit-dev/mcptools/issues/104) remains open | Parity test; clarify remaining upstream gap |
| Access to `capabilities.extensions["io.modelcontextprotocol/ui"]` when producing `tools/list` | Stored per shinymcp session | No filed mcptools issue | Delegation blocker; raise explicitly |
| HTTP server-session context for capability isolation | Basic POST/DELETE `Mcp-Session-Id` subset implemented | No filed server issue; [mcptools#119](https://github.com/posit-dev/mcptools/issues/119) does not cover it | Design requirement; exact mechanism may differ |
| Embeddable JSON-RPC dispatch | Internal dispatcher exists | [#119](https://github.com/posit-dev/mcptools/issues/119) open | Useful convergence enabler, not proof of HTTP-session parity |
| Async tool handlers | Not implemented | [#118](https://github.com/posit-dev/mcptools/issues/118) open | Future remote/tunnel host requirement, not current `serve()` parity |
| Non-blocking stdio | Not implemented; `serve_stdio()` blocks on `readLines()` | [#120](https://github.com/posit-dev/mcptools/issues/120) open | Framework-embedding requirement, not current standalone `serve()` parity |

The
[MCP Apps 2026-01-26 specification](https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/2026-01-26/apps.mdx#clientserver-capability-negotiation)
requires the Apps extension to be negotiated. That makes client-capability
access a real server abstraction, not a shinymcp convenience.

The parity suite must cover more than successful requests:

- Apps-capable and text-only clients, including app-only and model-only tool
  visibility enforcement;
- nested `_meta.ui`, the deprecated flat resource key, CSP, permissions, and
  extra resources;
- input and output schemas, annotations, structured content, typed images,
  meaningful text fallback, and error mapping;
- stdio and HTTP behavior, protocol versions, session isolation, session
  termination and eviction policy, notifications, and teardown;
- the current compatibility policy for clients that skip `initialize`.

There are visibility correctness issues to fix regardless of backend: the
current non-Apps `tools/list` path can expose app-only tools after stripping
nested visibility metadata, while the bundled local bridge and host can call
model-only tools. The contract suite must specify and test both directions
before the package claims complete graceful degradation.

## Workstreams

These tracks run in parallel. Product work must not wait for upstream
maintainers, and upstream uncertainty must not force remote-host scope.

### Track A — Positioning and tool interoperability

Start now.

1. Update the conversion-led metadata and routing:
   - `DESCRIPTION`, `index.md`, and the README hero;
   - `_pkgdown.yml` copy and grouping where needed;
   - conversion and migration vignettes, plus a "shinymcp or Shiny?" guide;
   - package/function documentation, `CLAUDE.md`, and the shipped conversion
     skill.
2. Keep the existing authored-tool-first quick start and make conversion a
   clearly labeled migration path. Do not describe all current docs as
   conversion-first; their information architecture is mixed.
3. Build one pinned interop fixture that:
   - creates an `ellmer::ToolDef` with primitive and rich argument schemas;
   - serves it through shinymcp;
   - registers the same object with Shiny's `registerMcpTool()`;
   - compares `tools/list`, annotations, calls, structured results, and text
     fallback.
4. Fix or explicitly gate the known ToolDef gaps before calling it canonical:
   - `mcp_tools()` adds UI metadata only to plain-list tools;
   - the generated `server.R` uses list-style `tool$fun` access even though
     generated tools are S7 ToolDefs;
   - shinymcp's manual ToolDef-to-schema conversion loses richer ellmer schema
     details.
5. Short-term dependency policy:
   - keep accepting both ToolDef and plain-list inputs;
   - make ToolDef the preferred public authoring format where ellmer is
     available;
   - set the optional interop floor to ellmer >= 0.4.0;
   - move ellmer to `Imports` only when a public default path requires it
     unconditionally, not merely because Shiny accepts ToolDefs.

**Exit:** users can choose the right product from the docs in under a minute,
and the same representative ToolDef has evidence-backed behavior in both
runtimes. Until
[rstudio/shiny#4409](https://github.com/rstudio/shiny/pull/4409) reaches
`main`, the Shiny side is an opt-in, commit-pinned integration test rather
than a stable CI dependency.

### Track B — mcptools convergence

Engage upstream without making local progress contingent on a response.

1. Comment on
   [mcptools#115](https://github.com/posit-dev/mcptools/issues/115) with:
   - the parity matrix above;
   - the missing client-extension and server-session requirements;
   - an offer of resource and differential conformance tests.
2. Ask whether the proposed resource API in
   [mcptools#116](https://github.com/posit-dev/mcptools/issues/116) is accepted
   before opening an implementation PR. Adapt shinymcp's behavior to that API
   rather than upstreaming package-specific classes wholesale.
3. Introduce an internal server-backend boundary while keeping `serve()` stable.
4. Add mcptools as an opt-in backend and run native and mcptools backends
   through the same contract suite.
5. Make mcptools the default only after a released version passes parity.
   Retain the native backend for one documented deprecation/rollback interval.
6. Remove the bespoke MCP stdio/basic MCP-over-HTTP server only after the
   default has survived that interval. Preview and Shiny-host transports remain
   because they solve different jobs.

**Fallback:** if upstream has not accepted the required abstractions by the
review date, keep the native backend, continue protocol conformance fixes, and
revisit. Lack of upstream movement is not a blocker for shinymcp users.

**Exit:** the public `serve()` contract is unchanged, a released shared backend
passes the parity suite, and rollback has been exercised before native server
removal.

### Track C — host ownership and remote-host discovery

Keep the existing trusted-local host useful while deciding whether a general
host belongs here at all.

1. Update
   [shinychat#175](https://github.com/posit-dev/shinychat/issues/175) with a
   runnable local-host demonstration and ask explicitly whether shinychat
   maintainers want to own remote MCP App hosting.
2. Document the current supported subset and limitations. The host handles
   initialization, tool/resource calls, context and theme updates, display
   changes, resize, ping, disposal, and teardown requests, but it does not
   implement every MCP Apps method and advertises empty host capabilities.
3. Before any third-party remote HTML is loaded, write and review a threat
   model covering:
   - origin isolation and the current
     `sandbox="allow-scripts allow-same-origin"` trusted-content assumption;
   - CSP and permission enforcement, navigation/open-link policy, and resource
     limits;
   - credentials, OAuth, secret isolation, tool allowlists, and per-user MCP
     sessions;
   - timeouts, cancellation, teardown, and rejection of pending requests.
4. Define the missing raw MCP client surface. mcptools' public client currently
   converts `tools/list` into ellmer tools and does not expose the raw
   `_meta.ui` or a `resources/read` client API. A host needs raw tool metadata,
   resource reads, generic calls, session lifecycle, and cancellation.
5. Produce an architecture decision record choosing one of:
   - contribute the general host to shinychat;
   - implement a hardened host in shinymcp with a named maintainer and
     demonstrated demand;
   - keep trusted-local embedding only and defer remote support.

Only after that decision should Shiny-tunneled hosting be reconsidered. It
requires the remote proxy plus genuinely async `_shiny_receive`; it is not a
committed stretch goal and should not pull shinymcp into building a second
live-session architecture.

**Exit:** an ownership and security decision, not necessarily code.

## Immediate upstream engagement

The first external actions are small and evidence-led:

1. Comment on [rstudio/shiny#4409](https://github.com/rstudio/shiny/pull/4409)
   agreeing with the complementary-product framing, correcting any stale
   comparison points, and offering the interop fixture.
2. Ask on [posit-dev/mcptools#115](https://github.com/posit-dev/mcptools/issues/115)
   whether the resource/dispatch split is accepted and raise capability plus
   server-session context.
3. Update [posit-dev/shinychat#175](https://github.com/posit-dev/shinychat/issues/175)
   with the local implementation, its trust boundary, and an explicit ownership
   question.

Exit when the comments are posted and the response—or lack of response—is
recorded at the review date. "Maintainers aligned" is not a controllable
milestone.

## Evidence, review, and sunset

At each review, record linked examples or a zero count for:

- external repositories or known applications that author `mcp_app()` directly;
- tools used from both Apps-capable and text-only clients;
- converted apps still maintained after their initial scaffold;
- independent trusted-local host adopters and remote-host requests;
- contract-suite failures and protocol-maintenance changes by backend.

Use that evidence for explicit continue/freeze decisions:

- remote-host implementation remains frozen without an approved threat model,
  a named long-term owner, and two independent prospective adopters with
  concrete use cases;
- conversion remains supported but receives new feature investment only when
  at least one maintained converted app is observed across two consecutive
  reviews;
- native-server removal remains governed by released-backend parity and the
  rollback interval, not adoption counts.

Apply sunset decisions per component:

- remove the native server only after released-backend parity, migration
  documentation, and a rollback interval;
- graduate host code upstream when a maintained upstream accepts ownership;
- deprecate conversion only if its tool-first migration job has a maintained
  replacement and no demonstrated users;
- archive the package only when all differentiated contracts have maintained
  homes.

At each review date, record upstream state, evidence from users, contract-suite
status, and the next reversible decision. Avoid letting transient issue status
or hard-coded source line numbers become permanent strategy.
