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

- [`McpApp$call_tool()`](#method-McpApp-call_tool)

- [`McpApp$resource_uri()`](#method-McpApp-resource_uri)

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
      theme = NULL
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

------------------------------------------------------------------------

### Method `html_resource()`

Generate the full HTML resource Returns a character string of the
complete HTML page including UI components, bridge script, and config.
HTML dependencies from bslib or other htmltools-based packages are
inlined automatically.

#### Usage

    McpApp$html_resource()

------------------------------------------------------------------------

### Method `mcp_tools()`

Get tools annotated with MCP metadata Returns the tools list with
\_meta.ui.resourceUri added to each tool.

#### Usage

    McpApp$mcp_tools()

------------------------------------------------------------------------

### Method `tool_definitions()`

Get tool definitions for MCP tools/list responses Returns a list of tool
definition objects suitable for JSON-RPC. Each tool includes
`_meta.ui.resourceUri` linking it to the app's UI resource, which tells
MCP Apps-capable hosts to render the UI.

#### Usage

    McpApp$tool_definitions()

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

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print method

#### Usage

    McpApp$print(...)

#### Arguments

`...`:

Ignored. Inline HTML dependencies as

and

tags\</p\>\</dd\> \</dl\>\<p\>\</div\>\</p\> \</div\>
\</div\>\<p\>\<hr\> \<a id="method-McpApp-clone"\>\</a\>\</p\>\<div
class='section' id='method-clone-'\> \<h3\>Method
\<code\>clone()\</code\>\</h3\> \<p\>The objects of this class are
cloneable with this method.\</p\>\<div class='section' id='usage'\>
\<h4\>Usage\</h4\> \<p\>\<div
class="r"\>\</p\>\<pre\>\<code\>McpApp\$clone(deep =
FALSE)\</code\>\</pre\>\<p\>\</div\>\</p\> \</div\> \<div
class='section' id='arguments'\> \<h4\>Arguments\</h4\> \<p\>\<div
class="arguments"\>\</p\>\<dl\> \<dt\>\<code\>deep\</code\>\</dt\>
\<dd\>\<p\>Whether to make a deep clone.\</p\>\</dd\>
\</dl\>\<p\>\</div\>\</p\> \</div\> \</div\> \</div\> \</main\> \<aside
class="col-md-3"\> \<nav id="toc" aria-label="Table of contents"\>
\<h2\>On this page\</h2\> \</nav\> \</aside\> \</div\> \<footer\> \<div
class="pkgdown-footer-left"\> \<p\>Developed by James Wade.\</p\>
\</div\> \<div class="pkgdown-footer-right"\> \<p\>Site built with \<a
href="https://pkgdown.r-lib.org/"\>pkgdown\</a\> 2.2.0.\</p\> \</div\>
\</footer\> \</div\> \</body\> \</html\> \</style\>\</p\>
\</li\>\</ul\>\</div\> \</div\> \</div\> \</div\>\</main\>
