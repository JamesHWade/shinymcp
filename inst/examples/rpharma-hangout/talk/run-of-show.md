# Run-of-Show — "Bring Shiny Workflows to Claude"

**shinymcp at R/Pharma genAI Day · June 16 · 50 minutes (live)**

## At a glance

- **Audience:** R users in pharma/clinical research — statisticians, statistical programmers, data scientists, Shiny developers, and platform/governance people. They are validation-minded, practical, and skeptical of vendor lock-in.
- **Length:** 50 minutes including a ~10-minute live demo and meaningful Q&A.
- **Core message:** shinymcp lets reviewed R/Shiny tools become MCP Apps that Claude and other MCP clients can call. Shiny remains the local review path; deterministic R remains the computation layer. The MCP Apps spec is now stable (2026-01-26, co-maintained by Anthropic and OpenAI), and the loop runs both ways: the model's tool calls drive the card, and the user's card interactions land back in the model's context as typed data.
- **The one thing they should remember:** the client changes, but the R function and typed contract do not.
- **The second thing they should remember:** they can build one this week — the closing slide is a complete 25-line app.
- **Everything runs on synthetic data.** Say so early and often.

## Timing table (fills the 50-minute slot — the final close + Q&A block flexes to use the remaining time)

| Block | Start | Dur | Goal |
|---|---:|---:|---|
| 1. Claude, meet your R tools | 00:00 | 5 | Reframe from "chatbot in a dashboard" to "R tools exposed through MCP" |
| 2. Why MCP | 05:00 | 6 | Explain MCP clients, servers, tools, resources, and why pharma should care |
| 3. What MCP Apps add | 11:00 | 7 | Callable tool + UI + typed result, **and the model-context loop** |
| 4. Why shinymcp | 18:00 | 5 | Make the audience-specific value proposition explicit |
| 5. Claude and other clients | 23:00 | 6 | R-backed MCP server path, **negotiated capability / graceful degradation**, portability |
| 6. Code contract + Shiny integration | 29:00 | 8 | The R tool, `model_value`, **visibility + outputSchema scoping**, Shiny as review path |
| 7. **LIVE DEMO: Oncology Signal Room** | 37:00 | 9 | Verify client paths, declared result schema, typed handoff, app swap |
| 8. Review boundaries + scale + limits | 46:00 | 2 | Name the constraints before Q&A |
| 9. Close: build-one recipe + Q&A | 48:00 | 2+ | Leave them with the complete 25-line app, then questions |

> If you fall behind, cut the conversion-pipeline detail first, then compress the before/after and Why-shinymcp card grids. **Never cut:** MCP in one slide, "The loop closes" (model context), What Claude sees, "Negotiated, not bolted on", Code 3 (`model_value`), the live round trip, and the build-one closing recipe.

---

## Block-by-block cues

**1. Open (00:00-05:00).** Start with: *"Claude can call an R-backed Shiny workflow."* Say the point plainly: the R computation can stay in R while Claude or another MCP client calls it through a typed contract. Preview the talk structure: MCP → MCP Apps → why shinymcp → Claude/MCP clients → Shiny review path → validation boundaries. State "open source, experimental, not on CRAN, synthetic data" immediately.

**2. Why MCP (05:00-11:00).** Explain MCP as the standard connection between MCP-capable clients and external processes. Use pharma language: MCP exposes approved analytical tools through a reviewable protocol. Contrast protocol calls with screen reading. The client calls a named tool with typed arguments; the R server computes and returns structured data.

**3. What MCP Apps add (11:00-18:00).** A plain MCP tool is a callable function. An MCP App adds an interactive UI resource tied to the same tool. Show the app contract: schema, `ui://` resource, structured result. Then slow down on "The loop closes": the user adjusts the card and the model's next turn starts from those values via `ui/update-model-context` — typed context, not screenshots. This is the substance-beyond-window-dressing beat; if the audience takes one protocol detail home, make it this one. The interaction record is loggable data, which is a sentence governance people remember.

**4. Why shinymcp (17:00-23:00).** Speak to each group in the room. Stat programmers keep deterministic R. Shiny teams reuse familiar UI patterns. Data scientists get callable approved tools. Governance gets a smaller contract to review than a prompt plus screenshot behavior. Platform teams get an open-standard integration path.

**5. Claude and other clients (23:00-29:00).** Show `mcp_app()` + `serve(app)` and the Claude Desktop-style config. Then "Negotiated, not bolted on": the apps extension went stable in January 2026 with Anthropic and OpenAI co-maintaining it, clients opt in during `initialize`, and shinymcp checks — so a client without support still gets the same tools text-only. Frame it as risk asymmetry: the worst case of adopting this is a working MCP integration without the card. Then the multi-client diagram. Land: *"The client changes. The R function and contract do not."*

**6. Code contract + Shiny integration (29:00-37:00).** Move briskly through real code. Code 1: IDs map to arguments/outputs. Code 2: deterministic R tool body and schema. Code 3: `model_value` is the main contract. Code 4 is the governance-in-code slide — give it a full minute: `tool_visibility` keeps the row-level detail tool off the model's tool list entirely, `tool_outputs` declares the result shape (the contract covers what comes back, not just what goes in), and deny-by-default CSP means an undeclared card cannot phone home. Code 5: one definition, multiple homes. Then position Shiny as the local review path.

**7. Live demo (36:00-46:00).** Prime three checks: client paths, typed result, tool swap. Keep the right-hand Contract inspector visible. Do not spend time on dashboard features that do not support those checks.

**8. Reviewability + scale + limits (46:00-49:00).** Name the review points quickly: deterministic R, declared schemas, aggregate boundary, typed handoff, human decision. Say the sandbox caveat plainly: it is one layer, not the whole data-control story. On scale, `convert_app()` scaffolds; it does not validate arbitrary clinical logic.

**9. Close + Q&A (48:00+).** Put the build-one slide up and walk it: complete 25-line app, input id = argument name, result key = output id, `preview_app()` first (local reference host with a protocol log), then the Claude config. Say: *"If you can write a function and label two ids, you can ship one of these by Friday."* Leave the example ladder + `vignette("mcp-apps-protocol")` pointers on screen during Q&A.

---

## LIVE DEMO — Oncology Signal Room

Target **8-9 min** for the click-path, ~1 min for recap.

### Pre-flight checklist

- [ ] App running locally, pre-warmed with one throwaway Apply cycle.
- [ ] `renv.lock` restored on a backup machine with pinned versions.
- [ ] Browser console open to catch bridge/postMessage errors.
- [ ] Window sized so the Contract inspector / handoff panel is visible.
- [ ] Pre-recorded GIF of one Apply → handoff cycle and screenshot of a populated Contract inspector ready in a tab.
- [ ] Use values that yield a visible signal: Lung / Neutropenia / grade 3 / RR watch limit around 1.2 for the determinism beat.
- [ ] Be ready to say: *"The dashboard is the local preview. The contract is what Claude can call."*

### Click-path

1. **Defaults.** Cohort = All cohorts, AE lens = Neutropenia, skill = Safety Signal Scout. Point at the dashboard: *"This is the Shiny review view."* Say **synthetic**.
2. **Integration strip.** Scroll to the MCP widget bay and point at `mcp_host_server`, `as_shinychat_tool`, and the `ui://` URI. *"Same R-backed tool, multiple client paths."*
3. **Contract inspector.** Point right before touching the card: `screen_safety_signal`, `ui://` URI, argument schema, AND the declared-result table (memo / evidence / risk_plot / audit with types). *"This is what Claude can call — and what it is promised back. Both directions, declared before anything runs."*
4. **Inside Safety Signal Scout:** Cohort = Lung, AE term = Neutropenia, Min grade = 3, RR watch limit = 1.8 → press **Apply**. Read the memo, evidence table, event-rate plot, and audit block.
5. **The round trip.** Point right: Last widget handoff + Meeting-note handoff. *"The parent app did not scrape the screen. It received this typed object."*
6. **Determinism.** Lower RR watch limit to ~1.2 → **Apply** again. Decision changes through deterministic R logic; handoff recomputes with the same schema.
7. **Skill swap.** Sidebar: Approved MCP skill → Enrollment Rescue Simulator. Pause 1-2 seconds. Point out that UI, schema, outputs, and contract changed together. Set monthly_randomized = 20 → **Apply**. Restore defaults if time allows.

### Recap

Check off the new story:

- MCP made the R function callable from another client.
- MCP Apps associated that callable function with an interactive UI resource.
- shinymcp supplied the MCP App wrapper for R/Shiny.
- The contract declared both directions: input schema and result schema, visible before any call.
- The Shiny dashboard showed the same contract in a familiar review view.
- The review point was the typed, aggregate, deterministic contract.

### Demo fallback

Trigger is `"submit"` — if any panel reads "Waiting for Apply" or "Run a widget…", press **Apply**. If the iframe/postMessage handoff stalls or the bridge errors, cut to the GIF and populated Contract inspector screenshot. Narrate the same points: contract, typed object, deterministic R, no patient rows. If short on time, cut the Enrollment Rescue Simulator.

---

## If Q&A runs dry — seed questions

1. *"Does this actually run in Claude?"* — The MCP server path is the standard route: an Rscript can run `serve(app)` and Claude Desktop can connect to that local MCP server. Remote custom connectors are a separate deployment path. UI rendering is client-dependent; the tool contract is the stable part.
2. *"Why not just build a Claude-specific tool?"* — You can, but then you own a Claude-specific integration. MCP gives you a portable contract across clients as support matures.
3. *"Is the model ever computing the numbers?"* — No. The client selects the tool and fills declared arguments. The deterministic R function computes.
4. *"What about patient data?"* — shinymcp gives the contract; the tool author controls what crosses it. For clinical use, return aggregate evidence and audit metadata, not subject-level rows.
5. *"How would you validate this?"* — Unit-test the R tools, inspect the JS bridge, assert the tool schema, and assert `model_value` payloads. Treat the typed handoff as the testable contract.
6. *"What about the sandbox?"* — It is one layer. Do not sell it as the whole data-control story. The real boundary is the client/tool permission model plus what the R tool returns. One concrete positive: hosts enforce deny-by-default CSP, so a card that declares no domains cannot make any network request.
7. *"How does the model know what the user did in the card?"* — The bridge reports card state through `ui/update-model-context` as typed data. The model's next turn starts from the user's actual parameters; nothing is inferred from pixels, and the interaction record is loggable.
8. *"What if our client doesn't support MCP Apps?"* — Support is negotiated per connection. shinymcp checks the client's capability during `initialize`; clients without it get the identical tools text-only. The spec went stable in January 2026 with Anthropic and OpenAI co-maintaining it.
9. *"Can we keep some tools away from the model?"* — Yes: `tool_visibility = list(x = "app")` hides a tool from the model's list while the card can still call it. Useful for row-level detail views that should stay a human affordance.

## Top objections → one-line rebuttals

- **"This is just a Shiny demo."** → The dashboard is the preview; the MCP contract is what Claude can call.
- **"LLMs can't be validated."** → The model does not compute; deterministic R does.
- **"Vendor lock-in?"** → MCP is the portability layer; Claude is the example, not the endpoint.
- **"Will every client render the UI?"** → No. Tool calls are the stable part; UI rendering depends on client support.
- **"Is this production-ready?"** → No. It is experimental and useful for learning the contract, validation points, and migration path.

## Install / read / fork

- `pak::pak("JamesHWade/shinymcp")` (GitHub; experimental)
- Climb the example ladder: `hello-mcp` -> `penguins` -> `feature-tour` -> this demo (`vignette("use-cases")` is the guided tour)
- Read the protocol: `vignette("mcp-apps-protocol")` — spec version, compliance table, security model; this is the document to send reviewers
- Read the bridge: `inst/js/shinymcp-bridge.js` (vanilla ES5, dependency-free)
- Try a minimal Claude path: the closing build-one slide is complete and runs as-is
- Docs: <https://jameshwade.github.io/shinymcp>
