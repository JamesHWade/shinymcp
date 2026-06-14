# Shiny components as building blocks for AI agents

This session is part of R/Pharma genAI Day on June 16, 2026.

Shiny is a proven way to build interactive data applications, but a Shiny app lives behind a URL. As AI assistants become a common place to explore and analyze data, that separation means users leave the conversation to use the app, then carry the results back by hand.

In this edition of the [R/Pharma](https://rinpharma.com) Hangout sessions, James Wade (Dow) demonstrates `{shinymcp}`, which converts Shiny apps into MCP-compatible interfaces that render inside chat-based tools. Plots, inputs, and summaries appear inline, respond to user input, and execute code within the conversation.

The session also covers two related packages built on [`{ellmer}`](https://ellmer.tidyverse.org/): `{dsprrr}`, which brings DSPy-style signatures, optimization, and tracing to R so prompts can be improved with data instead of hand-tuning, and `{deputy}`, an agent runtime for building tool-using AI agents with permissions, hooks, and multi-agent coordination. Together, these tools treat Shiny components as building blocks for agent-connected workflows rather than standalone dashboards.

## Goals of the Session

The session starts with shinymcp and a live demo, then widens out to the prompt and agent layers that sit on top of the same R functions. Along the way:

* Show how `{shinymcp}` turns a Shiny app into an MCP App: a named tool paired with an interactive UI card that renders inside chat clients through `ui://` resources, sandboxed iframes, and postMessage/JSON-RPC.
* Reach one R-backed tool three ways from a single `mcp_app()` definition: an MCP client, a Shiny host, and a shinychat result.
* Be honest about fit: bounded, named operations with serializable results belong here; open-ended exploration, high-frequency interaction, and tight latency loops do not.
* Introduce `{dsprrr}`: fit prompts to data with DSPy-style signatures, optimization, and tracing instead of hand-tuning.
* Introduce `{deputy}`: build tool-using agents with permissions, hooks, and multi-agent coordination, calling reviewed R functions as tools.

## Resources

* `{shinymcp}`: convert Shiny apps to MCP Apps <https://github.com/JamesHWade/shinymcp> and documentation <https://jameshwade.github.io/shinymcp/>
* `{dsprrr}`: declarative self-improving language programs for R <https://github.com/JamesHWade/dsprrr> and documentation <https://jameshwade.github.io/dsprrr/>
* `{deputy}`: agentic AI workflows for R <https://github.com/JamesHWade/deputy> and documentation <https://jameshwade.github.io/deputy/>
* `{ellmer}`: call LLMs from R <https://ellmer.tidyverse.org/>
* `{shinychat}`: chat UIs in Shiny <https://posit-dev.github.io/shinychat/>
* `{mcptools}`: Model Context Protocol for R <https://posit-dev.github.io/mcptools/>
* Model Context Protocol overview <https://modelcontextprotocol.io/>
* MCP Apps documentation <https://modelcontextprotocol.io/docs/extensions/apps>
* MCP Apps specification (stable, v2026-01-26) <https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/2026-01-26/apps.mdx>

## Example Application

The demo in this directory (`app.R`), the Oncology Signal Room, is a bslib dashboard with a shinychat study assistant, built over synthetic oncology trial data (n = 384). It offers two approved MCP skills, each one an MCP App: an interactive card paired with a typed tool contract.

* Safety Signal Scout screens a cohort and adverse-event lens and returns an aggregate safety read: a decision memo, an evidence table, an event-rate plot, and an audit block.
* Enrollment Rescue Simulator projects randomization under a monthly enrollment rate.

Each skill is defined once with `mcp_app()`, served to MCP clients with `serve()`, embedded in the Shiny host through `mcp_host_server()` and `mcp_host_ui()`, and surfaced inside shinychat as a tool result with `as_shinychat_tool()`. Tools are declared with `ellmer::tool()` and return a structured `model_value` the host or client can read without scraping the UI. Results stay aggregate and audit-friendly; no subject-level rows cross the contract. The dashboard is the local review and preview view, and the MCP contract is what an external client actually calls.

The data is synthetic. The study assistant is a scripted router for the demo: it surfaces the same shinymcp cards as shinychat tool results, with a branded welcome and clickable suggestion cards. It does not call a live LLM, so no API key is needed and the demo runs fully offline.

### Running the demo

```r
# install (experimental, from GitHub)
pak::pak("JamesHWade/shinymcp")

# run the demo
shiny::runApp(system.file("examples", "rpharma-hangout", package = "shinymcp"))
```

Requires shiny, bslib, htmltools, ellmer, shinychat, and shinymcp.

### What to look at

- The same R-backed tool reached three ways: an MCP client, the Shiny host, and
  shinychat, all from a single `mcp_app()` definition.
- The Contract inspector, showing the declared argument schema and the `ui://`
  card URI, so reviewers see what an external client calls.
- Each card has an inspectable tool contract rather than only a human UI,
  including a declared result schema (`tool_outputs` becomes `outputSchema`), so
  reviewers see what comes back before anything runs.
- The aggregate `model_value` handed back to the parent app, which reacts to it
  directly rather than reading the rendered page.
- Switching the approved skill, which swaps the UI, schema, outputs, and
  contract together.
- shinychat presents those cards as interactive tool results, with suggestions
  that help users discover what to ask.
- The shinychat page keeps review boundaries visible in the chat footer:
  aggregate tools only, visible arguments, and a clear auto-update vs Apply
  distinction. Cards can auto-update on input changes; the dashboard uses Apply
  because its embedded host is configured in submit mode.
- The loop runs both ways: model tool calls drive the card, and user card
  interactions land back in the model's context as typed data
  (`ui/update-model-context`), an interaction record you can log and review.
- MCP Apps support is negotiated per connection: clients without the apps
  extension get the identical tools text-only, so adopting the contract is
  low-risk.
- Tools can be scoped with `tool_visibility`: app-only tools stay callable
  from the card but never appear in the model's tool list.
- Hosts enforce deny-by-default networking (CSP) on cards; a card that
  declares no domains cannot phone home.
- Aggregate-return boundaries and audit text can be built into each clinical skill.

The `{dsprrr}` and `{deputy}` portions of the session use their own packages; see their documentation above.
