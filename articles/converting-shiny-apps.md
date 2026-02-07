# Converting Shiny Apps to MCP Apps

MCP Apps are interactive UIs that render directly inside AI chat
interfaces like Claude Desktop. Unlike Shiny apps that run in a browser
with a persistent server, MCP Apps are lightweight HTML documents where
user interactions trigger **tool calls** — stateless R functions that
the AI host invokes on demand.

This vignette walks through converting a Shiny app into an MCP App using
shinymcp. We’ll use the classic Palmer Penguins explorer as a worked
example.

## Key differences from Shiny

Before converting, it helps to understand what changes:

|                  | Shiny                                                                                                                                | MCP App                                                                                                                                                  |
|------------------|--------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Runs in**      | Browser tab                                                                                                                          | AI chat interface (iframe)                                                                                                                               |
| **Server**       | Persistent R process with reactive graph                                                                                             | Stateless tool calls                                                                                                                                     |
| **Reactivity**   | [`reactive()`](https://rdrr.io/pkg/shiny/man/reactive.html), [`observe()`](https://rdrr.io/pkg/shiny/man/observe.html), `render*()`  | Tool function called on input change                                                                                                                     |
| **UI framework** | shiny.js + WebSocket                                                                                                                 | Plain HTML + postMessage bridge                                                                                                                          |
| **State**        | Server-side reactive values                                                                                                          | Recomputed each tool call                                                                                                                                |
| **Layout**       | [`fluidPage()`](https://rdrr.io/pkg/shiny/man/fluidPage.html), [`sidebarLayout()`](https://rdrr.io/pkg/shiny/man/sidebarLayout.html) | bslib ([`page_sidebar()`](https://rstudio.github.io/bslib/reference/page_sidebar.html), [`card()`](https://rstudio.github.io/bslib/reference/card.html)) |

The core shift: **flatten your reactive graph into tool functions**.
Each connected group of inputs → reactives → outputs becomes a single
tool that accepts inputs as arguments and returns outputs as a named
list.

## Step 1: Identify inputs and outputs

Start with your Shiny app and list every input and output. Here’s a
typical penguins Shiny app:

``` r
# --- Original Shiny app ---
library(shiny)
library(ggplot2)
library(palmerpenguins)

ui <- fluidPage(
  titlePanel("Palmer Penguins Explorer"),
  sidebarLayout(
    sidebarPanel(
      selectInput("species", "Species", c("All", "Adelie", "Chinstrap", "Gentoo")),
      selectInput("x_var", "X axis", c("bill_length_mm", "bill_depth_mm",
                                        "flipper_length_mm", "body_mass_g")),
      selectInput("y_var", "Y axis", c("bill_depth_mm", "bill_length_mm",
                                        "flipper_length_mm", "body_mass_g")),
      checkboxInput("trend", "Show trend line", FALSE)
    ),
    mainPanel(
      plotOutput("scatter"),
      verbatimTextOutput("stats")
    )
  )
)

server <- function(input, output, session) {
  filtered_data <- reactive({
    data <- penguins[complete.cases(penguins), ]
    if (input$species != "All") {
      data <- data[data$species == input$species, ]
    }
    data
  })

  output$scatter <- renderPlot({
    p <- ggplot(filtered_data(),
                aes(x = .data[[input$x_var]], y = .data[[input$y_var]],
                    color = species)) +
      geom_point(alpha = 0.7, size = 2.5)
    if (input$trend) p <- p + geom_smooth(method = "lm", se = FALSE)
    p
  })

  output$stats <- renderPrint({
    summary(filtered_data()[, c(input$x_var, input$y_var, "species")])
  })
}

shinyApp(ui, server)
```

From this app, we identify:

**Inputs:**

- `species` — `selectInput` with 4 choices
- `x_var` — `selectInput` with 4 variable choices
- `y_var` — `selectInput` with 4 variable choices
- `trend` — `checkboxInput` (boolean)

**Outputs:**

- `scatter` — `plotOutput` (a ggplot scatter plot)
- `stats` — `verbatimTextOutput` (summary statistics)

**Reactive logic:**

- `filtered_data()` filters penguins by species
- Both outputs depend on `filtered_data()` plus the axis/trend inputs
- Everything is connected — one reactive group → one tool

## Step 2: Map components

Replace Shiny inputs with shinymcp equivalents:

| Shiny                                        | shinymcp                                    |
|----------------------------------------------|---------------------------------------------|
| `selectInput("species", "Species", choices)` | `mcp_select("species", "Species", choices)` |
| `selectInput("x_var", "X axis", choices)`    | `mcp_select("x_var", "X axis", choices)`    |
| `checkboxInput("trend", "Show trend line")`  | `mcp_checkbox("trend", "Show trend line")`  |
| `plotOutput("scatter")`                      | `mcp_plot("scatter")`                       |
| `verbatimTextOutput("stats")`                | `mcp_text("stats")`                         |

The IDs stay the same. The component APIs are intentionally similar.

## Step 3: Build the UI

Use bslib for layout instead of Shiny’s
[`fluidPage()`](https://rdrr.io/pkg/shiny/man/fluidPage.html) /
[`sidebarLayout()`](https://rdrr.io/pkg/shiny/man/sidebarLayout.html).
bslib components work directly with htmltools — no Shiny server needed:

``` r
library(shinymcp)
library(bslib)
library(htmltools)

ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "Palmer Penguins Explorer",
  sidebar = sidebar(
    width = 260,
    mcp_select(
      "species", "Species",
      c("All", "Adelie", "Chinstrap", "Gentoo")
    ),
    mcp_select("x_var", "X axis", c(
      "Bill Length (mm)" = "bill_length_mm",
      "Bill Depth (mm)" = "bill_depth_mm",
      "Flipper Length (mm)" = "flipper_length_mm",
      "Body Mass (g)" = "body_mass_g"
    )),
    mcp_select("y_var", "Y axis", c(
      "Bill Depth (mm)" = "bill_depth_mm",
      "Bill Length (mm)" = "bill_length_mm",
      "Flipper Length (mm)" = "flipper_length_mm",
      "Body Mass (g)" = "body_mass_g"
    )),
    mcp_checkbox("trend", "Show trend line")
  ),
  card(
    card_header("Scatter Plot"),
    mcp_plot("scatter", height = "380px")
  ),
  card(
    card_header("Summary Statistics"),
    mcp_text("stats")
  )
)
```

Named choice vectors (e.g. `"Bill Length (mm)" = "bill_length_mm"`) work
exactly like Shiny — the name is displayed, the value is sent to the
tool.

## Step 4: Convert reactive logic to a tool

This is the key step. Flatten the reactive graph into a single function:

1.  The function **arguments** are the input values (with sensible
    defaults)
2.  The function **body** does what the reactives and renderers did
3.  The function **returns** a named list mapping output IDs to values

For plots, render to a temporary PNG and return the base64-encoded
image. The bridge displays it as an `<img>` element.

``` r
tools <- list(
  ellmer::tool(
    fun = function(
      species = "All",
      x_var = "bill_length_mm",
      y_var = "bill_depth_mm",
      trend = FALSE
    ) {
      data <- palmerpenguins::penguins
      data <- data[complete.cases(data), ]

      # Filter (was: filtered_data reactive)
      if (species != "All") {
        data <- data[data$species == species, ]
      }

      # Plot (was: renderPlot)
      p <- ggplot2::ggplot(
        data,
        ggplot2::aes(x = .data[[x_var]], y = .data[[y_var]], color = species)
      ) +
        ggplot2::geom_point(alpha = 0.7, size = 2.5) +
        ggplot2::theme_minimal(base_size = 13)

      if (isTRUE(trend)) {
        p <- p + ggplot2::geom_smooth(method = "lm", se = FALSE)
      }

      # Render plot to base64 PNG
      tmp <- tempfile(fileext = ".png")
      ggplot2::ggsave(tmp, p, width = 7, height = 4, dpi = 144, bg = "white")
      on.exit(unlink(tmp))
      plot_b64 <- base64enc::base64encode(tmp)

      # Summary text (was: renderPrint)
      stats <- paste(capture.output({
        cat(sprintf("Observations: %d penguins\n\n", nrow(data)))
        print(summary(data[, c(x_var, y_var, "species")]))
      }), collapse = "\n")

      # Return named list: keys must match output IDs
      list(scatter = plot_b64, stats = stats)
    },
    name = "explore_penguins",
    description = "Explore the Palmer Penguins dataset with scatter plots",
    arguments = list(
      species = ellmer::type_string("Species filter: All, Adelie, Chinstrap, or Gentoo"),
      x_var = ellmer::type_string("X axis variable name"),
      y_var = ellmer::type_string("Y axis variable name"),
      trend = ellmer::type_boolean("Whether to show a linear trend line")
    )
  )
)
```

Important details:

- **Return keys match output IDs**: `list(scatter = ..., stats = ...)`
  corresponds to `mcp_plot("scatter")` and `mcp_text("stats")`. The
  bridge uses these keys to route values to the correct output elements.

- **Base64 plots**: Use
  [`ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html) or
  [`png()`](https://rdrr.io/r/grDevices/png.html) +
  [`dev.off()`](https://rdrr.io/r/grDevices/dev.html), then
  [`base64enc::base64encode()`](https://rdrr.io/pkg/base64enc/man/base64.html).
  The bridge wraps this in an `<img>` tag.

- **Text output**:
  [`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_text.md)
  renders in a `<pre>` tag, so R’s
  [`summary()`](https://rdrr.io/r/base/summary.html) and
  [`cat()`](https://rdrr.io/r/base/cat.html) output preserves column
  alignment.

- **Default arguments**: Every argument needs a default value. This is
  what the tool uses when loaded initially and what the AI sees as the
  expected format.

- **Stateless**: No
  [`reactiveVal()`](https://rdrr.io/pkg/shiny/man/reactiveVal.html), no
  `<<-`, no session state. Each tool call recomputes from scratch. For
  most apps this is fine since tool calls are fast.

## Step 5: Assemble and serve

Wire up the UI, tools, and server:

``` r
app <- mcp_app(ui, tools, name = "penguins-explorer")
serve(app)
```

Save this as a single `app.R` file. To register it with Claude Desktop,
add an entry to your Claude Desktop config
(`~/Library/Application Support/Claude/claude_desktop_config.json` on
macOS):

``` json
{
  "mcpServers": {
    "penguins": {
      "command": "/opt/homebrew/bin/Rscript",
      "args": ["/path/to/your/app.R"]
    }
  }
}
```

Restart Claude Desktop, and the app will appear as an interactive UI
when the `explore_penguins` tool is called.

## Conversion patterns

### One reactive group → one tool

If all your outputs share the same reactive dependencies, they belong in
a single tool. This is the most common case:

``` r
# Shiny: two outputs from one reactive
server <- function(input, output, session) {
  data <- reactive({ mtcars[mtcars$cyl == input$cyl, ] })
  output$plot <- renderPlot({ plot(data()$mpg) })
  output$text <- renderText({ paste(nrow(data()), "cars") })
}

# MCP App: one tool returning both
ellmer::tool(
  fun = function(cyl = 4) {
    data <- mtcars[mtcars$cyl == cyl, ]
    list(
      plot = render_plot_base64(function() plot(data$mpg)),
      text = paste(nrow(data), "cars")
    )
  },
  # ...
)
```

### Independent outputs → multiple tools

If outputs have completely independent inputs, use separate tools. The
bridge calls all tools whose inputs changed:

``` r
# Tool 1: only uses the "dataset" input
ellmer::tool(
  fun = function(dataset = "mtcars") { ... },
  name = "summarize_data",
  # ...
)

# Tool 2: only uses the "n" input
ellmer::tool(
  fun = function(n = 100) { ... },
  name = "generate_sample",
  # ...
)
```

### Replacing `reactiveVal` / session state

MCP tool calls are stateless. If your Shiny app uses
[`reactiveVal()`](https://rdrr.io/pkg/shiny/man/reactiveVal.html) or
[`reactiveValues()`](https://rdrr.io/pkg/shiny/man/reactiveValues.html)
to accumulate state across interactions, you have two options:

1.  **Recompute from inputs**: Most filtering/selection state can be
    derived from the current input values alone.

2.  **Use the file system**: For truly stateful apps (e.g., a todo
    list), write state to a temp file and read it back on the next tool
    call.

### Tables

For `tableOutput`, return an HTML table string.
[`knitr::kable()`](https://rdrr.io/pkg/knitr/man/kable.html) is the
easiest approach:

``` r
fun = function(dataset = "mtcars") {
  data <- head(get(dataset, envir = asNamespace("datasets")), 10)
  list(
    my_table = knitr::kable(data, format = "html")
  )
}
```

Use `mcp_table("my_table")` in the UI. The bridge sets `innerHTML`
directly.

### Dynamic UI

MCP Apps don’t support
[`renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html) /
[`uiOutput()`](https://rdrr.io/pkg/shiny/man/htmlOutput.html). Instead:

- Use `mcp_html(id)` and return HTML strings from the tool
- For show/hide, return an empty string when the element should be
  hidden
- For dynamic choices, use a fixed
  [`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  and document valid values in the tool description

## Layout with bslib

Since MCP Apps use htmltools directly (not Shiny’s `fluidPage`), use
bslib for layout. Common patterns:

``` r
# Sidebar layout
page_sidebar(

  sidebar = sidebar(
    mcp_select("x", "Variable", choices),
    mcp_checkbox("log", "Log scale")
  ),
  card(mcp_plot("main_plot")),
  card(mcp_text("summary"))
)

# Multi-column layout
page(
  theme = bs_theme(preset = "shiny"),
  layout_columns(
    col_widths = c(6, 6),
    card(card_header("Plot"), mcp_plot("plot1")),
    card(card_header("Table"), mcp_table("table1"))
  )
)

# Stacked cards
page(
  card(card_header("Controls"), mcp_select("x", "Pick", c("a", "b"))),
  card(card_header("Output"), mcp_text("result"))
)
```

All CSS and JS dependencies from bslib are automatically inlined into
the MCP App’s HTML resource.

## What can’t be converted

Some Shiny features don’t have MCP App equivalents:

- **`fileInput`**: MCP Apps can’t receive file uploads. Use
  [`mcp_text_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_text_input.md)
  for file paths instead, or have the tool read from a known directory.
- **Shiny modules with internal state**: Flatten the module logic into
  top-level tools.
- **`invalidateLater` / polling**: MCP tools are request-response only.
  No background updates.
- **JavaScript-heavy widgets** (DT, plotly, leaflet): These require
  Shiny’s JS runtime. Use static alternatives (base R plots,
  [`knitr::kable`](https://rdrr.io/pkg/knitr/man/kable.html) tables).

## Full example

The complete converted penguins app is available at:

``` r
system.file("examples", "penguins", "app.R", package = "shinymcp")
```
