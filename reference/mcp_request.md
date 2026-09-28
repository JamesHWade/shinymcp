# Information about the MCP request being handled

Call `mcp_request()` inside a tool function, or inside the server
function of a Shiny app served with
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
to learn who is calling and how. Outside a request it returns `NULL`.

## Usage

``` r
mcp_request()
```

## Value

A list, or `NULL` outside a request.

## Details

The fields are:

- `caller`: `"model"` when the model called the tool, `"app"` when the
  app's own UI did. Hosts don't report this, so the UI marks its own
  calls; treat it as a hint, not a security boundary.

- `user`, `groups`: the signed-in user and their groups when the server
  runs on Posit Connect, otherwise `NULL`.

- `client`: the client's name and version, when it reported them.

- `protocol_version`: the MCP protocol version of the request.

- `transport`: `"stdio"`, `"http"`, or `"in-process"`.

- `headers`: HTTP request headers (lowercase names), for the HTTP
  transport.

## See also

Other writing tools:
[`mcp_result`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md),
[`mcp_tool_result()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_result.md)

## Examples

``` r
greet <- function(name = "world") {
  who <- mcp_request()$user
  if (is.null(who)) who <- "someone"
  paste0("Hello, ", name, "! (asked by ", who, ")")
}
```
