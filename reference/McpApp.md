# MCP App object

An `McpApp` bundles a user interface with the tools it calls. It knows
how to render itself as the self-contained HTML page an MCP host shows
(the app's `ui://` resource), how to describe its tools to a client, and
how to run them. Create one with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
or
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md)
rather than calling `McpApp$new()` directly; the arguments are the same.

Most code only needs `$call_tool()` (run a tool and get its R value
back, as in tests) and `$html_resource()` (the page a host renders).

## See also

Other apps:
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md),
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md),
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)

## Public fields

- `name`:

  App name; the UI resource is `ui://<name>`, with any characters a URI
  can't carry percent-encoded.

- `version`:

  App version string.

- `title`:

  Human-readable title, or `NULL`.

- `description`:

  What the app is for, or `NULL`.

## Methods

### Public methods

- [`McpApp$new()`](#method-McpApp-initialize)

- [`McpApp$html_resource()`](#method-McpApp-html_resource)

- [`McpApp$resource_uri()`](#method-McpApp-resource_uri)

- [`McpApp$resource_meta()`](#method-McpApp-resource_meta)

- [`McpApp$resources()`](#method-McpApp-resources)

- [`McpApp$read_resource()`](#method-McpApp-read_resource)

- [`McpApp$has_resource()`](#method-McpApp-has_resource)

- [`McpApp$tools()`](#method-McpApp-tools)

- [`McpApp$tool_definitions()`](#method-McpApp-tool_definitions)

- [`McpApp$call_tool()`](#method-McpApp-call_tool)

- [`McpApp$run_tool()`](#method-McpApp-run_tool)

- [`McpApp$has_tool()`](#method-McpApp-has_tool)

- [`McpApp$interaction_defaults()`](#method-McpApp-interaction_defaults)

- [`McpApp$runtime()`](#method-McpApp-runtime)

- [`McpApp$close()`](#method-McpApp-close)

- [`McpApp$output_types()`](#method-McpApp-output_types)

- [`McpApp$print()`](#method-McpApp-print)

- [`McpApp$clone()`](#method-McpApp-clone)

------------------------------------------------------------------------

### `McpApp$new()`

Create an app. See
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
for the arguments.

#### Usage

    McpApp$new(
      ui,
      tools = list(),
      name = "shinymcp-app",
      version = "0.1.0",
      title = NULL,
      description = NULL,
      theme = NULL,
      csp = NULL,
      permissions = NULL,
      prefers_border = NULL,
      domain = NULL,
      tool_visibility = NULL,
      tool_outputs = NULL,
      trigger = NULL,
      debounce_ms = NULL,
      resources = NULL,
      host_styles = TRUE,
      model_context = TRUE,
      images = TRUE,
      www = NULL,
      runtime = NULL
    )

#### Arguments

- `ui, tools, name, version, title, description, theme, csp, permissions, prefers_border, domain, tool_visibility, tool_outputs, trigger, debounce_ms, resources, host_styles, model_context, images, www`:

  See
  [`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md).

- `runtime`:

  Internal: the live Shiny runtime for apps created by
  [`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md)
  from a Shiny app.

------------------------------------------------------------------------

### `McpApp$html_resource()`

The HTML page an MCP host renders for this app. Dependencies (Bootstrap,
bslib components, htmlwidgets) are inlined so the page works under a
host's default Content Security Policy.

#### Usage

    McpApp$html_resource(config = NULL)

#### Arguments

- `config`:

  Named list merged into the bridge configuration. Hosts use it to pass
  their own settings; apps rarely need it.

------------------------------------------------------------------------

### `McpApp$resource_uri()`

The app's `ui://` resource URI.

#### Usage

    McpApp$resource_uri()

------------------------------------------------------------------------

### `McpApp$resource_meta()`

The `_meta` published with the app's `ui://` resource (CSP, permissions,
border preference), or `NULL`.

#### Usage

    McpApp$resource_meta()

------------------------------------------------------------------------

### `McpApp$resources()`

Resource records for `resources/list`: the app's UI and any extra
resources.

#### Usage

    McpApp$resources()

------------------------------------------------------------------------

### `McpApp$read_resource()`

Read one of the app's resources.

#### Usage

    McpApp$read_resource(uri)

#### Arguments

- `uri`:

  Resource URI.

#### Returns

A `resources/read` contents entry (`uri`, `mimeType`, `text`, optional
`_meta`).

------------------------------------------------------------------------

### `McpApp$has_resource()`

Does the app serve this resource URI?

#### Usage

    McpApp$has_resource(uri)

#### Arguments

- `uri`:

  Resource URI.

------------------------------------------------------------------------

### `McpApp$tools()`

The app's tools, normalized.

#### Usage

    McpApp$tools(audience = NULL)

#### Arguments

- `audience`:

  `NULL` for all tools, or `"model"` / `"app"` for the tools that
  audience may call.

------------------------------------------------------------------------

### `McpApp$tool_definitions()`

Tool definitions for an MCP `tools/list` response.

#### Usage

    McpApp$tool_definitions(include_ui_meta = TRUE, include_app_only = TRUE)

#### Arguments

- `include_ui_meta`:

  Include the nested `_meta.ui` block. `FALSE` for clients that did not
  declare MCP Apps support.

- `include_app_only`:

  Include tools only the app's UI can call.

------------------------------------------------------------------------

### `McpApp$call_tool()`

Run a tool and return its R value, as the tool function returned it.
Useful in tests.

#### Usage

    McpApp$call_tool(name, arguments = list(), context = list())

#### Arguments

- `name`:

  Tool name.

- `arguments`:

  Named list of arguments, as a client would send them. A vector of one
  value is one value; write an array of one as `list(x)`.

- `context`:

  Request context; see
  [`mcp_request()`](https://jameshwade.github.io/shinymcp/reference/mcp_request.md).

------------------------------------------------------------------------

### `McpApp$run_tool()`

Run a tool and return an MCP `tools/call` result.

#### Usage

    McpApp$run_tool(name, arguments = list(), context = list(), raw = FALSE)

#### Arguments

- `name`:

  Tool name.

- `arguments`:

  Named list of arguments, as a client would send them. A vector of one
  value is one value; write an array of one as `list(x)`.

- `context`:

  Request context. `caller = "app"` marks calls from the app's own UI,
  and `images = FALSE` asks for a result without image blocks for the
  model.

- `raw`:

  If `TRUE`, return a list with the `result` and the `raw` value the
  tool function returned (`NULL` if it failed).

------------------------------------------------------------------------

### `McpApp$has_tool()`

Does the app have a tool with this name?

#### Usage

    McpApp$has_tool(name)

#### Arguments

- `name`:

  Tool name.

------------------------------------------------------------------------

### `McpApp$interaction_defaults()`

The app's declared interaction defaults (`trigger`, `debounce_ms`), each
possibly `NULL`.

#### Usage

    McpApp$interaction_defaults()

------------------------------------------------------------------------

### `McpApp$runtime()`

The live Shiny runtime behind an app made from a Shiny app, or `NULL`.

#### Usage

    McpApp$runtime()

------------------------------------------------------------------------

### `McpApp$close()`

Close the app's open views and stop the Shiny app behind it, if any,
running its `onStop` hook.
[`serve()`](https://jameshwade.github.io/shinymcp/reference/serve.md)
and
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md)
call this when they stop.

#### Usage

    McpApp$close()

------------------------------------------------------------------------

### `McpApp$output_types()`

Output ids and types found in the UI.

#### Usage

    McpApp$output_types()

------------------------------------------------------------------------

### `McpApp$print()`

Print a summary.

#### Usage

    McpApp$print(...)

#### Arguments

- `...`:

  Ignored.

------------------------------------------------------------------------

### `McpApp$clone()`

The objects of this class are cloneable with this method.

#### Usage

    McpApp$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
