# Package index

## Create MCP Apps

Build and serve MCP Apps from UI components and tools.

- [`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
  : Create an MCP App
- [`McpApp`](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  : MCP App
- [`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md)
  : Serve an MCP App
- [`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md)
  : Preview an MCP App in a web browser

## Input Components

Interactive inputs that mirror Shiny’s API. Values are sent to tools
when the user interacts with them.

- [`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  : Create an MCP select input
- [`mcp_text_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_text_input.md)
  : Create an MCP text input
- [`mcp_numeric_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_numeric_input.md)
  : Create an MCP numeric input
- [`mcp_checkbox()`](https://jameshwade.github.io/shinymcp/reference/mcp_checkbox.md)
  : Create an MCP checkbox input
- [`mcp_slider()`](https://jameshwade.github.io/shinymcp/reference/mcp_slider.md)
  : Create an MCP slider input
- [`mcp_radio()`](https://jameshwade.github.io/shinymcp/reference/mcp_radio.md)
  : Create MCP radio button inputs
- [`mcp_action_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_action_button.md)
  : Create an MCP action button

## Output Components

Placeholders populated by tool results. The JS bridge routes values to
outputs based on matching IDs.

- [`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_text.md)
  : Create an MCP text output
- [`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)
  : Create an MCP plot output
- [`mcp_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_table.md)
  : Create an MCP table output
- [`mcp_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_html.md)
  : Create an MCP HTML output

## Conversion Pipeline

Parse, analyze, and generate MCP Apps from existing Shiny apps.

- [`convert_app()`](https://jameshwade.github.io/shinymcp/reference/convert_app.md)
  : Convert a Shiny app to an MCP App
- [`parse_shiny_app()`](https://jameshwade.github.io/shinymcp/reference/parse_shiny_app.md)
  : Parse a Shiny app into intermediate representation
- [`analyze_reactive_graph()`](https://jameshwade.github.io/shinymcp/reference/analyze_reactive_graph.md)
  : Analyze reactive graph from parsed Shiny app
- [`generate_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/generate_mcp_app.md)
  : Generate MCP App from analysis
- [`print(`*`<ReactiveAnalysis>`*`)`](https://jameshwade.github.io/shinymcp/reference/print.ReactiveAnalysis.md)
  : Print method for ReactiveAnalysis
- [`print(`*`<ShinyAppIR>`*`)`](https://jameshwade.github.io/shinymcp/reference/print.ShinyAppIR.md)
  : Print method for ShinyAppIR

## Bridge Helpers

Internal helpers for the JS bridge configuration.

- [`bridge_config_tag()`](https://jameshwade.github.io/shinymcp/reference/bridge_config_tag.md)
  : Bridge config tag
- [`bridge_script_tag()`](https://jameshwade.github.io/shinymcp/reference/bridge_script_tag.md)
  : Bridge script tag

## Package

- [`shinymcp`](https://jameshwade.github.io/shinymcp/reference/shinymcp-package.md)
  [`shinymcp-package`](https://jameshwade.github.io/shinymcp/reference/shinymcp-package.md)
  : shinymcp: Convert Shiny Apps to MCP Apps
