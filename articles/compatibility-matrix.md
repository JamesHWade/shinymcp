# Compatibility matrix

## Host matrix

| Host                                                                              | Status        | Notes                                                                                                                                                                                                                          |
|-----------------------------------------------------------------------------------|---------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md) | Available now | Uses the extracted host controller locally in a browser preview.                                                                                                                                                               |
| Standards-based MCP host                                                          | Available now | `McpApp` still emits `_meta.ui.resourceUri` and serves `ui://` resources.                                                                                                                                                      |
| shinychat embedding                                                               | Available now | Use [`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md), [`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/mcp_content_result.md), or the host shell helpers. |
| shinychat native `ui://` support                                                  | Future        | The current adapter stays thin so it can collapse toward native support later.                                                                                                                                                 |

## Output fallback matrix

| Result helper                                                                                 | MCP / preview     | shinychat                     | Plain fallback        |
|-----------------------------------------------------------------------------------------------|-------------------|-------------------------------|-----------------------|
| [`mcp_result_text()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_text.md)     | text patch        | tool-card text                | text                  |
| [`mcp_result_html()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_html.md)     | HTML patch        | rich HTML card                | text/HTML string      |
| [`mcp_result_table()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_table.md)   | table HTML patch  | rich HTML card                | printed table summary |
| [`mcp_result_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_plot.md)     | base64 plot patch | embedded card or text summary | text summary          |
| [`mcp_result_image()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_image.md)   | image/plot patch  | embedded card or image HTML   | text summary          |
| [`mcp_result_pdf()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_pdf.md)       | HTML fallback     | link-like HTML fallback       | text summary          |
| [`mcp_result_widget()`](https://jameshwade.github.io/shinymcp/reference/mcp_result_widget.md) | HTML patch        | rich HTML card                | text summary          |

## Migration modes

| Mode                                 | Current status | Intended use                                           |
|--------------------------------------|----------------|--------------------------------------------------------|
| Authored runtime card                | Supported      | Primary path for production usage today                |
| Wrapped module with explicit handler | Supported      | Reuse bounded Shiny logic                              |
| `convert_app(mode = "cards")`        | Scaffold       | Split connected groups into chat-sized starting points |
| `convert_app(mode = "scaffold")`     | Scaffold       | Full-app starting point for manual completion          |
| Headless subset execution            | Future         | Capability-detected bounded subset only                |
