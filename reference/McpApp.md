# MCP App

MCP App

MCP App

## Details

An R6 class that bundles UI components and tools into a servable MCP
App. The app generates HTML with an embedded JS bridge and provides
tools annotated with resource URIs for MCP consumption.

## Public fields

- `name`:

  App name

- `version`:

  App version

## Methods

### Public methods

- [`McpApp$new()`](#method-McpApp-new)

- [`McpApp$html_resource()`](#method-McpApp-html_resource)

- [`McpApp$mcp_tools()`](#method-McpApp-mcp_tools)

- [`McpApp$tool_definitions()`](#method-McpApp-tool_definitions)

- [`McpApp$extra_resources()`](#method-McpApp-extra_resources)

- [`McpApp$read_extra_resource()`](#method-McpApp-read_extra_resource)

- [`McpApp$resource_meta()`](#method-McpApp-resource_meta)

- [`McpApp$call_tool()`](#method-McpApp-call_tool)

- [`McpApp$resource_uri()`](#method-McpApp-resource_uri)

- [`McpApp$interaction_defaults()`](#method-McpApp-interaction_defaults)

- [`McpApp$print()`](#method-McpApp-print)

- [`McpApp$clone()`](#method-McpApp-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new McpApp

#### Usage

    McpApp$new(
      ui,
      tools = list(),
      name = "shinymcp-app",
      version = "0.1.0",
      theme = NULL,
      csp = NULL,
      permissions = NULL,
      prefers_border = NULL,
      tool_visibility = NULL,
      trigger = NULL,
      debounce_ms = NULL,
      resources = NULL,
      tool_outputs = NULL
    )

#### Arguments

- `ui`:

  An htmltools tag or tagList defining the UI. Can be a simple tagList
  of shinymcp components, or a full
  [`bslib::page()`](https://rstudio.github.io/bslib/reference/page.html)
  with theme.

- `tools`:

  A list of tool definitions (ellmer tool objects or named list)

- `name`:

  App name (used in resource URIs)

- `version`:

  App version string

- `theme`:

  Optional bslib theme (a
  [`bslib::bs_theme()`](https://rstudio.github.io/bslib/reference/bs_theme.html)
  object). If provided, the UI will be wrapped in a themed page. Not
  needed if `ui` is already a
  [`bslib::page()`](https://rstudio.github.io/bslib/reference/page.html).

- `csp`:

  Optional named list of Content Security Policy domain declarations for
  the app's `ui://` resource, per the MCP Apps spec. Hosts block
  undeclared external domains. Fields: `connect_domains`
  (fetch/XHR/WebSocket origins), `resource_domains` (scripts, styles,
  images, fonts), `frame_domains` (nested iframes), `base_uri_domains`.
  Apps with fully inlined assets (the shinymcp default) don't need this.

- `permissions`:

  Optional named list of sandbox permissions the app needs (e.g.
  `list(camera = list())`). Most apps don't need this.

- `prefers_border`:

  Optional logical; hint that the host should draw a border around the
  embedded app.

- `tool_visibility`:

  Optional named list mapping tool names to visibility scopes per the
  MCP Apps spec. Each entry is a character vector drawn from
  `c("model", "app")`. Use `"app"` for tools only the UI should call
  (hidden from the model), `"model"` for tools the UI should not call.
  Default (unset) is both.

- `trigger`:

  When the UI calls tools as inputs change: `"debounce"` (default,
  batches rapid changes) or `"change"` (immediate). The `"submit"` and
  `"manual"` modes only apply inside shinymcp's own Shiny host, which
  provides Apply/Run buttons.

- `debounce_ms`:

  Debounce interval in milliseconds (default 250).

- `resources`:

  Optional named list of extra resources served alongside the app. Names
  are URIs; values are a string (static content), a function returning a
  string (evaluated on each read, useful for lazy-loading data into the
  UI via `window.shinymcp.readResource()`), or a list with fields
  `content` (string or function), `mime_type`, `name`, `description`,
  `meta`.

- `tool_outputs`:

  Optional named list mapping tool names to the output ids they return
  (e.g. `list(explore = c("scatter", "stats"))`). Used to generate an
  `outputSchema` for each tool. Only declare this for tools that return
  a named list keyed by those output ids.

------------------------------------------------------------------------

### Method `html_resource()`

Generate the full HTML resource Returns a character string of the
complete HTML page including UI components, bridge script, and config.
HTML dependencies from bslib or other htmltools-based packages are
inlined automatically.

#### Usage

    McpApp$html_resource(bridge_config = NULL)

#### Arguments

- `bridge_config`:

  Optional named list of bridge config overrides used by
  `$html_resource()`.

------------------------------------------------------------------------

### Method `mcp_tools()`

Get tools annotated with MCP metadata Returns the tools list with
`_meta.ui` added to each plain-list tool, excluding tools whose
`visibility` does not include `"model"` (those are app-only: callable
from the rendered UI, hidden from the model). Used by the
shinychat/mcptools registration paths.

#### Usage

    McpApp$mcp_tools()

------------------------------------------------------------------------

### Method `tool_definitions()`

Get tool definitions for MCP tools/list responses Returns a list of tool
definition objects suitable for JSON-RPC. Each tool includes
`_meta.ui.resourceUri` linking it to the app's UI resource, which tells
MCP Apps-capable hosts to render the UI.

#### Usage

    McpApp$tool_definitions(include_ui_meta = TRUE)

#### Arguments

- `include_ui_meta`:

  Whether to attach `_meta.ui` to each tool. Set to `FALSE` for clients
  that did not advertise the MCP Apps extension capability, so tools
  degrade gracefully to text-only.

------------------------------------------------------------------------

### Method `extra_resources()`

Get the extra resources declared for this app Returns a named list (URI
-\> normalized spec with `uri`, `name`, `description`, `mime_type`,
`content_fn`, `meta`) for registration alongside the app's main ui://
resource.

#### Usage

    McpApp$extra_resources()

------------------------------------------------------------------------

### Method `read_extra_resource()`

Read one extra resource by URI Returns a `resources/read` contents entry
(`uri`, `mimeType`, `text`, optional `_meta`). Errors with class
`shinymcp_error_resource` when the URI is not a declared extra resource.

#### Usage

    McpApp$read_extra_resource(uri)

#### Arguments

- `uri`:

  The resource URI to read

------------------------------------------------------------------------

### Method `resource_meta()`

Get the `_meta` for this app's ui:// resource Returns the `_meta` list
(CSP domains, permissions, prefersBorder) to attach to the resource in
`resources/list` and `resources/read` responses, or `NULL` when nothing
was declared.

#### Usage

    McpApp$resource_meta()

------------------------------------------------------------------------

### Method `call_tool()`

Call a tool by name

#### Usage

    McpApp$call_tool(name, arguments = list())

#### Arguments

- `name`:

  Name of the tool to call

- `arguments`:

  Named list of arguments to pass to the tool

------------------------------------------------------------------------

### Method `resource_uri()`

Get the ui:// resource URI for this app

#### Usage

    McpApp$resource_uri()

------------------------------------------------------------------------

### Method `interaction_defaults()`

Get the app's declared interaction defaults Returns a list with
`trigger` and `debounce_ms` as declared at construction (either may be
`NULL` when unset). Hosts use this to defer to the app's declaration
when the embedder didn't specify.

#### Usage

    McpApp$interaction_defaults()

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print method

#### Usage

    McpApp$print(...)

#### Arguments

- `...`:

  Ignored.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    McpApp$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
