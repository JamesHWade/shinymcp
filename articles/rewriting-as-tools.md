# Rewriting a Shiny app as tools

A Shiny app’s server function turns inputs into outputs through reactive
expressions. Rewritten as tools, the same code becomes ordinary R
functions, each taking some of the app’s inputs as arguments and
returning some of its outputs. The UI stays as it is.
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
puts the two together, and the page calls the tools as the person
changes the inputs, much as the server function would have reacted.

To put an app in a chat without rewriting it, see
[`vignette("shiny-apps")`](https://jameshwade.github.io/shinymcp/articles/shiny-apps.md).

## When to rewrite

A rewrite takes work, so it should buy something. It does when:

- **The model should use the computation on its own.** A tool is useful
  without the app: in chat clients that can’t show apps, to other
  agents, or when the model wants the numbers rather than the picture.
- **Each call should stand alone.** Tools keep no session in R, so any
  process can answer any call, and a restart loses nothing.
- **The model needs only part of the app.** Rewrite that part. The rest
  stays a Shiny app for people to use in the browser.

It doesn’t pay when the part the model needs keeps state as the person
works
([`reactiveVal()`](https://rdrr.io/pkg/shiny/man/reactiveVal.html),
uploaded data, a multi-step workflow) or relies on observers with side
effects.

## An app to rewrite

``` r

ui <- fluidPage(
  titlePanel("Simple Dashboard"),
  sidebarLayout(
    sidebarPanel(
      selectInput("dataset", "Dataset:", c("mtcars", "iris")),
      numericInput("obs", "Observations:", 10, min = 1, max = 50)
    ),
    mainPanel(
      textOutput("summary_text"),
      tableOutput("data_table")
    )
  )
)

server <- function(input, output, session) {
  selected_data <- reactive({
    head(get(input$dataset, envir = asNamespace("datasets")), input$obs)
  })
  output$summary_text <- renderText({
    paste("Showing", nrow(selected_data()), "rows of", input$dataset)
  })
  output$data_table <- renderTable(selected_data())
}
```

## Keep the UI

[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
takes the same UI. Tool arguments match inputs by id, and the names in
the list a tool returns match outputs, so `ui` needs no changes. When an
id can’t match, because two tools share the page or a module prefixed
it, mark the element with
[`mcp_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_input.md)
or
[`mcp_output()`](https://jameshwade.github.io/shinymcp/reference/mcp_output.md).

## Turn the server function into tools

Follow each output back to the inputs it uses. Outputs that use the same
inputs belong in one tool; outputs that use different inputs go in
separate tools, so the page calls only the ones whose inputs changed.
Here both outputs come from `selected_data()`, which uses `dataset` and
`obs`, so one tool returns both.

Then rewrite the code as a function of those inputs:

- `input$x` becomes the argument `x`, with the input’s starting value as
  its default;
- a reactive expression becomes a variable, or a helper function when
  several tools use it;
- each render call becomes the value it rendered, in the returned list
  under its output id.

``` r

show_dataset <- ellmer::tool(
  function(dataset = "mtcars", obs = 10) {
    data <- head(getExportedValue("datasets", dataset), obs)
    list(
      summary_text = paste("Showing", nrow(data), "rows of", dataset),
      data_table = data
    )
  },
  name = "show_dataset",
  description = "Show the first rows of one of R's built-in datasets.",
  arguments = list(
    dataset = ellmer::type_enum(c("mtcars", "iris"), "Dataset to show.", required = FALSE),
    obs = ellmer::type_integer("Number of rows, 1 to 50.", required = FALSE)
  ),
  annotations = ellmer::tool_annotations(read_only_hint = TRUE)
)

app <- mcp_app(ui, tools = list(show_dataset), name = "dashboard")
```

The model reads the tool’s name and descriptions, not its code, so say
what it is for.
[`ellmer::type_enum()`](https://ellmer.tidyverse.org/reference/type_boolean.html)
tells the model the choices a select input offers, and
`required = FALSE` lets it leave out arguments that have defaults.

Each kind of output takes its own kind of value:

| Output | Return |
|----|----|
| [`textOutput()`](https://rdrr.io/pkg/shiny/man/textOutput.html), [`verbatimTextOutput()`](https://rdrr.io/pkg/shiny/man/textOutput.html) | a string |
| [`tableOutput()`](https://rdrr.io/pkg/shiny/man/renderTable.html) | a data frame |
| [`plotOutput()`](https://rdrr.io/pkg/shiny/man/plotOutput.html) | a ggplot object, or `mcp_result_plot(function() ...)` for base graphics |
| [`uiOutput()`](https://rdrr.io/pkg/shiny/man/htmlOutput.html), [`htmlOutput()`](https://rdrr.io/pkg/shiny/man/htmlOutput.html) | an htmltools tag |
| an htmlwidget’s output, such as [`DT::DTOutput()`](https://rdrr.io/pkg/DT/man/dataTableOutput.html) | the widget |

Call the tool as the model would, and open the app with
[`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md):

``` r

app$call_tool("show_dataset", list(dataset = "iris", obs = 3))
preview_app(app)
```

The finished app is in the
[`rewritten-dashboard`](https://github.com/JamesHWade/shinymcp/tree/main/inst/examples/rewritten-dashboard)
example, next to the original.

## What doesn’t rewrite line by line

- **Observers and side effects.** Code that writes files, sends
  messages, or changes state belongs in its own tool, usually one only
  the app may call (`mcp_app(tool_visibility = list(save = "app"))`),
  annotated with `ellmer::tool_annotations(read_only_hint = FALSE)`. An
  `observeEvent(input$save, ...)` becomes a tool that takes `save`, the
  button’s id: it runs when the button is pressed, and not when its
  other inputs change. Without a button, the page never runs it.
- **State kept between interactions.** A tool can’t remember. Pass the
  state in as an argument, or keep that part of the app in Shiny.
- **File uploads.** A tool can’t take a file from the page. Take a path
  or the data as an argument, for the model to supply.
- **Inputs made by
  [`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html).** Inputs
  in HTML that a tool returns aren’t connected to tools. Put every input
  in the UI from the start, and show the ones that apply with
  [`conditionalPanel()`](https://rdrr.io/pkg/shiny/man/conditionalPanel.html).

## Keeping a module’s UI

If the app is built from Shiny modules,
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)
serves a module’s UI with a function of your own in place of its server:

``` r

mcp_tool_module(
  hist_ui,
  name = "eruptions",
  description = "Histogram of waiting times between Old Faithful eruptions.",
  handler = function(bins = 20) {
    list(plot = mcp_result_plot(function() hist(faithful$waiting, breaks = bins)))
  }
)
```

The handler takes the module’s inputs by their ids, without the module’s
namespace, and returns its outputs by id.

## With a coding agent

shinymcp comes with a
[skill](https://github.com/JamesHWade/shinymcp/tree/main/inst/skills/convert-shiny-app)
that takes a coding agent through this rewrite. For Claude Code, copy
its folder,
`system.file("skills", "convert-shiny-app", package = "shinymcp")`, into
`~/.claude/skills/`.
