# Build a shinychat-friendly tool result with a live embedded card

Build a shinychat-friendly tool result with a live embedded card

## Usage

``` r
mcp_content_result(
  app,
  value,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE,
  html = NULL,
  markdown = NULL,
  text = NULL,
  intent = NULL
)
```

## Arguments

- app:

  An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  object.

- value:

  Machine-facing value returned to the model.

- title:

  Optional card title.

- icon:

  Optional card icon.

- open:

  Whether the card starts expanded.

- show_request:

  Whether shinychat should show the request payload.

- full_screen:

  Whether shinychat should offer its full-screen tool-card mode when
  supported.

- html:

  Optional HTML display body.

- markdown:

  Optional markdown fallback.

- text:

  Optional plain-text fallback.

- intent:

  Optional display intent metadata.
