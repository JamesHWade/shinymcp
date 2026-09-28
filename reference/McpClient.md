# A client for a remote MCP server

Made by
[`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md).
The methods below block until the server answers and raise an error of
class `shinymcp_error_client` when it reports one. Each has an `_async`
variant that returns a promise instead, for use in Shiny.

## Public fields

- `url`:

  The server's endpoint.

- `name`:

  The name hosts know the server by.

- `timeout`:

  Seconds to wait for each response.

## Methods

### Public methods

- [`McpClient$new()`](#method-McpClient-initialize)

- [`McpClient$tools()`](#method-McpClient-tools)

- [`McpClient$call_tool()`](#method-McpClient-call_tool)

- [`McpClient$read_resource()`](#method-McpClient-read_resource)

- [`McpClient$request()`](#method-McpClient-request)

- [`McpClient$send()`](#method-McpClient-send)

- [`McpClient$tools_async()`](#method-McpClient-tools_async)

- [`McpClient$call_tool_async()`](#method-McpClient-call_tool_async)

- [`McpClient$read_resource_async()`](#method-McpClient-read_resource_async)

- [`McpClient$request_async()`](#method-McpClient-request_async)

- [`McpClient$send_async()`](#method-McpClient-send_async)

- [`McpClient$protocol_version()`](#method-McpClient-protocol_version)

- [`McpClient$server_info()`](#method-McpClient-server_info)

- [`McpClient$close()`](#method-McpClient-close)

- [`McpClient$print()`](#method-McpClient-print)

------------------------------------------------------------------------

### `McpClient$new()`

Create a client. Use
[`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md).

#### Usage

    McpClient$new(url, headers = NULL, name = NULL, timeout = 60, transport = NULL)

#### Arguments

- `url, headers, name, timeout`:

  See
  [`mcp_client()`](https://jameshwade.github.io/shinymcp/reference/mcp_client.md).

- `transport`:

  For tests: a function taking a request (a list with `method`, `url`,
  `headers`, `body`, and the JSON-RPC `id`), `async`, and `timeout`, and
  returning a response (`status`, `headers`, `body`) or a promise of
  one.

------------------------------------------------------------------------

### `McpClient$tools()`

The server's tools, from `tools/list`, with their `_meta`. The list is
kept for as long as the server says it may be, or a minute.

#### Usage

    McpClient$tools(refresh = FALSE, wait = TRUE)

#### Arguments

- `refresh`:

  Read the list again even if it is kept.

- `wait`:

  `FALSE` to return the last list the client got, however old, without
  asking the server: `NULL` if it has none.

------------------------------------------------------------------------

### `McpClient$call_tool()`

Call a tool.

#### Usage

    McpClient$call_tool(name, arguments = NULL)

#### Arguments

- `name`:

  Tool name.

- `arguments`:

  Named list of arguments, sent as JSON. A vector of one value goes as
  one value; write an array of one as `list(x)`.

#### Returns

The `tools/call` result: a list with `content`, and possibly
`structuredContent`, `_meta`, and `isError`.

------------------------------------------------------------------------

### `McpClient$read_resource()`

Read a resource, such as an app's `ui://` page.

#### Usage

    McpClient$read_resource(uri)

#### Arguments

- `uri`:

  Resource URI.

#### Returns

The `resources/read` result, a list with `contents`.

------------------------------------------------------------------------

### `McpClient$request()`

Send any request and return its result.

#### Usage

    McpClient$request(method, params = NULL)

#### Arguments

- `method`:

  JSON-RPC method.

- `params`:

  Named list of parameters.

------------------------------------------------------------------------

### `McpClient$send()`

Send a JSON-RPC request and return the whole response, errors included,
with the request's own id. Hosts use this to pass an app's requests on.

#### Usage

    McpClient$send(message)

#### Arguments

- `message`:

  A JSON-RPC request (a list).

------------------------------------------------------------------------

### `McpClient$tools_async()`

`tools()`, returning a promise.

#### Usage

    McpClient$tools_async(refresh = FALSE)

#### Arguments

- `refresh`:

  Read the list again even if it is kept.

------------------------------------------------------------------------

### `McpClient$call_tool_async()`

`call_tool()`, returning a promise.

#### Usage

    McpClient$call_tool_async(name, arguments = NULL)

#### Arguments

- `name`:

  Tool name.

- `arguments`:

  Named list of arguments.

------------------------------------------------------------------------

### `McpClient$read_resource_async()`

`read_resource()`, returning a promise.

#### Usage

    McpClient$read_resource_async(uri)

#### Arguments

- `uri`:

  Resource URI.

------------------------------------------------------------------------

### `McpClient$request_async()`

`request()`, returning a promise.

#### Usage

    McpClient$request_async(method, params = NULL)

#### Arguments

- `method`:

  JSON-RPC method.

- `params`:

  Named list of parameters.

------------------------------------------------------------------------

### `McpClient$send_async()`

`send()`, returning a promise.

#### Usage

    McpClient$send_async(message)

#### Arguments

- `message`:

  A JSON-RPC request (a list).

------------------------------------------------------------------------

### `McpClient$protocol_version()`

The protocol version in use, or `NULL` before the first request.

#### Usage

    McpClient$protocol_version()

------------------------------------------------------------------------

### `McpClient$server_info()`

What the server said about itself (`name`, `version`), or `NULL` before
the first request.

#### Usage

    McpClient$server_info()

------------------------------------------------------------------------

### `McpClient$close()`

End the session, for servers that keep one. The next request starts a
new one.

#### Usage

    McpClient$close()

------------------------------------------------------------------------

### `McpClient$print()`

Print a summary.

#### Usage

    McpClient$print(...)

#### Arguments

- `...`:

  Ignored.
