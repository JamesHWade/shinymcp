# shinymcp examples

An ordered tour. Each rung adds one idea on top of the last. The narrated version,
with code and explanation, is the [shinymcp by example](https://jameshwade.github.io/shinymcp/articles/shinymcp-by-example.html) article.

Preview an MCP App locally:

```r
shinymcp::preview_app(system.file("examples", "penguins", package = "shinymcp"))
```

| # | Example | What it adds |
|---|---------|--------------|
| 1 | [`hello-mcp-minimal`](hello-mcp-minimal) | One input, one tool, one output — the smallest MCP App |
| 2 | [`hello-mcp`](hello-mcp) | Rich outputs (a plot and text) and a bslib theme |
| 3 | [`penguins`](penguins) | Native bslib/shiny inputs, auto-detected by arg-name == element id |
| 4 | [`bslib-inputs`](bslib-inputs) | The auto-detection rules, plus `mcp_input()`/`mcp_output()` escape hatches |
| 5 | [`bind-mcp-demo`](bind-mcp-demo) | `bindMcp()`: expose only chosen parts of an existing app; some inputs stay private |
| 6 | [`multi-tool`](multi-tool) | Several tools and chained reactives in one app |
| 7 | [`module-tool`](module-tool) | `mcp_tool_module()`: reuse a Shiny module as a tool |
| 8 | [`converted-dashboard`](converted-dashboard) | Output of `convert_app()` — a plain Shiny app turned into an MCP App |
| 9 | [`serve-to-client`](serve-to-client) | Reach a real MCP client (Claude Desktop, then VS Code) over stdio |
| 10 | [`shinychat-card`](shinychat-card) | Surface a card as a shinychat tool result with `as_shinychat_tool()` |
| 11 | [`embed-in-shiny`](embed-in-shiny) | `mcp_host_server()`/`mcp_host_ui()`: Shiny as the review surface |
| 12 | [`data-explorer`](data-explorer) | Build inputs programmatically from a data frame |
| 13 | [`rpharma-hangout`](rpharma-hangout) | Capstone: multi-skill clinical app, contract inspector, `model_value` handoff |

For tuning the prompts behind these tools, see [`{dsprrr}`](https://jameshwade.github.io/dsprrr/);
for letting an agent call them, see [`{deputy}`](https://jameshwade.github.io/deputy/).
