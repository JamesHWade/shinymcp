# Deploying an MCP App to Posit Connect

`app.R` here is an ordinary Shiny app piped into `mcp_endpoint()`. The
result is still a Shiny app, so anything that runs Shiny apps can host it:
Posit Connect, Shiny Server, shinyapps.io, or `shiny::runApp()` on your own
machine.

## Try it locally

```r
shiny::runApp(system.file("examples", "posit-connect", package = "shinymcp"), port = 7000)
```

- <http://127.0.0.1:7000/> is the Shiny app, as a browser sees it.
- <http://127.0.0.1:7000/mcp> is the MCP endpoint.

Check the endpoint from a terminal:

```sh
curl -s http://127.0.0.1:7000/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
```

## Deploy

```r
rsconnect::deployApp(
  system.file("examples", "posit-connect", package = "shinymcp"),
  appName = "old-faithful-mcp"
)
```

Connect shows the content URL when the deploy finishes, for example
`https://connect.example.com/content/1a2b3c4d/`. The MCP endpoint is that
URL followed by `mcp`.

## Connect a client

Content that requires a login needs credentials on every request. Create a
Connect API key (your user menu, then **API Keys**) and send it as
`Authorization: Key <api-key>`.

Claude Code:

```sh
claude mcp add --transport http faithful \
  https://connect.example.com/content/1a2b3c4d/mcp \
  --header "Authorization: Key $CONNECT_API_KEY"
```

VS Code (`.vscode/mcp.json`):

```json
{
  "servers": {
    "faithful": {
      "type": "http",
      "url": "https://connect.example.com/content/1a2b3c4d/mcp",
      "headers": { "Authorization": "Key ${input:connect-api-key}" }
    }
  },
  "inputs": [
    { "id": "connect-api-key", "type": "promptString", "description": "Posit Connect API key", "password": true }
  ]
}
```

Inside the app, `session$user` is the Connect user the request came from,
and tool functions can read it with `mcp_request()$user`.

## Processes

Each open view of a live Shiny app keeps its session in the R process that
started it. If Connect runs the app in several processes, a request can
reach a process that doesn't have that session. shinymcp then starts a new
session from the inputs on the page, so the app keeps working, but anything
the server function held outside its inputs starts over. For apps that
keep such state, set **Max processes** to 1 in the content's runtime
settings.

Apps built from tools with `mcp_app()` keep no state between calls and can
run in as many processes as you like.
