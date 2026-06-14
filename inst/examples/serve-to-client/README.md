# serve-to-client

Every other example previews locally. This one shows the point of MCP: calling your
R tool from a real client. The server is `serve.R`, an ordinary `mcp_app()` ending in
`serve(app, type = "stdio")`. A client launches that script and talks to it over stdio.

Find the absolute path to `serve.R`:

```r
system.file("examples", "serve-to-client", "serve.R", package = "shinymcp")
```

You need `Rscript` on your `PATH` (check with `which Rscript`) and the `shinymcp` and
`ellmer` packages installed in the library that `Rscript` uses.

## Claude Desktop

1. Open **Settings → Developer → Edit Config** (or edit the file directly):
   - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - Windows: `%APPDATA%\Claude\claude_desktop_config.json`
2. Add the server (use the absolute path from above; on macOS an absolute `Rscript`
   path such as `/opt/homebrew/bin/Rscript` is more reliable than bare `Rscript`):

   ```json
   {
     "mcpServers": {
       "shinymcp-demo": {
         "command": "Rscript",
         "args": ["/ABSOLUTE/PATH/TO/serve-to-client/serve.R"]
       }
     }
   }
   ```

3. Quit and reopen Claude Desktop. The `greet` tool appears in the tools list; ask it to
   greet someone and the card renders inline.

## VS Code

1. Create `.vscode/mcp.json` in your workspace:

   ```json
   {
     "servers": {
       "shinymcp-demo": {
         "type": "stdio",
         "command": "Rscript",
         "args": ["/ABSOLUTE/PATH/TO/serve-to-client/serve.R"]
       }
     }
   }
   ```

2. Open the file and click **Start** on the server, or run **MCP: List Servers** from the
   Command Palette and start it there.
3. In Copilot Chat (Agent mode), the `greet` tool is now available.

## Troubleshooting

- Nothing appears: confirm `Rscript <path-to-serve.R>` runs without error in a terminal
  (it will wait on stdin, which is correct; press Ctrl-C to exit).
- "command not found": use the absolute path to `Rscript`.
- Tool errors: check the client's MCP logs for the server's stderr.
