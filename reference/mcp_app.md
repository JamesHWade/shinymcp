# Create an MCP App

Convenience function to create an
[McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object.

## Usage

``` r
mcp_app(
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
  tool_outputs = NULL,
  ...
)
```

## Arguments

- ui:

  UI definition (htmltools tags). Can be a simple
  [`htmltools::tagList()`](https://rstudio.github.io/htmltools/reference/tagList.html)
  of shinymcp components, or a full
  [`bslib::page()`](https://rstudio.github.io/bslib/reference/page.html)
  with theme.

- tools:

  List of tools

- name:

  App name

- version:

  App version

- theme:

  Optional
  [`bslib::bs_theme()`](https://rstudio.github.io/bslib/reference/bs_theme.html)
  object. Supports `brand` for
  [brand.yml](https://posit-dev.github.io/brand-yml/) theming. Not
  needed if `ui` is already a
  [`bslib::page()`](https://rstudio.github.io/bslib/reference/page.html).

- csp:

  Optional named list of Content Security Policy domain declarations for
  the app's `ui://` resource, per the MCP Apps spec. MCP hosts apply a
  restrictive default policy that blocks all external network access and
  assets, so any domain your app loads from at runtime must be declared
  here. Fields (snake_case or spec camelCase):

  - `connect_domains`: origins for fetch/XHR/WebSocket requests

  - `resource_domains`: origins for scripts, styles, images, fonts

  - `frame_domains`: origins for nested iframes

  - `base_uri_domains`: allowed `base-uri` values

  Apps with fully inlined assets (the shinymcp default) don't need this.

- permissions:

  Optional named list of iframe permissions the app needs, e.g.
  `list(camera = list())`. Most apps don't need this.

- prefers_border:

  Optional logical hint that the host should draw a border around the
  embedded app.

- tool_visibility:

  Optional named list mapping tool names to MCP Apps visibility scopes
  (character vectors drawn from `c("model", "app")`). Use `"app"` for
  tools only the rendered UI should call (hidden from the model's tool
  list), `"model"` for tools the UI must not call. Unset tools are
  visible to both.

- trigger:

  When the UI calls tools as inputs change: `"debounce"` (default) or
  `"change"`. `"submit"`/`"manual"` only apply inside shinymcp's own
  Shiny host.

- debounce_ms:

  Debounce interval in milliseconds (default 250).

- resources:

  Optional named list of extra resources served alongside the app,
  readable from the UI via `window.shinymcp.readResource(uri)`. Names
  are URIs; values are a string (static content), a function returning a
  string (evaluated on each read — useful for lazy-loading data instead
  of inlining it into the app HTML), or a list with fields `content`,
  `mime_type` (default `"text/plain"`), `name`, `description`, and
  `meta`. For example:
  `resources = list("ui://my-app/data" = list(content = function() jsonlite::toJSON(mtcars), mime_type = "application/json"))`

- tool_outputs:

  Optional named list mapping tool names to the output ids they return,
  e.g. `list(explore = c("scatter", "stats"))`. Declared tools get an
  auto-generated `outputSchema` (all properties are strings, with
  descriptions derived from the matching UI output types). Only declare
  tools that return a named list keyed by those output ids.

- ...:

  Additional arguments passed to `McpApp$new()`

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object
