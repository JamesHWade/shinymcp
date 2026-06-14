# Host shell server for an embedded MCP app

Host shell server for an embedded MCP app

## Usage

``` r
mcp_host_server(
  id,
  app,
  trigger = NULL,
  debounce_ms = NULL,
  height = "auto",
  initial_arguments = NULL,
  debug = FALSE
)
```

## Arguments

- id:

  Shiny module id.

- app:

  An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  object.

- trigger:

  Interaction mode: `"change"`, `"debounce"`, `"submit"`, or `"manual"`.
  Defaults to the app's own declaration (`mcp_app(trigger = )`), falling
  back to `"debounce"`.

- debounce_ms:

  Debounce interval in milliseconds. Defaults to the app's own
  declaration, falling back to 250.

- height:

  Preferred initial height for the host shell.

- initial_arguments:

  Optional named list of initial tool arguments.

- debug:

  Whether to enable debug affordances in the host shell.

## Value

A small control API with `instance_id`, `execute()`, `reset()`,
`dispose()`, and read-only reactives for `model_context`, `last_result`,
`last_raw_result`, `last_tool_call`, and `last_size`.

## Details

The embedded app is rendered via `srcdoc` in an iframe with
`sandbox="allow-scripts allow-same-origin"`, i.e. on the same origin as
the hosting Shiny app. This is appropriate for embedding apps you wrote
and trust; it is not a hardened boundary for running third-party HTML.
