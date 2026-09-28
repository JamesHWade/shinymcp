# Using MCP Apps from desktop clients

`serve.R` serves two apps over stdio, each built from one tool: a histogram
of Old Faithful waiting times and a dataset summary. A client starts the
script and talks to it on stdin and stdout.

Find the script's full path:

```r
system.file("examples", "local-clients", "serve.R", package = "shinymcp")
```

`Rscript` must be on the client's `PATH`, and shinymcp, shiny and ellmer
must be installed in the library `Rscript` uses. On macOS, desktop apps
don't see your shell's `PATH`; use the full path to `Rscript` (run
`which Rscript` to find it).

## Claude Desktop

Open **Settings → Developer → Edit Config** and add:

```json
{
  "mcpServers": {
    "shinymcp-examples": {
      "command": "/usr/local/bin/Rscript",
      "args": ["/full/path/to/local-clients/serve.R"]
    }
  }
}
```

Restart Claude Desktop, then ask for "a histogram of Old Faithful waiting
times with 30 bins". The app appears in the conversation.

## Claude Code

```sh
claude mcp add shinymcp-examples -- Rscript /full/path/to/local-clients/serve.R
```

Claude Code runs in a terminal and doesn't show apps, so the tools answer
with text. The same server works in both places.

## VS Code

Add `.vscode/mcp.json` to your workspace:

```json
{
  "servers": {
    "shinymcp-examples": {
      "type": "stdio",
      "command": "Rscript",
      "args": ["/full/path/to/local-clients/serve.R"]
    }
  }
}
```

Start the server from the file's code lens (or **MCP: List Servers**) and
use the tools from Copilot Chat in agent mode.

## When nothing shows up

- Run `Rscript /full/path/to/local-clients/serve.R` in a terminal. It
  should sit waiting for input; press Ctrl+C to stop it. An error here is
  the error the client hits.
- Check the client's MCP log. Claude Desktop keeps one per server; on
  macOS, in `~/Library/Logs/Claude/`.
- `preview_app()` shows the protocol messages and what the model receives,
  which is usually quicker than debugging inside a client.
