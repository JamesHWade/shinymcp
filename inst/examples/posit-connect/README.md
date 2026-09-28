# Deploying an MCP App to Posit Connect

`app.R` here is a Shiny app for people and an MCP App for chat clients, in
one deployment. The two share their UI and the function that draws the
plot; the MCP App runs a tool where the Shiny app runs a server function.
`mcp_endpoint(apps = )` serves the MCP App at `/mcp` next to the Shiny app.
The result is still a Shiny app, so anything that runs Shiny apps can host
it: Posit Connect, Shiny Server, shinyapps.io, or `shiny::runApp()` on your
own machine.

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

Connect tells the app who the user is: the Shiny app's server function
sees them as `session$user`, and the tool as `mcp_request()$user`.

## Processes

The MCP App keeps nothing between calls, so Connect can run it in as many
processes as it likes.
