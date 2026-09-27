---
name: convert-shiny-app
description: Make a Shiny app usable from AI chat clients (Claude, ChatGPT, VS Code) as an MCP App with the shinymcp R package, either by serving the app as it is or by rewriting it as tools. Use when asked to convert or port a Shiny app to MCP, to serve a Shiny app to a chat client or agent, or to build an MCP App in R.
---

# Shiny app to MCP App

shinymcp serves Shiny apps as MCP Apps. A client that supports the MCP Apps
extension shows the app in the conversation, and the model opens it through
a tool, sets its inputs, and reads its outputs. Clients without the
extension get the same tools, with text results.

There are two routes:

- **Serve the app as it is**, with `as_mcp_app()`. The server function
  keeps running in R, one session each time the app opens. Nothing is
  rewritten. Take this route unless there is a reason not to.
- **Rewrite it as tools**, with `mcp_app()`: plain R functions that take the
  inputs and return the outputs, with no session. Take this route only when
  the user asks for it, when the model must use the computation without the
  app (in clients that can't show apps, or from other agents), or when each
  call must stand alone, with nothing kept in the R process between calls.

## Serving the app as it is

### 1. Read the app

Read `app.R`, or `ui.R`, `server.R`, and `global.R`, and the files in `R/`.
Note:

- which inputs and outputs matter for what the app is for;
- anything loaded from another site: `https://` URLs in `tags$script()`,
  `tags$link()`, or `tags$img()`, map tiles, web fonts;
- icons made with `icon()` (Font Awesome);
- `withProgress()`, bookmarking, `updateQueryString()`, and
  `session$reload()`.

### 2. Write the server script

Write a script that makes the app and serves it, for example `mcp.R` next
to `app.R` (not in `R/`, which Shiny sources):

```r
library(shinymcp)

app <- as_mcp_app(
  "/full/path/to/app",
  name = "sales",
  title = "Sales explorer",
  description = "Monthly sales by region and product line, with a forecast."
)

serve(app)
```

- Use the app directory's full path. Chat clients start the script from a
  directory of their own.
- The model reads `description` when it decides whether to open the app.
  Say what the app is for in a sentence or two. The default only lists the
  inputs and outputs.
- `name` is also the tool's name. Keep it short: letters, digits, `_`, `-`.
- Nothing may print to standard output before `serve()` starts, because
  the protocol runs over it. Messages and warnings go to standard error and
  are fine.

`as_mcp_app()` starts the app as `shiny::runApp()` would: `global.R`, the
files in `R/`, and `onStart` run first, the code runs in the app's
directory, and files in `www/` are written into the page. It also takes a
Shiny app object, `as_mcp_app(shinyApp(ui, server), ...)`.

### 3. Check what the model gets

Run the tool in R, as a client would:

```r
app$tool_definitions()[[1]]$inputSchema  # the arguments the model sees
result <- app$run_tool("sales", list(region = "West"))
isTRUE(result$isError)                   # should be FALSE
cat(result$content[[1]]$text)            # what the model reads
```

Plots reach the model as images as well. `as_mcp_app(images = FALSE)`
leaves them out.

To see the app as a chat client shows it, the user can run
`preview_app(app)` in an interactive session.

### 4. Narrow the tool when the app is large

A large app gives the model a tool with many arguments, most of them beside
the point. Mark the inputs and outputs the model should use with
`bindMcp()`:

```r
selectInput("region", "Region", regions) |> bindMcp(),
sliderInput("alpha", "Point opacity", 0, 1, 0.7),
plotOutput("trend") |> bindMcp(),
```

Once anything is marked, only marked inputs are arguments and only marked
outputs are reported. The person using the app still sees and uses all of
it. The model presses an action button only if it is marked, and never sets
password or file inputs. `bindMcp()` changes nothing when the app runs in
Shiny.

### 5. Tell the model what the person did (optional)

When the person changes something, the page tells the model the current
values of the inputs it can set and a summary of each output it reads. For
something more useful, call `mcp_model_context()` from the server function:

```r
observe({
  mcp_model_context(
    text = sprintf("Showing %s sales in %s.", input$product, input$region),
    data = list(region = input$region, product = input$product)
  )
})
```

Keep it short and factual. It does nothing in an ordinary Shiny session;
`is_mcp_session()` tells the two apart.

### 6. Fix what doesn't carry over

The client shows the page in a sandboxed iframe under a Content Security
Policy that blocks what the app doesn't declare.

| In the app | What to do |
|---|---|
| Scripts, stylesheets, images, or fonts from another site | Declare the domains: `as_mcp_app(..., csp = list(resource_domains = "https://cdn.example.com"))`. |
| `fetch()` or WebSockets to another site | `csp = list(connect_domains = ...)`. |
| `icon()` and other icon fonts | Fonts in the page can't load. Use SVG icons, such as `bsicons::bs_icon()`. |
| `withProgress()` | Shows nothing. The request finishes before the page hears of it. |
| Bookmarking, `updateQueryString()`, `session$reload()` | There is no page URL to act on. |
| Output bindings from packages, other than htmlwidgets | Shown as text. |
| Uploads larger than 5 MB | `options(shiny.maxRequestSize = ...)`, as in Shiny. |

Everything else works as it does in a browser: reactive expressions,
observers, `renderUI()`, modules, htmlwidgets, `update*Input()`,
notifications, modals, downloads, uploads, `invalidateLater()`, and packages
built on Shiny's JavaScript (shinyWidgets, DT row selection,
`plotly::event_data()`, shinyjs).

### 7. Register the script with a client

Claude Desktop, in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "sales": {
      "command": "Rscript",
      "args": ["/full/path/to/mcp.R"]
    }
  }
}
```

Claude Code: `claude mcp add sales -- Rscript /full/path/to/mcp.R`.

On macOS, desktop clients don't see the shell's `PATH`; use the full path to
`Rscript` (from `which Rscript`). To check the script, run
`Rscript /full/path/to/mcp.R` in a terminal: it should wait without
printing anything.

For clients that connect to a URL, `serve(app, type = "http", port = 8080)`
serves it at `http://127.0.0.1:8080/mcp`. To deploy to Posit Connect or
Shiny Server, end `app.R` with `shinyApp(ui, server) |> mcp_endpoint(name =
"sales")`: browsers get the Shiny app and chat clients connect to the
content's URL followed by `/mcp`.

## Rewriting the app as tools

### 1. Draft with `convert_app()`

```r
shinymcp::convert_app("/full/path/to/app")
```

It reads the code without running it, groups outputs that share inputs into
one tool each, and writes `ui.R`, `tools.R`, and `app.R` to
`/full/path/to/app_mcp/`, with `CONVERSION_NOTES.md` when some code doesn't
fit a tool (observers with side effects, for example). Each draft tool
takes its inputs as typed arguments with the app's defaults, holds the
app's code for its outputs as comments, and returns placeholder text for
each output, so the draft runs as it is.

### 2. Finish each tool

Rewrite each tool's body as a function of its arguments:

- `input$x` becomes the argument `x`;
- a reactive expression becomes an ordinary variable;
- each render call becomes the value it rendered, returned in a list named
  by output id.

Return, by output:

| Output | Return |
|---|---|
| `textOutput()`, `verbatimTextOutput()`, `mcp_text()` | a string |
| `tableOutput()`, `mcp_table()` | a data frame |
| `plotOutput()`, `mcp_plot()` | a ggplot object, or `mcp_result_plot(function() <base graphics code>)` |
| `uiOutput()`, `htmlOutput()`, `mcp_html()` | an htmltools tag |
| an htmlwidget's output | the widget (plotly, leaflet, DT) |

Name and describe each tool for what it does ("show_sales_trend", "Plot
monthly sales for one region"): the model reads those, not the code. Use
`ellmer::type_enum()` for fixed choices and `required = FALSE` for arguments
with defaults.

`mcp_tool_result()` sets the text and structured data the model gets, when
the defaults (each output's text, a table's rows) aren't what it needs.

### 3. What doesn't rewrite line by line

- **Side effects.** Code that writes files, sends messages, or changes a
  database goes in its own tool, hidden from the model with
  `mcp_app(tool_visibility = list(save_report = "app"))` and annotated
  `ellmer::tool_annotations(read_only_hint = FALSE)`. To run it from a
  button, as `observeEvent(input$save, ...)` did, give the tool an argument
  named after the button's id: it runs when the button is pressed, and not
  when its other inputs change.
- **State between interactions** (`reactiveVal()`, uploaded data, a
  multi-step workflow). A tool keeps nothing between calls. Pass the state
  in as an argument, or serve that part of the app with `as_mcp_app()`.
- **File uploads.** A tool can't take a file from the page. Take a path or
  the data as an argument, for the model to supply, or keep the upload in a
  Shiny app.

### 4. Test

`as_mcp_app()` loads the app from its `app.R` without serving it:

```r
app <- shinymcp::as_mcp_app("/full/path/to/app_mcp")
app$call_tool("show_sales_trend", list(region = "West"))  # the R value
app$run_tool("show_sales_trend", list(region = "West"))   # what a client gets
```

`app.R` ends with `if (interactive()) preview_app(app) else serve(app)`, so
the same file previews the app in an interactive session and serves it when
a client starts it with `Rscript /full/path/to/app_mcp/app.R`. Register it
with a client as in step 7 above.
