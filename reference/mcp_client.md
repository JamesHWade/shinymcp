# Connect to a remote MCP server

`mcp_client()` connects to an MCP server over Streamable HTTP, so a
Shiny app can host the server's apps with
[`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)
and
[`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md).
Any server works: an app deployed with
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md),
a Shiny app served by Shiny's own MCP support, or a server written in
another language.

The client speaks both generations of the protocol: the stateless
2026-07-28 revision, and the `initialize` handshake of 2025-11-25 and
earlier. It tells the server it can show MCP Apps, and it keeps the
`_meta` of every result, which is where an app's page is declared.

Nothing is sent until the client is first used.

## Usage

``` r
mcp_client(url, headers = NULL, name = NULL, timeout = 60)
```

## Arguments

- url:

  The server's MCP endpoint, such as
  `"https://connect.example.com/sales/mcp"`.

- headers:

  Headers to send with every request, such as `Authorization`: a named
  list, or a function that returns one.

- name:

  A name for the server, unique among the sources a Shiny app hosts.
  Saved conversations refer to the server's apps by this name, so keep
  it stable. Defaults to the URL's host and path.

- timeout:

  Seconds to wait for each response. Apps that poll their server, as
  Shiny apps can, need this to be longer than their polls.

## Value

An
[McpClient](https://jameshwade.github.io/shinymcp/reference/McpClient.md).

## Credentials

`headers` can be a function, called before each request. To send each
visitor's own credentials, create the client in the Shiny server
function, where the function can read the visitor's session. A client
created outside it is shared by every session, along with its connection
and the tool list it has read.

Headers go wherever `url` points, so use `https://` for anything secret.

## See also

Other hosting:
[`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md),
[`mcp_chat_host()`](https://jameshwade.github.io/shinymcp/reference/mcp_chat_host.md),
[`mcp_host_ui()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)

## Examples

``` r
if (FALSE) { # \dontrun{
client <- mcp_client(
  "https://connect.example.com/sales/mcp",
  headers = list(Authorization = paste("Key", Sys.getenv("CONNECT_API_KEY")))
)
client$tools()
client$call_tool("open_sales_app", list(region = "West"))
} # }
```
