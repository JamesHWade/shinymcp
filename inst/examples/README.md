# shinymcp examples

Each folder is a runnable app. Open one in the preview host:

```r
shinymcp::preview_app(system.file("examples", "hello", "app.R", package = "shinymcp"))
```

`preview_app()` shows the app the way a chat client does, next to what the
model receives from each call.

## Start here

| Example | What it shows |
|---|---|
| [`hello`](hello) | The smallest app built from a tool: one input, one tool, one output. |
| [`sample-size`](sample-size) | A tool first, with a UI on top. One result carries text for the model, structured data, and outputs for the app. |
| [`rewritten-dashboard`](rewritten-dashboard) | A Shiny app (`original-app.R`) rewritten as a tool, with its UI unchanged. |

## Connecting to clients

| Example | What it shows |
|---|---|
| [`local-clients`](local-clients) | Claude Desktop, Claude Code, and VS Code, over stdio. |
| [`posit-connect`](posit-connect) | One deployment on Posit Connect: a Shiny app for people, and an MCP App on the same UI for chat clients, with `mcp_endpoint(apps = )`. |

## Hosting apps in Shiny

| Example | What it shows |
|---|---|
| [`shinychat`](shinychat) | Apps in a shinychat conversation, with `mcp_chat_host()`: the model opens them, and what the person does in them reaches the model. |
| [`shiny-host`](shiny-host) | An app inside a Shiny app, with the context it gives the model shown alongside. |
| [`remote-host`](remote-host) | An app from another MCP server, such as one deployed on Posit Connect, in a Shiny app, with `mcp_client()`. |

## Larger examples

| Example | What it shows |
|---|---|
| [`ggplot-builder`](ggplot-builder) | A plot builder over ggplot2 4.0 features, built from one tool. |
| [`feature-tour`](feature-tour) | The page's JavaScript API: an app-only tool, a resource read on demand, messages to the chat, links, and full screen. |
| [`rpharma-hangout`](rpharma-hangout) | The R/Pharma 2026 demo: two apps reached from an MCP client, a Shiny host, and shinychat. |

## Serving a Shiny app as it is

These serve Shiny apps live with `as_mcp_app()`, which shinymcp will stop
doing once Shiny's own MCP support is released; see
`vignette("shiny-apps", package = "shinymcp")`.

| Example | What it shows |
|---|---|
| [`faithful`](faithful) | An unchanged Shiny app, served live. |
| [`fuel-economy`](fuel-economy) | A bslib dashboard. `bindMcp()` chooses what the model sees, `mcp_model_context()` tells it what the user did, `mcp_host_context()` follows the chat's theme, and the download button works. |
| [`shiny-packages`](shiny-packages) | A Shiny app built on shinyWidgets and DT, with a file upload. The model reads the table's rows and hears which ones the person selected. |
| [`shiny-module`](shiny-module) | A Shiny module served with `mcp_tool_module()`. |
