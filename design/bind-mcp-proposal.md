# Design Proposal: `bindMcp()` Pipe Operator

**Origin**: Barrett Schloerke's suggestion to expose Shiny inputs/reactives/outputs
as MCP endpoints via a simple pipe: `|> bindMcp()`.

**Goal**: A Shiny app author writes ONE app that works both as a regular Shiny app
and as an MCP App, with minimal annotation.

## The Problem

Today, shinymcp offers two paths:

1. **Write MCP-native apps** using `mcp_select()`, `mcp_plot()`, and `ellmer::tool()`.
   Clean, but requires learning a new API and rewriting existing apps.

2. **Auto-convert** via `convert_app(path)` which parses → analyzes → generates
   a separate MCP app. Produces code-generated stubs that require manual editing.

Neither path lets you keep your existing Shiny app and _also_ serve it as MCP.

## The Vision

```r
library(shiny)
library(shinymcp)

ui <- fluidPage(
  selectInput("dataset", "Choose", c("mtcars", "iris")) |> bindMcp(),
  numericInput("n", "Rows", 10),            # <-- NOT exposed to MCP
  plotOutput("plot") |> bindMcp(),
  textOutput("summary") |> bindMcp()
)

server <- function(input, output, session) {
  output$plot <- renderPlot({
    plot(get(input$dataset))
  })
  output$summary <- renderText({
    paste("Rows:", nrow(get(input$dataset)))
  })
}

# Serve as a regular Shiny app:
shinyApp(ui, server)

# OR serve as an MCP App:
shinyApp(ui, server) |> as_mcp_app() |> serve()
```

Three levels of ergonomics, matching Barrett's sketch:

| Syntax | Scope | What it does |
|--------|-------|-------------|
| `selectInput(...) \|> bindMcp()` | Per-element | Marks one input/output for MCP exposure |
| `shinyApp(ui, server) \|> as_mcp_app()` | Whole-app | Converts an entire shinyApp to McpApp |
| `options(shinymcp.enabled = TRUE)` | Global flag | Any shinyApp auto-exposes an MCP endpoint |

## Design: Three Rounds

### Round 1 — `bindMcp()` for UI + `as_mcp_app()` (ergonomic layer)

The smallest useful increment. No new runtime magic, just better DX on top of
existing infrastructure.

#### `bindMcp()` — generic pipe for UI tags

```r
#' @export
bindMcp <- function(tag, id = NULL, type = NULL, description = NULL, ...) {
  UseMethod("bindMcp")
}

#' @export
bindMcp.shiny.tag <- function(tag, id = NULL, type = NULL, description = NULL, ...) {
  detected <- detect_mcp_role(tag)

  if (detected$role == "input") {
    mcp_input(tag, id = id %||% detected$id)
  } else if (detected$role == "output") {
    mcp_output(tag, id = id %||% detected$id, type = type %||% detected$type)
  } else {
    cli::cli_abort("Cannot determine MCP role for this element. Use {.arg type}.")
  }
}
```

**How `detect_mcp_role()` works**: Inspects the tag tree for known Shiny patterns:

| Pattern | Role | Type |
|---------|------|------|
| Tag contains `selectInput` structure (select element) | input | select |
| Tag contains `numericInput` structure (input[type=number]) | input | numeric |
| Tag has class `shiny-plot-output` | output | plot |
| Tag has class `shiny-text-output` | output | text |
| Tag has class `shiny-html-output` | output | html |
| Tag has class `datatables` | output | table |

This leverages the fact that Shiny's `*Input()` and `*Output()` functions produce
tags with predictable class names and structures.

**Key property**: `bindMcp()` is idempotent. Calling it on an already-annotated
element (or an `mcp_*()` component) is a no-op.

#### `as_mcp_app()` — convert shinyApp to McpApp

```r
#' @export
as_mcp_app <- function(x, ...) {
  UseMethod("as_mcp_app")
}

#' @export
as_mcp_app.shiny.appobj <- function(x, name = NULL, tools = NULL, ...) {
  # Extract UI and server from the shinyApp object
  ui <- x$ui
  server_fn <- x$serverFuncSource()

  # Option A: If tools are provided explicitly, use them
  if (!is.null(tools)) {
    return(mcp_app(ui = ui, tools = tools, name = name %||% "shinymcp-app"))
  }

  # Option B: Auto-generate tools from the parse → analyze pipeline
  # (operates on the UI tags + server function body, not files)
  ir <- parse_shiny_app_object(ui, body(server_fn))
  analysis <- analyze_reactive_graph(ir)
  tools <- generate_tools_from_analysis(analysis, ir)

  mcp_app(ui = ui, tools = tools, name = name %||% "shinymcp-app")
}
```

**New internal**: `parse_shiny_app_object(ui_tags, server_body)` — the existing
parser walks R files; this variant walks live tag objects and an already-parsed
server body expression. Most of the parser's `walk_exprs()` logic works unchanged
since it operates on AST, not evaluated objects.

**`bindMcp()` annotations are respected**: When `as_mcp_app()` encounters a UI tree,
elements with `data-shinymcp-input` or `data-shinymcp-output` attributes are
prioritized. Non-annotated elements can be included or excluded based on a
`selective = TRUE/FALSE` flag:

```r
# Only expose annotated elements (bindMcp'd ones)
shinyApp(ui, server) |> as_mcp_app(selective = TRUE)

# Expose everything (like convert_app)
shinyApp(ui, server) |> as_mcp_app(selective = FALSE)
```

#### What Round 1 does NOT do

- Tool handler functions still need explicit implementation (either provided
  via `tools = list(...)` or auto-generated as stubs with `# TODO` bodies).
- The server function's reactive graph is analyzed statically, but NOT executed.
- No headless Shiny runtime.

#### Round 1 deliverables

| File | What |
|------|------|
| `R/bind-mcp.R` | `bindMcp()` S3 generic + methods |
| `R/as-mcp-app.R` | `as_mcp_app()` S3 generic + `shiny.appobj` method |
| `R/detect.R` | `detect_mcp_role()` — tag introspection heuristics |
| `R/parse.R` (extend) | `parse_shiny_app_object()` for live tag/expr parsing |
| `tests/testthat/test-bind-mcp.R` | Tests for `bindMcp()` on all Shiny input/output types |
| `tests/testthat/test-as-mcp-app.R` | Tests for `as_mcp_app()` conversion |
| `inst/examples/bind-mcp-demo/` | Example showing `bindMcp()` annotations |

---

### Round 2 — Headless Shiny driver (the reactive bridge)

This is where `|> bindMcp()` becomes truly powerful. The Shiny server function
runs for real, and MCP tool calls drive it.

#### Core idea: MCP tools ↔ Shiny session

```
MCP tool call                    Shiny headless session
─────────────                    ──────────────────────
tools/call {                     session$setInputs(
  dataset: "iris"     ────►        dataset = "iris"
}                                )
                                 flush reactives
                                 ◄────
{ plot: base64(...),             capture output$plot, output$summary
  summary: "..." }
```

#### Implementation: `ShinyMcpDriver` R6 class

```r
ShinyMcpDriver <- R6::R6Class(
  "ShinyMcpDriver",
  public = list(
    initialize = function(app_dir_or_obj) {
      # Launch headless Shiny session using shinytest2::AppDriver
      # or shiny::testServer() infrastructure
      private$.session <- create_headless_session(app_dir_or_obj)
    },

    call_tool = function(name, arguments) {
      # 1. Map tool arguments to input IDs
      # 2. Set inputs on the headless session
      private$.session$setInputs(!!!arguments)

      # 3. Wait for reactive flush
      private$.session$waitForIdle()

      # 4. Capture outputs
      results <- list()
      for (output_id in private$.tool_outputs[[name]]) {
        results[[output_id]] <- private$.capture_output(output_id)
      }
      results
    },

    stop = function() {
      private$.session$stop()
    }
  )
)
```

#### Plot capture

For `renderPlot()` outputs, the driver:

1. Uses `shiny::plotPNG()` or captures the plot device to a temp PNG
2. Base64-encodes the result
3. Returns it in `structuredContent` under the output ID

This is the same pattern shinymcp's existing tools use, but automated.

#### Tool auto-generation

With the headless driver, tools are auto-generated with **working handlers**:

```r
generate_live_tool <- function(tool_group, driver) {
  input_ids <- vapply(tool_group$input_args, `[[`, character(1), "id")
  output_ids <- vapply(tool_group$output_targets, `[[`, character(1), "id")

  # Build the tool function dynamically
  tool_fn <- function(...) {
    args <- list(...)
    # Set inputs on the Shiny session
    driver$set_inputs(args)
    # Wait for reactives
    driver$wait_for_idle()
    # Capture outputs
    driver$capture_outputs(output_ids)
  }

  # Set proper formals from input metadata
  formals(tool_fn) <- make_formals(tool_group$input_args)

  ellmer::tool(
    fun = tool_fn,
    name = tool_group$name,
    description = tool_group$description,
    arguments = make_type_args(tool_group$input_args)
  )
}
```

#### Dependencies

Round 2 adds a soft dependency on `shinytest2` (or uses `shiny::testServer()`
which is in shiny itself). This stays in Suggests since it's only needed for
the headless driver path.

#### What Round 2 enables

```r
# This now "just works" — no explicit tool handlers needed
shinyApp(ui, server) |> as_mcp_app() |> serve()
```

The server function runs unmodified. All `input$*` → `output$*` flows are
preserved. Complex reactive chains, `reactive()`, `reactiveVal()`, `observe()` —
all work because it's a real Shiny session.

#### Round 2 deliverables

| File | What |
|------|------|
| `R/shiny-driver.R` | `ShinyMcpDriver` R6 class |
| `R/as-mcp-app.R` (extend) | `headless = TRUE` option for live tools |
| `R/capture.R` | Output capture utilities (plots, text, tables) |
| `tests/testthat/test-driver.R` | Tests for headless driver |

---

### Round 3 — Server-side `bindMcp()` + fine-grained control

The final piece: annotations on the server side, matching Barrett's full vision.

#### Server-side `bindMcp()`

```r
server <- function(input, output, session) {
  output$plot <- renderPlot({
    plot(get(input$dataset))
  }) |> bindMcp(
    tool = "explore",                    # explicit tool name
    description = "Dataset visualization",
    args = list(dataset = "Dataset to plot")
  )

  output$summary <- renderText({
    paste("Rows:", nrow(get(input$dataset)))
  }) |> bindMcp(tool = "explore")        # same tool group

  output$debug <- renderText({
    paste("Debug:", Sys.time())
  })
  # ^^^ NOT annotated — invisible to MCP
}
```

#### How it works

`bindMcp()` on a render function wraps it in a thin shim that:

1. Registers metadata in a session-level `McpRegistry` (a hidden reactive value)
2. Records which tool group this output belongs to
3. The actual render function is unmodified — Shiny runs it normally

At `as_mcp_app()` time, the registry is read to determine:
- Which outputs participate in MCP
- How outputs are grouped into tools
- Custom descriptions and argument specs

```r
#' @export
bindMcp.shiny.render.function <- function(x, tool = NULL, description = NULL,
                                          args = NULL, ...) {
  # Store MCP metadata as an attribute on the render function
  attr(x, "mcp_binding") <- list(
    tool = tool,
    description = description,
    args = args
  )
  x
}
```

#### Tool grouping rules

| Scenario | Behavior |
|----------|----------|
| Multiple outputs with same `tool = "name"` | Grouped into one tool |
| Output with no `tool` specified | Auto-grouped by connected component analysis |
| Output without `bindMcp()` | Excluded when `selective = TRUE` |

#### The `@shiny.mcp` decorator (future R syntax)

If R ever gets decorators (there's been discussion), the syntax could become:

```r
#' @shiny.mcp tool="explore"
output$plot <- renderPlot({ ... })
```

Until then, `|> bindMcp()` is the closest R idiom.

#### Round 3 deliverables

| File | What |
|------|------|
| `R/bind-mcp.R` (extend) | `bindMcp.shiny.render.function` method |
| `R/mcp-registry.R` | Session-level binding registry |
| `R/as-mcp-app.R` (extend) | Registry-aware tool generation |
| `tests/testthat/test-bind-mcp-server.R` | Server-side annotation tests |

---

## API Summary

After all three rounds, the full API surface:

```r
# UI-side annotation (Round 1)
selectInput("x", "X", choices) |> bindMcp()
plotOutput("plot") |> bindMcp()

# Server-side annotation (Round 3)
output$plot <- renderPlot({...}) |> bindMcp(tool = "explore")

# Whole-app conversion (Round 1 + Round 2)
shinyApp(ui, server) |> as_mcp_app() |> serve()

# Explicit tools still work (existing API, unchanged)
mcp_app(ui, tools, name = "app") |> serve()

# One-liner for simple apps (Round 2)
serve_mcp(shinyApp(ui, server))
```

## Key Design Decisions

### 1. `bindMcp()` is a pipe, not a wrapper

Barrett's insight: `|> bindMcp()` reads as "and also expose this via MCP."
It doesn't change the element's behavior — it adds a capability.

This is different from `mcp_select()` which _replaces_ `selectInput()`.
With `bindMcp()`, you keep the original Shiny function.

### 2. Headless Shiny session for tool execution

Rather than extracting reactive logic into standalone functions (which is
fragile and lossy), we run the actual Shiny server. This means:

- Complex reactive chains work
- `reactiveVal()`, `eventReactive()`, `observeEvent()` all work
- Session-scoped state (e.g., database connections) works
- Modules work

### 3. Selective vs. full exposure

`selective = TRUE` (default): Only `bindMcp()`-annotated elements are exposed.
`selective = FALSE`: Everything is exposed (like `convert_app()` today).

This gives app authors fine-grained control over what AI agents can see and do.

### 4. Backwards compatible

The existing API (`mcp_select()`, `mcp_app()`, `convert_app()`, etc.) is
unchanged. `bindMcp()` and `as_mcp_app()` are purely additive.

## Open Questions

1. **Should `as_mcp_app()` default to `selective = TRUE` or `FALSE`?**
   - `TRUE` is safer (opt-in exposure)
   - `FALSE` is more convenient (everything exposed by default)
   - Recommendation: `TRUE` if any `bindMcp()` annotations exist, `FALSE` otherwise

2. **How to handle stateful server patterns?**
   - `reactiveVal()` with `observeEvent()` accumulates state across tool calls
   - Should each tool call get a fresh session or reuse one?
   - Recommendation: One persistent session per MCP connection, reset on teardown

3. **Module support?**
   - Shiny modules namespace their inputs/outputs (`ns("plot")` → `"module1-plot"`)
   - `bindMcp()` inside a module would need to respect namespacing
   - Recommendation: Defer to Round 3, use `session$ns()` to resolve IDs

4. **Performance of headless sessions?**
   - Each MCP connection spawns a Shiny session
   - For plot-heavy apps, this could be slow
   - Recommendation: Lazy session creation, session pooling for HTTP transport

## Suggested Starting Point

Round 1 is self-contained and delivers immediate value:
- `bindMcp()` on UI elements (simple tag manipulation)
- `as_mcp_app()` for shinyApp objects (reuses existing parse/analyze pipeline)
- New example app demonstrating the pattern
- No new runtime complexity

Round 2 (headless driver) is the high-impact feature that makes the dream
API work. It should be designed in parallel with Round 1 but can ship
separately.
