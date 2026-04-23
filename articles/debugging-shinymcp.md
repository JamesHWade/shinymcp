# Debugging shinymcp

## Inspect inputs and tool groups

Start with the parser and analyzer:

``` r
ir <- parse_shiny_app("path/to/app")
analysis <- analyze_reactive_graph(ir)

analysis$tool_groups
ir$inputs
ir$outputs
```

That tells you whether `shinymcp` found the same reactive islands you
expected.

## Inspect bridge traffic in preview

[`preview_app()`](https://jameshwade.github.io/shinymcp/reference/preview_app.md)
now uses the shared host controller and exposes a protocol log in the
preview page. Use it to inspect:

- `ui/initialize`
- `tools/call`
- `ui/update-model-context`
- `ui/notifications/size-changed`

## Inspect display payloads

Use `format_tool_result()` during development when you want to see
exactly what the runtime will send back to the host:

``` r
format_tool_result(list(
  summary = mcp_result_text("ready"),
  table = mcp_result_table(head(mtcars))
))
```

For shinychat wrappers, inspect the `ContentToolResult` directly:

``` r
tool <- as_shinychat_tool(card_app)
result <- tool(dataset = "mtcars")

result@value
result@extra$display
```

## Common failure modes

- Input ids do not match tool argument names.
- Large converted groups should really be split into smaller cards.
- Generated conversion tools are still placeholders.
- Rich display works in shinychat, but plain fallback text still matters
  for other hosts.
