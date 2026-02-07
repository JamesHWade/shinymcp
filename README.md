
<!-- README.md is generated from README.Rmd. Please edit that file -->

# shinymcp

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

shinymcp converts [Shiny](https://shiny.posit.co/) apps into [MCP
Apps](https://modelcontextprotocol.io/) — interactive UIs that render
directly inside AI chat interfaces like Claude, ChatGPT, and VS Code
Copilot.

It provides:

- A **parse-analyze-generate** pipeline that automatically converts
  Shiny apps to MCP Apps
- **MCP-compatible UI components** (`mcp_select()`, `mcp_text_input()`,
  `mcp_plot()`, etc.) that mirror Shiny’s input/output API
- A **self-contained JS bridge** that implements the MCP Apps
  postMessage protocol
- An **MCP server** that serves tools and `ui://` resources over stdio
  or HTTP

## Installation

You can install the development version of shinymcp from
[GitHub](https://github.com/) with:

``` r
# install.packages("pak")
pak::pak("jameslairdsmith/shinymcp")
```

## Usage

### Build an MCP App from scratch

Create an MCP App by defining UI components and tools:

``` r
library(shinymcp)

ui <- htmltools::tagList(
  mcp_select("dataset", "Choose dataset", c("mtcars", "iris", "pressure")),
  mcp_text("summary")
)

tools <- list(
  ellmer::tool(
    fun = function(dataset = "mtcars") {
      data <- get(dataset, envir = asNamespace("datasets"))
      paste(capture.output(summary(data)), collapse = "\n")
    },
    name = "get_summary",
    description = "Get summary statistics for the selected dataset",
    arguments = list(
      dataset = ellmer::type_string("Dataset name")
    )
  )
)

app <- mcp_app(ui, tools, name = "hello-mcp")
serve(app)
```

### Convert an existing Shiny app

Point `convert_app()` at a Shiny app directory and it will generate an
equivalent MCP App:

``` r
convert_app("path/to/my-shiny-app")
```

This parses the app’s UI and server code, groups connected reactive
chains into tool definitions, and writes the output to a new directory.

### UI components

shinymcp provides input and output components that mirror familiar Shiny
functions:

``` r
library(shinymcp)

# Inputs
mcp_select("colour", "Colour", c("red", "green", "blue"))
```

<div class="shinymcp-input-group">
<label for="colour">Colour</label>
<select id="colour" data-shinymcp-input="colour" data-shinymcp-type="select">
<option value="red" selected>red</option>
<option value="green">green</option>
<option value="blue">blue</option>
</select>
</div>

``` r
mcp_numeric_input("n", "Count", value = 10, min = 1, max = 100)
```

<div class="shinymcp-input-group">
<label for="n">Count</label>
<input type="number" id="n" data-shinymcp-input="n" data-shinymcp-type="numeric" value="10" min="1" max="100"/>
</div>

``` r

# Outputs
mcp_plot("my_plot")
```

<div id="my_plot" class="shinymcp-output" data-shinymcp-output="my_plot" data-shinymcp-output-type="plot" style="width: 100%; height: 400px;"></div>

``` r
mcp_text("result")
```

<div id="result" class="shinymcp-output" data-shinymcp-output="result" data-shinymcp-output-type="text"></div>

Each component generates standard HTML with `data-shinymcp-*` attributes
that the JS bridge reads at runtime.

### Serve as an MCP server

`serve()` starts an MCP server that exposes your app’s tools and HTML UI
as a `ui://` resource:

``` r
app <- mcp_app(ui, tools, name = "my-app")

# Stdio transport (for Claude Desktop, VS Code, etc.)
serve(app, type = "stdio")

# HTTP transport (for development/testing)
serve(app, type = "http", port = 8080)
```

## How it works

MCP Apps use sandboxed iframes and postMessage/JSON-RPC to communicate
between the AI host and your app’s UI. shinymcp replaces Shiny’s
JavaScript runtime (`shiny.js`) with a lightweight bridge that:

1.  Collects input values from MCP components on user interaction
2.  Calls server-side tools via JSON-RPC
3.  Updates output elements with the tool results

The conversion pipeline works in three stages:

1.  **Parse** — Walk the Shiny app’s AST to extract inputs, outputs,
    reactive expressions, and observers
2.  **Analyze** — Build a dependency graph and group connected
    components into tool clusters
3.  **Generate** — Emit MCP-compatible HTML, tool definitions, and a
    server entrypoint

## Related packages

- [ellmer](https://ellmer.tidyverse.org/) — LLM framework that shinymcp
  uses for tool definitions
- [mcptools](https://github.com/posit-dev/mcptools) — MCP server
  framework (shinymcp extends this with resource support)
- [deputy](https://github.com/jameslairdsmith/deputy) — Agentic AI
  framework with a bundled skill for AI-assisted Shiny conversion
