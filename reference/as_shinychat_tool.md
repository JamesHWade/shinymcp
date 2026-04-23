# Wrap an McpApp as an ellmer tool for shinychat

Small single-card apps work best here. Multi-tool apps return a list of
wrapped ellmer tools, one wrapper per underlying app tool.

## Usage

``` r
as_shinychat_tool(
  app,
  value_fn = NULL,
  summary = NULL,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE
)
```

## Arguments

- app:

  An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  object.

- value_fn:

  Optional function that derives the machine-facing value from the raw
  tool result.

- summary:

  Optional text fallback or summary function.

- title:

  Optional card title or title function.

- icon:

  Optional card icon or icon function.

- open:

  Whether the card starts expanded.

- show_request:

  Whether shinychat should show the request payload.
