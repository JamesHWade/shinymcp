# CLAUDE.md

This file provides guidance for AI assistants working with the shinymcp
codebase.

## Project Overview

**shinymcp** is an R package that converts Shiny apps into MCP (Model
Context Protocol) Apps. MCP Apps render inside AI chat interfaces
(Claude, ChatGPT, VS Code) using `ui://` resources, sandboxed iframes,
and postMessage/JSON-RPC communication.

Key capabilities: - **Parse → Analyze → Generate** pipeline for
automatic Shiny-to-MCP conversion - MCP-compatible UI components
([`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md),
[`mcp_text_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_text_input.md),
[`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md),
etc.) - Self-contained JS bridge for the MCP Apps postMessage/JSON-RPC
protocol - McpApp R6 runtime class bundling UI + tools - Resource
protocol handler for `ui://` resources - MCP server supporting stdio and
HTTP transports - Deputy skill for AI-assisted conversion of complex
apps

## Directory Structure

    shinymcp/
    ├── R/
    │   ├── shinymcp-package.R     # Package-level docs
    │   ├── parse.R                # Shiny app AST parser → ShinyAppIR
    │   ├── analyze.R              # Reactive graph → tool group clusters
    │   ├── generate.R             # Code generator (HTML + tools.R + server.R)
    │   ├── convert.R              # Top-level convert_app() entry point
    │   ├── mcp-app.R              # McpApp R6 class (runtime)
    │   ├── components-input.R     # mcp_select(), mcp_text_input(), mcp_input(), mcp_output()
    │   ├── components-output.R    # mcp_plot(), mcp_text(), mcp_table()
    │   ├── js-bridge.R            # JS bridge config generation + injection
    │   ├── serve.R                # MCP server with tools + ui:// resources
    │   ├── mcp-resources.R        # Resource protocol handler
    │   ├── utils.R                # Internal utilities
    │   └── errors.R               # Custom error classes
    ├── inst/
    │   ├── js/shinymcp-bridge.js  # MCP Apps JS bridge (~300 lines)
    │   ├── templates/app.html     # HTML skeleton template
    │   ├── skills/                # Deputy skill for AI conversion
    │   └── examples/              # Example MCP Apps
    ├── tests/testthat/            # Unit tests (testthat edition 3)
    └── man/                       # Auto-generated roxygen2 docs

## Common Commands

### Testing

``` bash
Rscript -e "devtools::test()"
Rscript -e "testthat::test_file('tests/testthat/test-components.R')"
Rscript -e "devtools::test(filter = 'parse')"
```

### Code Quality

``` bash
Rscript -e "devtools::check()"
air format R/ tests/testthat/
Rscript -e "devtools::document()"
```

### Building

``` bash
Rscript -e "devtools::build()"
Rscript -e "devtools::install()"
```

## Code Conventions

- **Formatter**: Air (config in `air.toml`)
- **Documentation**: roxygen2 with markdown support
- **Classes**: R6 for McpApp, ResourceRegistry
- **Errors**: Custom error classes via
  [`rlang::abort()`](https://rlang.r-lib.org/reference/abort.html) (see
  `R/errors.R`)
- **Style**: tidyverse conventions, `%||%` operator from rlang

### Input Binding

The JS bridge auto-detects inputs by matching tool argument names to DOM
element `id` attributes. This means native
[`shiny::selectInput()`](https://rdrr.io/pkg/shiny/man/selectInput.html),
[`shiny::numericInput()`](https://rdrr.io/pkg/shiny/man/numericInput.html),
etc. work without wrappers — as long as the element’s `id` matches a
tool argument name.

Resolution priority (in `resolveInputElement()`): 1. Explicit
`data-shinymcp-input="{id}"` attribute (backward compat,
[`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
etc.) 2. Standard form elements by id: `select#id`, `input#id`,
`textarea#id`, `button#id` 3. Container with `id` holding radio inputs
(radio group pattern)

The `mcp_*()` input components
([`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md),
[`mcp_text_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_text_input.md),
etc.) still work and are used by the conversion pipeline.
`mcp_input(tag)` and `mcp_output(tag)` are escape hatches for stamping
`data-shinymcp-*` attributes on arbitrary tags.

### UI Components Pattern

Components generate `htmltools` tags with `data-shinymcp-*`
attributes: - Inputs: `data-shinymcp-input="{id}"`,
`data-shinymcp-type="{type}"` - Outputs: `data-shinymcp-output="{id}"`,
`data-shinymcp-output-type="{type}"`

### Conversion Pipeline

1.  `parse_shiny_app(path)` → `ShinyAppIR` (AST walking)
2.  `analyze_reactive_graph(ir)` → `ReactiveAnalysis` (dependency graph)
3.  `generate_mcp_app(analysis, ir, output_dir)` → files on disk
4.  `convert_app(path)` → orchestrates the full pipeline

## Architecture

### MCP Apps Protocol

MCP Apps use: - `ui://` resource URIs to declare HTML content -
`text/html;profile=mcp-app` MIME type - postMessage/JSON-RPC for host ↔︎
iframe communication - Tool annotations with `_meta.ui.resourceUri` to
link tools to their UI

### JS Bridge

The self-contained bridge (`inst/js/shinymcp-bridge.js`): - Reads config
(including `toolArgs`) from `<script id="shinymcp-config">` element -
Builds input cache by matching tool arg names to DOM elements
(`buildInputCache()`) - Listens for input changes → sends
`ui/update-model-context` and debounced `tools/call` to host - Receives
`ui/tool-result` → updates DOM output elements via `structuredContent`
keys - Reports size changes via ResizeObserver - Handles teardown
cleanup - ES5-compatible (no const/let/arrow functions/Set), includes
CSS.escape polyfill

### Key Design Decisions

1.  **htmltools, not Shiny runtime** - No dependency on Shiny’s JS. The
    JS bridge replaces shiny.js entirely.
2.  **Auto-detect inputs** - The bridge matches tool argument names to
    DOM element ids, so native shiny/bslib inputs work without wrappers.
    `mcp_*()` components and `data-shinymcp-input` attributes remain as
    explicit overrides.
3.  **One tool per reactive group** - Connected inputs/reactives/outputs
    map to a single tool.
4.  **Self-contained JS** - No npm build step. Vanilla ES5 JS in an
    IIFE.
5.  **mcptools extension path** - Resource handling in `mcp-resources.R`
    is designed for eventual upstream PR.

## Dependencies

**Core** (Imports): R6, htmltools, jsonlite, cli, rlang **Optional**
(Suggests): ellmer, mcptools, shiny, base64enc, httpuv, testthat,
deputy, knitr
