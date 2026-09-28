# Package index

## Make an app

- [`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
  : Create an MCP App
- [`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)
  : Serve a Shiny module as an MCP App
- [`McpApp`](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  : MCP App object

## UI

- [`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  [`mcp_text_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  [`mcp_numeric_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  [`mcp_checkbox()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  [`mcp_slider()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  [`mcp_radio()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  [`mcp_action_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  : Inputs for apps built from tools
- [`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)
  [`mcp_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)
  [`mcp_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)
  [`mcp_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md)
  : Output placeholders for tool results
- [`mcp_submit_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_submit_button.md)
  : An apply button for apps that wait for it
- [`mcp_input()`](https://jameshwade.github.io/shinymcp/reference/mcp_input.md)
  : Mark an element as an input of an app's tools
- [`mcp_output()`](https://jameshwade.github.io/shinymcp/reference/mcp_output.md)
  : Mark an element as an output of an app's tools

## Tools and their results

- [`mcp_result_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
  [`mcp_result_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
  [`mcp_result_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
  [`mcp_result_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
  [`mcp_result_image()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
  [`mcp_result_pdf()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
  [`mcp_result_widget()`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
  : Typed output values for tool results
- [`mcp_tool_result()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_result.md)
  : Set a tool result's text and data explicitly
- [`mcp_request()`](https://jameshwade.github.io/shinymcp/reference/mcp_request.md)
  : Information about the MCP request being handled

## Run it

- [`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md)
  : Serve MCP Apps to an MCP client
- [`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md)
  : Add an MCP endpoint to a Shiny app
- [`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md)
  : Preview an MCP App in a browser
- [`shinymcp-options`](https://jameshwade.github.io/shinymcp/reference/shinymcp-options.md)
  : Options

## Host apps in Shiny

Show MCP Apps, from this process or any MCP server, in a shinychat
conversation or a pane of a Shiny app.

- [`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md)
  : Host MCP Apps in a shinychat conversation
- [`mcp_host_ui()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)
  [`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)
  [`mcp_embed()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)
  : Host an MCP App in a Shiny app
- [`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
  [`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md)
  : Use an MCP App's tools in a shinychat conversation
- [`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md)
  : Connect to a remote MCP server
- [`McpClient`](https://jameshwade.github.io/shinymcp/reference/McpClient.md)
  : A client for a remote MCP server

## Serving a Shiny app as it is

For serving an existing Shiny app live, until Shiny’s own MCP support is
released. Outside an MCP App, the helpers for server functions do
nothing, so the app still runs as usual.

- [`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md)
  : Serve a Shiny app as an MCP App
- [`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md)
  : Choose what the model sees of a Shiny app
- [`mcp_model_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md)
  [`mcp_send_message()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md)
  [`is_mcp_session()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md)
  : Talk to the model from a Shiny app served with shinymcp
- [`mcp_host_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_context.md)
  : The chat client around a Shiny app served with shinymcp

## Pages built by hand

- [`bridge_script_tag()`](https://jameshwade.github.io/shinymcp/reference/bridge_script_tag.md)
  [`bridge_config_tag()`](https://jameshwade.github.io/shinymcp/reference/bridge_script_tag.md)
  : The bridge script as an HTML tag
