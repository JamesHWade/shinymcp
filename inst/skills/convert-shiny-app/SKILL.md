---
name: convert-shiny-app
description: Make a Shiny app usable from AI chat clients (Claude, ChatGPT, VS Code) as an MCP App with the shinymcp R package, either by rewriting it as tools or by serving it as it is. Use when asked to convert or port a Shiny app to MCP, to serve a Shiny app to a chat client or agent, or to build an MCP App in R.
---

# Shiny app to MCP App

shinymcp builds MCP Apps: tools with a page that clients supporting the MCP
Apps extension show in the conversation. Clients without the extension get
the same tools, with text results.

For an existing Shiny app there are two routes:

- **Rewrite it as tools**, with `mcp_app()`: the app's UI, unchanged, with
  plain R functions in place of the server function. Each call stands
  alone, so the tools are useful without the page (in clients that can't
  show apps, or to other agents) and run in any number of R processes.
  Take this route when the model should use the computation itself, or
  when the part it needs is a few inputs and outputs.
- **Serve the app as it is**, with `as_mcp_app()`. The server function
  keeps running in R, one session each time the app opens, and nothing is
  rewritten. Take this route when the whole app should appear in the chat,
  especially a large app or one that keeps state as the person works
  (`reactiveVal()`, uploads, multi-step workflows).

If it isn't clear which the user wants, ask.

Shiny is gaining MCP support of its own
(<https://github.com/rstudio/shiny/pull/4407>), and shinymcp will stop
serving live apps once it is released. If the installed shiny has it
(`exists("mcpConfigure", envir = asNamespace("shiny"))` is `TRUE`), serve
the app as it is with Shiny's own support, following its documentation,
instead of `as_mcp_app()`.

## Rewriting the app as tools

### 1. Plan the tools

Read the server function and follow each output back, through the
reactive expressions it uses, to the inputs. Outputs that use the same
inputs become one tool; outputs that use different inputs become separate
tools, so the page calls only the ones whose inputs changed. If the model
needs only part of the app, rewrite only that part.

Note what won't rewrite line by line (step 3): observers with side
effects, state kept between interactions (`reactiveVal()`,
`reactiveValues()`, uploaded data), and inputs created by `renderUI()`.

### 2. Write the app

Write it in its own directory, for example `/full/path/to/app_mcp/app.R`,
so the Shiny app keeps working. Copy the UI as it is: tool arguments match
inputs by id, and the names in the list a tool returns match outputs. Then
write each tool as a function of its inputs:

- `input$x` becomes the argument `x`, with the input's starting value as
  its default;
- a reactive expression becomes a variable, or a helper function when
  several tools use it;
- each render call becomes the value it rendered, in the returned list
  under its output id.

```r
library(shiny)
library(shinymcp)

ui <- fluidPage(...)  # the app's UI, unchanged

show_sales_trend <- ellmer::tool(
  function(region = "West", months = 12) {
    sales <- load_sales(region, months)
    list(
      trend = plot_trend(sales),               # was output$trend <- renderPlot(...)
      summary = summarize_sales(sales)         # was output$summary <- renderText(...)
    )
  },
  name = "show_sales_trend",
  description = "Plot monthly sales for one region, with a one-line summary.",
  arguments = list(
    region = ellmer::type_enum(c("West", "East"), "Sales region.", required = FALSE),
    months = ellmer::type_integer("Months to show, 1 to 36.", required = FALSE)
  ),
  annotations = ellmer::tool_annotations(read_only_hint = TRUE)
)

app <- mcp_app(ui, tools = list(show_sales_trend), name = "sales")

if (interactive()) preview_app(app) else serve(app)
```

Return, by output:

| Output | Return |
|---|---|
| `textOutput()`, `verbatimTextOutput()`, `mcp_text()` | a string |
| `tableOutput()`, `mcp_table()` | a data frame |
| `plotOutput()`, `mcp_plot()` | a ggplot object, or `mcp_result_plot(function() <base graphics code>)` |
| `uiOutput()`, `htmlOutput()`, `mcp_html()` | an htmltools tag |
| an htmlwidget's output | the widget (plotly, leaflet, DT) |

Name and describe each tool for what it does: the model reads those, not
the code. Use `ellmer::type_enum()` for fixed choices and `required =
FALSE` for arguments with defaults.

When an id can't match (two tools share the page, or a module prefixed
it), mark the element with `mcp_input(tag, id = "argument")` or
`mcp_output(tag, id = "output")`. `mcp_tool_result()` sets the text and
structured data the model gets, when the defaults (each output's text, a
table's rows) aren't what it needs.

### 3. What doesn't rewrite line by line

- **Side effects.** Code that writes files, sends messages, or changes a
  database goes in its own tool, hidden from the model with
  `mcp_app(tool_visibility = list(save_report = "app"))` and annotated
  `ellmer::tool_annotations(read_only_hint = FALSE)`. To run it from a
  button, as `observeEvent(input$save, ...)` did, give the tool an argument
  named after the button's id: it runs when the button is pressed, and not
  when its other inputs change. Without a button, the page never runs it.
- **State between interactions** (`reactiveVal()`, uploaded data, a
  multi-step workflow). A tool keeps nothing between calls. Pass the state
  in as an argument, or leave that part of the app out.
- **File uploads.** A tool can't take a file from the page. Take a path or
  the data as an argument, for the model to supply.
- **Inputs made by `renderUI()`.** Inputs in HTML that a tool returns
  aren't connected to tools. Put every input in the UI from the start and
  show the ones that apply with `conditionalPanel()`.

### 4. Test

`as_mcp_app()` loads the app from its `app.R` without serving it:

```r
app <- shinymcp::as_mcp_app("/full/path/to/app_mcp")
app$call_tool("show_sales_trend", list(region = "East"))  # the R value
app$run_tool("show_sales_trend", list(region = "East"))   # what a client gets
```

Because `app.R` ends with `if (interactive()) preview_app(app) else
serve(app)`, the same file previews the app in an interactive session and
serves it when a client starts it with `Rscript
/full/path/to/app_mcp/app.R`.

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

## Registering the app with a client

Register the script that serves the app: `app_mcp/app.R` for a rewritten
app, `mcp.R` for one served as it is. Claude Desktop, in
`claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "sales": {
      "command": "Rscript",
      "args": ["/full/path/to/app_mcp/app.R"]
    }
  }
}
```

Claude Code: `claude mcp add sales -- Rscript /full/path/to/app_mcp/app.R`.

On macOS, desktop clients don't see the shell's `PATH`; use the full path to
`Rscript` (from `which Rscript`). To check the script, run it with
`Rscript` in a terminal: it should wait without printing anything.

For clients that connect to a URL, `serve(app, type = "http", port = 8080)`
serves it at `http://127.0.0.1:8080/mcp`. To deploy to Posit Connect or
Shiny Server, end `app.R` with `mcp_endpoint(app)`. To keep the Shiny app
for people and serve the rewritten app to chat clients from the same
deployment, end it with `shinyApp(ui, server) |> mcp_endpoint(apps = app)`;
for a Shiny app served as it is, `shinyApp(ui, server) |>
mcp_endpoint(name = "sales")`. Chat clients connect to the content's URL
followed by `/mcp`.
