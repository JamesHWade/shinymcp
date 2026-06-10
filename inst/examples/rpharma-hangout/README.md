# R/Pharma Hangout Demo

Run with:

```r
shiny::runApp(system.file("examples", "rpharma-hangout", package = "shinymcp"))
```

This demo is designed for the June 16 R/Pharma genAI Day shinymcp session. It
shows a normal Shiny oncology dashboard with an approved MCP skill registry.
It also includes a shinychat study assistant with a branded welcome message,
clickable suggestion cards, and tool cards inside shinychat backed by the same
shinymcp apps shown in the dashboard.

The main teaching points are:

- A reviewed R/Shiny tool can become an MCP App that Claude and other MCP
  clients can call through a typed contract.
- A shinymcp card can be served to MCP clients, embedded in a Shiny host, and
  displayed in shinychat.
- shinychat can present those cards as interactive tool results, with suggestions that
  help users discover what to ask.
- The shinychat page keeps review boundaries visible in the chat footer: aggregate
  tools only, visible arguments, and a clear auto-update vs Apply distinction.
- Cards in shinychat can auto-update on input changes; the dashboard uses Apply
  because its embedded host is configured in submit mode.
- Each card has an inspectable tool contract rather than only a human UI —
  including a declared result schema (`tool_outputs` → `outputSchema`), so
  reviewers see what comes back before anything runs.
- Tool results include human-facing plots/tables and structured model handoff.
- The parent Shiny app can react to the widget output without scraping the UI.
- The loop runs both ways: model tool calls drive the card, and user card
  interactions land back in the model's context as typed data
  (`ui/update-model-context`) — an interaction record you can log and review.
- MCP Apps support is negotiated per connection: clients without the apps
  extension get the identical tools text-only, so adopting the contract is
  low-risk.
- Tools can be scoped with `tool_visibility`: app-only tools stay callable
  from the card but never appear in the model's tool list.
- Hosts enforce deny-by-default networking (CSP) on cards; a card that
  declares no domains cannot phone home.
- Aggregate-return boundaries and audit text can be built into each clinical skill.
