# shinymcp (development version)

## MCP Apps spec 2026-01-26 alignment

shinymcp now targets the stable MCP Apps specification (2026-01-26,
<https://github.com/modelcontextprotocol/ext-apps>):

* The server now checks the client's
  `capabilities.extensions["io.modelcontextprotocol/ui"]` extension
  capability during `initialize`. Clients that don't advertise MCP Apps
  support receive the same tools without `_meta.ui` annotations, so they
  degrade gracefully to text-only operation.
* Core protocol version negotiation now follows the MCP spec: the server
  echoes a supported requested version (2024-11-05 through 2025-11-25) and
  otherwise responds with its latest, instead of taking the string minimum.
* The JS bridge handshake (`ui/initialize`) uses apps protocol version
  `2026-01-26` and declares `availableDisplayModes`.
* `ui/update-model-context` is now sent with request semantics per the
  spec (previously a notification).
* The server and bridge both answer `ping`.

## New features

* `mcp_app()` gains `resources`: declare extra resources (static strings or
  lazily-evaluated functions) served alongside the app and readable from
  the UI via the new `window.shinymcp.readResource(uri)` — the spec's
  view-side `resources/read`. This enables lazy-loading large datasets
  instead of inlining them into the app HTML. Supported by real chat
  hosts, the bundled Shiny host, and `preview_app()`.
* `mcp_app()` gains `tool_outputs`: declare which output ids each tool
  returns and shinymcp generates a spec-compliant `outputSchema` per tool,
  with property descriptions derived from the matching UI output types.
  `convert_app()` scaffolds emit the suggested mapping (commented out
  until the placeholder tool bodies are completed).
* The HTTP transport now implements basic streamable-HTTP session
  management: an `Mcp-Session-Id` is assigned on `initialize`, per-client
  session state (protocol version, UI capability) is keyed by that header,
  and `DELETE` terminates a session. Previously concurrent HTTP clients
  shared one session and could clobber each other's capability
  negotiation.

* `mcp_app()` gains `csp`, `permissions`, and `prefers_border` arguments.
  These publish `_meta.ui` metadata (CSP domain declarations, iframe
  permissions, border hint) on the app's `ui://` resource in
  `resources/list` and `resources/read`, so hosts can allow declared
  external domains. Apps with fully inlined assets (the default) need none
  of this.
* `mcp_app()` gains `tool_visibility` to scope tools with
  `_meta.ui.visibility`: `"app"`-only tools are hidden from the model,
  `"model"`-only tools are hidden from the rendered UI. Plain-list tools
  can also carry `visibility` and `outputSchema` fields directly.
* `mcp_app()` gains `trigger` and `debounce_ms` so standalone apps (not
  just Shiny-hosted ones) can control when input changes call tools.
* The bridge now applies host context: the host's `theme` maps to
  `data-bs-theme` (bslib UIs and the built-in component CSS follow the
  chat client's light/dark mode automatically), `locale` sets the document
  language, and `styles.variables` become CSS custom properties. Context
  updates via `ui/notifications/host-context-changed` are merged and
  re-applied; shinymcp's Shiny host propagates its page theme live.
* New `window.shinymcp` JS API inside apps: `callTool()`,
  `updateModelContext()`, `openLink()`, `sendMessage()`,
  `requestDisplayMode()`, `log()`, and `getHostContext()`. The bundled
  Shiny host implements `ui/open-link` and maps
  `ui/request-display-mode` to its fullscreen toggle, notifying apps of
  display-mode changes.

## Bug fixes

* The bridge now handles JSON-RPC *error* responses: failed `tools/call`
  requests reject their Promise (and log to the console) instead of
  leaving the UI silently stuck. (Previously error responses were dropped
  and pending requests never settled.)

## Documentation

* New `vignette("mcp-apps-protocol")`: a message-level walkthrough of the
  protocol, a spec compliance table, documented deviations, and guidance
  on CSP, theming, and tool visibility.
* README gains "Where MCP Apps run" (host support and graceful
  degradation) and "External assets and CSP" sections.
* `vignette("debugging-shinymcp")` covers the most common failure modes:
  hosts without the apps extension, error responses, CSP blocks, and dark
  mode styling.
