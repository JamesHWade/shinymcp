# Host shell server for an embedded MCP app

Host shell server for an embedded MCP app

## Usage

``` r
mcp_host_server(
  id,
  app,
  trigger = c("debounce", "change", "submit", "manual"),
  debounce_ms = 250,
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

- debounce_ms:

  Debounce interval in milliseconds.

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
