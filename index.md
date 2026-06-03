<!-- This file becomes the pkgdown site home page (overrides README for the site).
     Keep README.Rmd for the GitHub landing; this drives jameshwade.github.io/shinymcp.
     NOTE: raw HTML below is intentionally flush-left. Pandoc treats any line indented
     4+ spaces as a code block, which breaks these blocks out of their raw-HTML context. -->

<div class="smc-hero">
<span class="smc-chip"><span class="dot"></span> R package · works with Claude Desktop &amp; shinychat</span>
<h1 class="smc-title">Your Shiny app, <span class="smc-grad">live inside the chat.</span></h1>
<p class="smc-lede">shinymcp turns Shiny interfaces and R computations into <strong>MCP Apps</strong> — interactive cards that run inside AI chat, Shiny hosts, and shinychat.</p>
<div class="smc-actions">
<a class="btn smc-btn smc-btn-primary" href="#quick-start">Get started →</a>
<a class="btn smc-btn smc-btn-ghost" href="https://github.com/JamesHWade/shinymcp">View on GitHub</a>
</div>
<div class="smc-install"><span class="smc-prompt">&gt;</span> <code>pak::pak("JamesHWade/shinymcp")</code></div>
</div>

<div id="smc-demo" class="smc-demo-frame" data-logo="logo.png"></div>
<p class="smc-demo-cap">↑ a real MCP App — change an input, the bridge calls your R tool and redraws the card in place</p>

<div class="smc-section">
<h2 id="start-with-a-path">Three ways in</h2>
<p class="smc-section-lede">Start from scratch, move an app you already ship, or wire MCP cards into a chat assistant.</p>
<div class="smc-paths">
<a class="smc-path" href="#quick-start">
<div class="smc-path-tag">Build</div>
<h3>Create an MCP App</h3>
<p>Use the Shiny and bslib inputs you already know, add MCP output targets, and bind them to R tools.</p>
<span class="smc-path-more">Jump to quick start →</span>
</a>
<a class="smc-path" href="articles/converting-shiny-apps.html">
<div class="smc-path-tag">Convert</div>
<h3>Move an existing Shiny app</h3>
<p>Flatten reactive groups into tool functions. The workflow users see stays the same.</p>
<span class="smc-path-more">Read the guide →</span>
</a>
<a class="smc-path" href="articles/use-shinymcp-with-shinychat.html">
<div class="smc-path-tag">Integrate</div>
<h3>Render apps inside shinychat</h3>
<p>Return MCP cards from chat tools, with state sync and a full-screen mode.</p>
<span class="smc-path-more">Read the guide →</span>
</a>
</div>
</div>

## Quick start

An MCP App has two parts: UI components that render in the chat interface, and tools that run R code when inputs change. Use standard shiny or bslib inputs — the bridge finds them by matching tool argument names to element `id` attributes.

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

Save this as `app.R`, register it in your Claude Desktop config, and restart. When the tool runs, the UI appears inline in the conversation. Change the dropdown and the tool runs again and updates the output — no page reload.

<div class="smc-section">
<h2 id="how-it-works">A lightweight bridge, no npm</h2>
<p class="smc-section-lede">MCP Apps render inside sandboxed iframes. A small JavaScript bridge handles the round-trip via postMessage and JSON-RPC.</p>
<div class="smc-steps">
<div class="smc-step"><span class="smc-step-n">01</span><div><h4>User changes an input</h4><p>The bridge matches tool argument names to element ids, then collects every value.</p></div></div>
<div class="smc-step"><span class="smc-step-n">02</span><div><h4>Bridge sends tools/call</h4><p>A JSON-RPC request travels over postMessage from the sandboxed iframe to the host chat client.</p></div></div>
<div class="smc-step"><span class="smc-step-n">03</span><div><h4>Host proxies to your R process</h4><p>The MCP host forwards the call to the MCP server running your R session.</p></div></div>
<div class="smc-step"><span class="smc-step-n">04</span><div><h4>Your tool function runs</h4><p>Plain R executes and returns a named list of results: a base64 plot, a table, summary text.</p></div></div>
<div class="smc-step"><span class="smc-step-n">05</span><div><h4>Outputs update in place</h4><p>The bridge routes each value to the matching output element. No page reload, no redeploy.</p></div></div>
</div>
</div>

## Component reference

Inputs are standard shiny / bslib elements, auto-detected by `id`. Outputs map one-to-one onto familiar Shiny render functions.

| Shiny | shinymcp | Notes |
|----|----|----|
| `textOutput()` / `verbatimTextOutput()` | `mcp_text()` | Renders in a monospace block |
| `plotOutput()` | `mcp_plot()` | Tool returns a base64-encoded PNG |
| `tableOutput()` | `mcp_table()` | Tool returns an HTML table string |
| `htmlOutput()` | `mcp_html()` | Tool returns raw HTML |

For a full worked example, see `vignette("converting-shiny-apps")`. For the complete component list, see the [reference index](reference/index.html).
