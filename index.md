# Your Shiny app, live inside the chat.

R package · works with Claude Desktop & shinychat

shinymcp turns Shiny interfaces and R computations into **MCP Apps** —
interactive cards that run inside AI chat, Shiny hosts, and shinychat.

[Get started →](#quick-start) [View on
GitHub](https://github.com/JamesHWade/shinymcp)

\> `pak::pak(“JamesHWade/shinymcp”)`

↑ a real MCP App — change an input, the bridge calls your R tool and
redraws the card in place

## Three ways in

Start from scratch, move an app you already ship, or wire MCP cards into
a chat assistant.

[](#quick-start)

Build

### Create an MCP App

Use the Shiny and bslib inputs you already know, add MCP output targets,
and bind them to R tools.

Jump to quick start →
[](https://jameshwade.github.io/shinymcp/articles/converting-shiny-apps.md)

Convert

### Move an existing Shiny app

Flatten reactive groups into tool functions. The workflow users see
stays the same.

Read the guide →
[](https://jameshwade.github.io/shinymcp/articles/use-shinymcp-with-shinychat.md)

Integrate

### Render apps inside shinychat

Return MCP cards from chat tools, with state sync and a full-screen
mode.

Read the guide →

## Quick start

An MCP App has two parts: UI components that render in the chat
interface, and tools that run R code when inputs change. Use standard
shiny or bslib inputs — the bridge finds them by matching tool argument
names to element `id` attributes.

``` r

library(shinymcp)
library(bslib)

ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "Dataset Explorer",
  sidebar = sidebar(
    # Standard shiny input — auto-detected because id matches tool arg "dataset"
    shiny::selectInput("dataset", "Choose dataset", c("mtcars", "iris", "pressure"))
  ),
  card(
    card_header("Summary"),
    mcp_text("summary")
  )
)

tools <- list(
  ellmer::tool(
    fun = function(dataset = "mtcars") {
      data <- get(dataset, envir = asNamespace("datasets"))
      paste(capture.output(summary(data)), collapse = "\n")
    },
    name = "get_summary",
    description = "Get summary statistics for the selected dataset",
    arguments = list(dataset = ellmer::type_string("Dataset name"))
  )
)

app <- mcp_app(ui, tools, name = "dataset-explorer")
serve(app)
```

Save this as `app.R`, register it in your Claude Desktop config, and
restart. When the tool runs, the UI appears inline in the conversation.
Change the dropdown and the tool runs again and updates the output — no
page reload.

## A lightweight bridge, no npm

MCP Apps render inside sandboxed iframes. A small JavaScript bridge
handles the round-trip via postMessage and JSON-RPC.

01

#### User changes an input

The bridge matches tool argument names to element ids, then collects
every value.

02

#### Bridge sends tools/call

A JSON-RPC request travels over postMessage from the sandboxed iframe to
the host chat client.

03

#### Host proxies to your R process

The MCP host forwards the call to the MCP server running your R session.

04

#### Your tool function runs

Plain R executes and returns a named list of results: a base64 plot, a
table, summary text.

05

#### Outputs update in place

The bridge routes each value to the matching output element. No page
reload, no redeploy.

## Component reference

Inputs are standard shiny / bslib elements, auto-detected by `id`.
Outputs map one-to-one onto familiar Shiny render functions.

| Shiny | shinymcp | Notes |
|----|----|----|
| `textOutput()` / `verbatimTextOutput()` | [`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_text.md) | Renders in a monospace block |
| `plotOutput()` | [`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md) | Tool returns a base64-encoded PNG |
| `tableOutput()` | [`mcp_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_table.md) | Tool returns an HTML table string |
| `htmlOutput()` | [`mcp_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_html.md) | Tool returns raw HTML |

For a full worked example, see
[`vignette("converting-shiny-apps")`](https://jameshwade.github.io/shinymcp/articles/converting-shiny-apps.md).
For the complete component list, see the [reference
index](https://jameshwade.github.io/shinymcp/reference/index.md).
