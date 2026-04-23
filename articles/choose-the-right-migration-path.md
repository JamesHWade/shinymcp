# Choose the right migration path

`shinymcp` should be treated as two related products:

1.  A runtime for authored interactive cards and MCP Apps.
2.  An experimental migration assistant for existing Shiny apps.

The runtime path is the primary product today. Conversion remains
scaffold-oriented.

## 1. Authored card from scratch

Use this when you know the compact interaction you want.

``` r
app <- mcp_app(
  ui = htmltools::tagList(
    mcp_select("dataset", "Dataset", c("mtcars", "iris")),
    mcp_text("summary")
  ),
  tools = list(
    list(
      name = "inspect_dataset",
      description = "Inspect a built-in dataset",
      inputSchema = list(
        type = "object",
        properties = list(dataset = list(type = "string"))
      ),
      fun = function(dataset = "mtcars") {
        list(summary = paste(capture.output(summary(get(dataset))), collapse = "\n"))
      }
    )
  )
)
```

This path gives the cleanest runtime behavior in preview, shinychat, and
MCP hosts.

## 2. Wrapped module with explicit handler

Use this when you already have a bounded module or server-side
computation you trust.

- Keep the Shiny UI fragment.
- Expose only the inputs and outputs you want in the card.
- Supply an explicit tool handler instead of expecting automatic
  execution of arbitrary server code.

## 3. Selective migration into multiple cards

Use
[`as_mcp_apps()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_apps.md)
or `convert_app(mode = "cards")` when the original Shiny app contains
several connected reactive islands that should become separate chat
cards.

``` r
cards <- as_mcp_apps("path/to/shiny-app")
convert_app("path/to/shiny-app", mode = "cards")
```

This path is still scaffold output:

- tool bodies remain placeholders
- large reactive groups still need review
- side effects and unsupported widgets still need manual treatment

## 4. Full scaffold conversion

Use `convert_app(mode = "scaffold")` when you want a starting point for
manual completion.

``` r
convert_app("path/to/shiny-app", mode = "scaffold")
```

Always review `CONVERSION_NOTES.md`. The generated code is not a claim
that the source app now has a bounded headless runtime.

## Runtime versus scaffold

Use this rule of thumb:

- If you authored the handlers yourself, you are on the runtime path.
- If
  [`convert_app()`](https://jameshwade.github.io/shinymcp/reference/convert_app.md)
  generated the handlers, assume scaffold output until you replace the
  placeholders.
