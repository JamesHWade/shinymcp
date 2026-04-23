# Package index

## Create MCP Apps

Build and serve MCP Apps from UI components and tools.

- [`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
  : Create an MCP App
- [`McpApp`](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  : MCP App
- [`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md)
  : Convert an object to an MCP App
- [`as_mcp_apps()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_apps.md)
  : Split a parsed Shiny app into chat-sized MCP App scaffolds
- [`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
  : Mark a Shiny UI element for MCP exposure
- [`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)
  : Create an MCP App from a Shiny module
- [`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md)
  : Serve an MCP App
- [`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md)
  : Preview an MCP App in a web browser

## Shinychat and Hosting

Embed MCP Apps in Shiny and shinychat, and return typed rich results.

- [`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
  : Wrap an McpApp as an ellmer tool for shinychat
- [`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/mcp_content_result.md)
  : Build a shinychat-friendly tool result with a live embedded card
- [`mcp_embed()`](https://jameshwade.github.io/shinymcp/reference/mcp_embed.md)
  : Embed an MCP app inside a live Shiny session
- [`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_server.md)
  : Host shell server for an embedded MCP app
- [`mcp_host_ui()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)
  : Host shell UI for an embedded MCP app
- [`mcp_result_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_html.md)
  : Build a typed HTML result
- [`mcp_result_image()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_image.md)
  : Build a typed image result
- [`mcp_result_pdf()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_pdf.md)
  : Build a typed PDF result
- [`mcp_result_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_plot.md)
  : Build a typed plot result
- [`mcp_result_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_table.md)
  : Build a typed table result
- [`mcp_result_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_text.md)
  : Build a typed text result
- [`mcp_result_widget()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_widget.md)
  : Build a typed widget result

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
- [`mcp_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_input.md)
  : Mark an element as an MCP input

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
- [`mcp_output()`](https://jameshwade.github.io/shinymcp/reference/mcp_output.md)
  : Mark an element as an MCP output

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
