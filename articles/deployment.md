# Running an app

An MCP App is served by an MCP server. A chat client connects to it in
one of two ways: it starts the server itself and talks to it over
standard input and output (stdio), or it connects to a URL (Streamable
HTTP). shinymcp serves apps both ways, and inside a Shiny app for Posit
Connect.

Every way below works with an
[`McpApp`](https://jameshwade.github.io/shinymcp/reference/McpApp.md), a
list of apps to serve from one server, or a path to a file or directory
whose `app.R` makes one.

## While you work: `preview_app()`

``` r

preview_app(app)
```

[`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md)
serves the app over HTTP on your machine and opens a page that plays the
part of a chat client: it calls the app’s tool the way a model would,
shows the app in a sandboxed frame under the same Content Security
Policy clients use, and lists what the model received, each tool call,
and the protocol messages. Change the arguments and call again, or
switch the theme and width to see the app in a dark or narrow chat.

[`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md)
returns right away. Call `$stop()` on its result when you’re done.

## Desktop clients, over stdio

Claude Desktop, Claude Code, VS Code, Goose, and most other desktop
clients start an MCP server as a program. Write the app in a script that
ends with
[`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md):

``` r

# ~/apps/mileage/app.R
library(shiny)
library(shinymcp)

show_mileage <- ellmer::tool(...)

app <- mcp_app(fluidPage(...), tools = list(show_mileage), name = "mileage")
serve(app)
```

Run it in a terminal first: `Rscript ~/apps/mileage/app.R` should sit
waiting for input (Ctrl+C stops it). An error there is the error the
client would hit, without the client’s log in the way.

The protocol runs over standard output, so the script must not print to
it before
[`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md)
starts; messages and warnings go to standard error, which is fine. While
a request is being handled, anything the app prints is sent to standard
error, where clients keep it in their logs.

Then register the script with the client, using full paths. On macOS,
desktop apps don’t see your shell’s `PATH`, so give the full path to
`Rscript` too (`which Rscript` prints it).

**Claude Desktop**, under Settings \> Developer \> Edit Config:

``` json
{
  "mcpServers": {
    "mileage": {
      "command": "/usr/local/bin/Rscript",
      "args": ["/Users/you/apps/mileage/app.R"]
    }
  }
}
```

**Claude Code**:

``` sh
claude mcp add mileage -- Rscript /Users/you/apps/mileage/app.R
```

**VS Code**, in `.vscode/mcp.json`:

``` json
{
  "servers": {
    "mileage": {
      "type": "stdio",
      "command": "Rscript",
      "args": ["/Users/you/apps/mileage/app.R"]
    }
  }
}
```

Clients that can’t show apps (Claude Code, which runs in a terminal, is
one) still get every tool the model can call, and their results as text.

## Over HTTP

``` r

serve(app, type = "http", port = 8080)
```

This serves the app at `http://127.0.0.1:8080/mcp`, reachable from this
machine only. To accept connections from elsewhere, listen on all
interfaces with `host = "0.0.0.0"` and put the server behind a proxy
that handles TLS and authentication; shinymcp does neither.

A server listening on this machine refuses requests for host names other
than `localhost` and IP addresses. That protects it from web pages that
point their own domain at your machine (DNS rebinding). If you reach it
through another name, such as a proxy on the same machine, list the name
in `allowed_hosts`. Browser pages from origins other than the server’s
own need `allowed_origins`.

The server speaks both generations of the MCP protocol: the versions
from 2024-11-05 to 2025-11-25, which start with a handshake and keep a
session, and the stateless 2026-07-28 revision, in which every request
stands alone and any server process can answer it.

## Posit Connect

[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md)
turns an app into a Shiny app that answers MCP requests at `/mcp`. It
deploys like any Shiny app, to Posit Connect, Shiny Server, or
shinyapps.io:

``` r

# app.R
library(shiny)
library(shinymcp)

show_mileage <- ellmer::tool(...)

app <- mcp_app(fluidPage(...), tools = list(show_mileage), name = "mileage")
mcp_endpoint(app)
```

Chat clients connect to the content’s URL followed by `mcp`, for example
`https://connect.example.com/content/1a2b3c4d/mcp`. People who open the
content’s URL itself get the preview page. Try it locally with
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html): the
preview is at `/` and the endpoint at `/mcp`.

To deploy a Shiny app for people and an MCP App for chat clients
together, give
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md)
both. People who open the URL get the Shiny app, and chat clients get
the MCP App at `/mcp`. The two can share their UI and functions, the MCP
App running a tool where the Shiny app runs a server function:

``` r

shinyApp(ui, server) |> mcp_endpoint(apps = app)
```

Given a Shiny app alone,
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md)
serves the same app, live, to chat clients through
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md):

``` r

shinyApp(ui, server) |>
  mcp_endpoint(name = "mileage", description = "Fuel economy by number of cylinders.")
```

That form goes when Shiny’s own MCP support is released and shinymcp
stops serving live apps; see
[`vignette("shiny-apps")`](https://jameshwade.github.io/shinymcp/articles/shiny-apps.md).

### Signing in

Content that requires a login needs credentials on every request.
Clients send a Connect API key as `Authorization: Key <api-key>`:

``` sh
claude mcp add --transport http mileage \
  https://connect.example.com/content/1a2b3c4d/mcp \
  --header "Authorization: Key $CONNECT_API_KEY"
```

Connect checks the key and tells the app who the user is. Tool functions
see them as `mcp_request()$user` and `mcp_request()$groups` (and a live
Shiny app’s server function as `session$user` and `session$groups`), so
an app can show each person only their data.

### Processes

Apps built from tools keep no state between calls, so Connect can run
them in as many processes as you like.

A live Shiny app is different: each open view keeps its session in the R
process that started it. If Connect runs the app in several processes, a
request can reach one that doesn’t have the session. shinymcp then
starts a new session from the inputs on the page and the app keeps
working, but anything the server function kept outside its inputs starts
over. For apps that keep such state, set **Max processes** to 1 in the
content’s runtime settings.

The
[`posit-connect`](https://github.com/JamesHWade/shinymcp/tree/main/inst/examples/posit-connect)
example has a complete app and the client settings for Claude Code and
VS Code.
