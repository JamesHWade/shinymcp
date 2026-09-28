# Create an MCP App

An MCP App is an interactive page that an AI chat client (Claude,
ChatGPT, VS Code, Goose) shows inside the conversation, next to the
tools that feed it. `mcp_app()` pairs a UI with those tools:

- The **UI** is ordinary htmltools: Shiny or bslib inputs, outputs, and
  layouts, or shinymcp's own components such as
  [`mcp_select()`](https://jameshwade.github.io/shinymcp/reference/mcp_select.md)
  and
  [`mcp_plot()`](https://jameshwade.github.io/shinymcp/reference/mcp_plot.md).

- The **tools** are R functions, usually written with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).
  A tool's argument names match input ids, and the names of the list it
  returns match output ids. When the user changes an input, the app
  calls the tools that take that input and fills in their outputs.

The model can call the same tools. When it does, the host shows the app
and the app fills in from the result. Tools keep nothing between calls,
so any R process can answer any call.

To make one from a Shiny app you already have, see
[`vignette("rewriting-as-tools")`](https://jameshwade.github.io/shinymcp/articles/rewriting-as-tools.md).

## Usage

``` r
mcp_app(
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
  ...
)
```

## Arguments

- ui:

  The app's UI: an htmltools tag or tag list, or a full page such as
  [`bslib::page_sidebar()`](https://rstudio.github.io/bslib/reference/page_sidebar.html).

- tools:

  A list of tools:
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects, or plain lists with `name`, `description`, `fun`, and
  optionally `inputSchema`, `outputSchema`, `annotations`, and
  `visibility`.

- name:

  App name, used for the `ui://<name>` resource. Letters, digits, `-`
  and `_` work everywhere.

- version:

  App version string.

- title:

  Human-readable title, shown by some hosts.

- description:

  What the app does. Hosts and models read it when deciding whether to
  use it.

- theme:

  A
  [`bslib::bs_theme()`](https://rstudio.github.io/bslib/reference/bs_theme.html)
  to wrap a UI that isn't already a page.

- csp:

  External domains the page needs, as a named list with any of
  `connect_domains` (fetch and WebSocket), `resource_domains` (scripts,
  styles, images, fonts), `frame_domains` (nested iframes), and
  `base_uri_domains`. Hosts block everything not declared. shinymcp
  inlines its own dependencies, so most apps need none.

- permissions:

  Browser permissions the page asks for: a character vector drawn from
  `"camera"`, `"microphone"`, `"geolocation"`, and `"clipboard_write"`.
  Hosts may refuse.

- prefers_border:

  `TRUE` or `FALSE` to ask the host for (or not for) a border and
  background around the app. `NULL` leaves it to the host.

- domain:

  A dedicated origin for the app's sandbox, in the format the host
  documents. Rarely needed.

- tool_visibility:

  Who may call each tool: a named list mapping tool names to `"model"`,
  `"app"`, or both. Tools only the app calls (`"app"`) are hidden from
  the model; use them for controls that must stay in the user's hands,
  such as an approval button.

- tool_outputs:

  The output ids each tool returns, as a named list
  (`list(explore = c("scatter", "stats"))`). Declared tools get an
  `outputSchema`.

- trigger:

  When the app calls tools as inputs change: `"debounce"` (after a
  pause, the default), `"change"` (on every change), or `"submit"` (when
  the user presses an apply button; add one with
  [`mcp_submit_button()`](https://jameshwade.github.io/shinymcp/reference/mcp_submit_button.md)).

- debounce_ms:

  The pause for `trigger = "debounce"`, in milliseconds (default 250).

- resources:

  Extra resources the page can load on demand with
  `window.shinymcp.readResource(uri)`, as a named list from URI to a
  string, a function returning a string, or a list with `content`,
  `mime_type`, `name`, `description`, and `meta`. Use this to keep large
  data out of the page.

- host_styles:

  If `TRUE` (the default) the app takes the host's colors and fonts when
  the host provides them, and a Bootstrap 5 page follows its dark mode,
  so the app looks native in each client. Set `FALSE` to keep your own
  theme.

- model_context:

  If `TRUE` (the default) the app tells the model what the user has
  changed in it, so the model can take it into account on its next turn.

- images:

  If `TRUE` (the default) plots and images in a result returned to the
  model are also sent as image content the model can see. Set `FALSE` to
  save tokens.

- www:

  A directory of files the UI refers to by relative path, like a Shiny
  app's `www/` folder: scripts, stylesheets, and images. They are
  written into the page, since a host's frame can't fetch them. Paths
  added with
  [`shiny::addResourcePath()`](https://rdrr.io/pkg/shiny/man/resourcePaths.html)
  are found without it.

- ...:

  Passed to `McpApp$new()`.

## Value

An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
object.

## See also

Other apps:
[`McpApp`](https://jameshwade.github.io/shinymcp/reference/McpApp.md),
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
[`bindMcp()`](https://jameshwade.github.io/shinymcp/reference/bindMcp.md),
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)

## Examples

``` r
app <- mcp_app(
  ui = htmltools::tagList(
    mcp_text_input("name", "Your name", value = "world"),
    mcp_text("greeting")
  ),
  tools = list(
    ellmer::tool(
      function(name = "world") list(greeting = paste0("Hello, ", name, "!")),
      name = "greet",
      description = "Greet someone by name.",
      arguments = list(name = ellmer::type_string("Name to greet"))
    )
  ),
  name = "greeter"
)
app
#> <McpApp> greeter 0.1.0
#> UI resource: ui://greeter
#> Tools:
#> * greet
app$call_tool("greet", list(name = "Ada"))
#> $greeting
#> [1] "Hello, Ada!"
#> 

if (FALSE) { # \dontrun{
preview_app(app) # try it in a browser
serve(app)       # serve it to an MCP client over stdio
} # }
```
