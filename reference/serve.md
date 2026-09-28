# Serve MCP Apps to an MCP client

`serve()` starts an MCP server for an app and blocks until the client
disconnects (stdio) or you interrupt it (HTTP).

- `type = "stdio"`, the default, is for desktop clients such as Claude
  Desktop, VS Code, and Goose, which start the R process themselves and
  talk to it over standard input and output. Put `serve(app)` at the end
  of a script and register `Rscript /path/to/script.R` with the client.

- `type = "http"` runs a long-lived Streamable HTTP server at
  `http://host:port/mcp`, for clients that connect to a URL. To deploy
  to Posit Connect, use
  [`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md)
  instead.

The server speaks MCP protocol versions 2024-11-05 through 2025-11-25
(with an `initialize` handshake) and 2026-07-28 (stateless, no
handshake), and the MCP Apps extension (2026-01-26). Clients that don't
support MCP Apps still get every tool; they see text results instead of
the app.

## Usage

``` r
serve(
  app,
  type = c("stdio", "http"),
  port = 8080,
  host = "127.0.0.1",
  path = "/mcp",
  allowed_origins = NULL,
  allowed_hosts = NULL,
  ...
)
```

## Arguments

- app:

  An
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md), a
  list of apps to serve from one server, a Shiny app object, or a path
  to a directory containing an `app.R` (or `ui.R` and `server.R`). Shiny
  apps run live; see
  [`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md).

- type:

  `"stdio"` or `"http"`.

- port, host:

  Where the HTTP server listens. The default host only accepts
  connections from this machine; use `"0.0.0.0"` to listen on all
  interfaces, and put the server behind authentication.

- path:

  The HTTP endpoint path.

- allowed_origins:

  Browser origins, besides the server's own and loopback ones for a
  local server, allowed to call the HTTP endpoint, for example
  `"https://chat.example.com"`. Use `"*"` to allow any.

- allowed_hosts:

  For a server listening on this machine only, the host names it may be
  reached at besides `localhost` and IP addresses, such as the public
  name of a reverse proxy in front of it. Requests for any other host
  are refused, which protects a local server from web pages that point
  their own host name at it (DNS rebinding).

- ...:

  Unused; for future extensions.

## Value

Nothing; `serve()` runs until the connection closes.

## See also

Other serving:
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md),
[`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md),
[`shinymcp-options`](https://jameshwade.github.io/shinymcp/reference/shinymcp-options.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# app.R, registered with Claude Desktop as `Rscript /path/to/app.R`
library(shinymcp)
app <- mcp_app(ui, tools, name = "explorer")
serve(app)

# An existing Shiny app, served live
serve("path/to/shiny-app")

# Over HTTP
serve(app, type = "http", port = 8080)
} # }
```
