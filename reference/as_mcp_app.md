# Serve a Shiny app as an MCP App

`as_mcp_app()` turns an existing Shiny app into an MCP App without
rewriting it. The app's UI becomes the page the chat client shows, and
its server function keeps running in R: each time the app opens in the
conversation, shinymcp starts a session for it, and the user's changes
flow to that session the way they would from a browser. Reactive
expressions, observers,
[`updateSelectInput()`](https://rdrr.io/pkg/shiny/man/updateSelectInput.html)
and friends,
[`validate()`](https://rdrr.io/pkg/shiny/man/validate.html)/[`req()`](https://rdrr.io/pkg/shiny/man/req.html),
notifications, modals, and downloads all work.

The model gets one tool, named after the app. Its arguments are the
app's inputs, so the model can open the app already set up ("show the
penguins explorer for Gentoo"). The result tells the model what the app
shows: text outputs as text, tables (DT's included) as their rows, plots
as images.

Choose what the model sees with
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md).
Once any input or output is marked, only marked inputs become tool
arguments and only marked outputs are reported; the user still sees the
whole app. Buttons are never pressed by the model unless you mark them,
and password and file inputs are never the model's to set.

## Usage

``` r
as_mcp_app(x, ...)

# S3 method for class 'shiny.appobj'
as_mcp_app(
  x,
  name = NULL,
  title = NULL,
  description = NULL,
  tools = NULL,
  tool_name = NULL,
  selective = NULL,
  version = "0.1.0",
  ...
)

# S3 method for class 'McpApp'
as_mcp_app(x, ...)

# S3 method for class 'character'
as_mcp_app(x, name = NULL, ...)

# Default S3 method
as_mcp_app(x, ...)
```

## Arguments

- x:

  A Shiny app (from
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html) or
  [`shiny::shinyAppDir()`](https://rdrr.io/pkg/shiny/man/shinyApp.html)),
  a path to an app directory (with `app.R`, or `ui.R` and `server.R`),
  or an
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  (returned unchanged). An `app.R` may build an
  [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  instead of a Shiny app; its tools run, and its page is built, in the
  app's directory.

- ...:

  Passed on to
  [`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md),
  for example `csp`, `prefers_border`, `images`, or `www` (which
  defaults to the app directory's `www/` folder).

- name:

  App name, used for the `ui://<name>` resource and the tool name.
  Defaults to the directory name for a path, otherwise `"shiny-app"`.

- title:

  Human-readable title.

- description:

  What the app does, for the model. By default shinymcp writes one from
  the inputs and outputs; a sentence about what the app is *for* helps
  the model decide when to open it.

- tools:

  More tools for the model, such as
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects, served next to the one that opens the app: a computation the
  model should be able to run without opening it, say.

- tool_name:

  Name of the tool that opens the app. Defaults to `name` with anything
  other than letters, digits, `-` and `_` replaced.

- selective:

  Whether only inputs and outputs marked with
  [`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
  are exposed to the model. Defaults to `TRUE` if anything is marked.

- version:

  App version string.

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md).

## What runs where

The page is the app's UI rendered once to HTML, with shinymcp's bridge
in place of Shiny's JavaScript. The bridge draws Shiny's built-in inputs
itself (select, slider, date, checkbox group, and so on), and puts
outputs sent back from R on the page: text, HTML, tables, plots,
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html), and
htmlwidgets such as plotly, DT, and leaflet. Conditional panels show and
hide, and clicks and brushes on plots reach the server as they would
from a browser, for
[`shiny::nearPoints()`](https://rdrr.io/pkg/shiny/man/brushedPoints.html)
and
[`shiny::brushedPoints()`](https://rdrr.io/pkg/shiny/man/brushedPoints.html).

Packages written for Shiny's JavaScript API work too. The page provides
`window.Shiny` with the parts packages use: input bindings they register
(shinyWidgets, for example), `Shiny.setInputValue()` (DT row selection,
plotly's `event_data()`, leaflet clicks), custom message handlers
(shinyjs), and the `shiny:value` family of events (shinycssloaders).
File inputs upload to the session, within `shiny.maxRequestSize`.
[`invalidateLater()`](https://rdrr.io/pkg/shiny/man/invalidateLater.html)
and [`reactivePoll()`](https://rdrr.io/pkg/shiny/man/reactivePoll.html)
run while the app is open.

The app starts as
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) would
start it: its `onStart` (for a directory, `global.R` and the files in
`R/`) runs once, before the UI is built, and its code runs in the app's
directory. Scripts, stylesheets, and images the UI loads from `www/` or
from
[`shiny::addResourcePath()`](https://rdrr.io/pkg/shiny/man/resourcePaths.html)
paths are written into the page. `onStop` runs when the server stops.

## Sessions

Sessions live in the R process that serves the app, up to 50 at a time
(the `shinymcp.max_views` option), each closing after an hour without
use (`shinymcp.view_timeout`, in seconds). If a request reaches a
process that doesn't have the view's session (after a restart, or on a
server running several processes), a new session starts from the inputs
on the page. Anything the server function kept outside its inputs (a
[`reactiveVal()`](https://rdrr.io/pkg/shiny/man/reactiveVal.html) that
counts clicks, say) starts over.

## Shiny's own MCP support

Shiny is gaining MCP support of its own
(<https://github.com/rstudio/shiny/pull/4407>). Once it is released, it
will be the way to put a live Shiny app in a chat, and shinymcp will
stop serving live apps. `as_mcp_app()`,
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md),
and
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)
will take only apps built from tools, and
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
and the helpers for server functions
([`mcp_model_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md),
[`mcp_host_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_context.md),
and the rest) will be removed. For something the model should be able to
use on its own, rewrite that part of the app as tools with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md);
see
[`vignette("rewriting-as-tools")`](https://jameshwade.github.io/shinymcp/articles/rewriting-as-tools.md).

## See also

Other apps:
[`McpApp`](https://jameshwade.github.io/shinymcp/reference/McpApp.md),
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md),
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md),
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)

## Examples

``` r
if (FALSE) { # \dontrun{
library(shiny)

ui <- fluidPage(
  selectInput("cyl", "Cylinders", c(4, 6, 8)),
  plotOutput("scatter"),
  textOutput("count")
)
server <- function(input, output, session) {
  cars <- reactive(mtcars[mtcars$cyl == input$cyl, ])
  output$scatter <- renderPlot(plot(cars()$wt, cars()$mpg))
  output$count <- renderText(paste(nrow(cars()), "cars"))
}

app <- as_mcp_app(
  shinyApp(ui, server),
  name = "cars",
  description = "Explore fuel economy in mtcars by number of cylinders."
)
preview_app(app)
serve(app)

# Or straight from a directory:
serve("path/to/my-app")
} # }
```
