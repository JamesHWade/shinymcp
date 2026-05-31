# R/Pharma Hangout Demo

Run with:

```r
shiny::runApp(system.file("examples", "rpharma-hangout", package = "shinymcp"))
```

This demo is designed for the June 16 R/Pharma genAI Day shinymcp session. It
shows a normal Shiny oncology dashboard with an approved MCP skill registry.

The main teaching points are:

- A shinymcp card is portable across a Shiny host, shinychat, and MCP hosts.
- Each card has an inspectable tool contract rather than only a human UI.
- Tool results include human-facing plots/tables and structured model handoff.
- The parent Shiny app can react to the widget output without scraping the UI.
- Aggregate guardrails and audit text can be built into each clinical skill.
