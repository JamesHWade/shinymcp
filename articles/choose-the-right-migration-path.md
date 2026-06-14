# Choose the right migration path

`shinymcp` does two jobs. It is a runtime for interactive cards and MCP
Apps you write yourself, and it is an experimental converter that gets
existing Shiny apps part of the way there. The runtime is the part to
lean on today. Conversion still produces a scaffold you finish by hand.

There are four ways to start, depending on what you already have.

## 1. Authored card from scratch

Reach for this when you already know the small interaction you want.

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

You write the handler yourself, so the runtime behaves the same way in
preview, shinychat, and MCP hosts.

## 2. Wrapped module with explicit handler

Reach for this when you already have a bounded module or server-side
computation you trust. You keep the Shiny UI fragment, expose only the
inputs and outputs you want in the card, and supply an explicit tool
handler. Nothing runs your arbitrary server code automatically; the
handler you write is what the card calls.

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

The output is still a scaffold. Tool bodies come out as placeholders,
large reactive groups need review, and side effects and unsupported
widgets need manual treatment.

## 4. Full scaffold conversion

Reach for `convert_app(mode = "scaffold")` when you want a starting
point to finish by hand.

``` r

convert_app("path/to/shiny-app", mode = "scaffold")
```

Always review `CONVERSION_NOTES.md`. The generated code is a draft, not
a promise that the source app now has a bounded headless runtime.

## Runtime versus scaffold

The line between the two is who wrote the handlers. If you wrote them
yourself, you are on the runtime path and can trust the behavior. If
[`convert_app()`](https://jameshwade.github.io/shinymcp/reference/convert_app.md)
generated them, treat the result as scaffold output until you have
replaced the placeholders.
