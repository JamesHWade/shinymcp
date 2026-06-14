# Use shinymcp with shinychat

There are two ways to put a shinymcp card into a shinychat conversation,
and both run the tool in the live Shiny session. You can wrap a small
`McpApp` as an ellmer tool with
[`as_shinychat_tool()`](https://jameshwade.github.io/shinymcp/reference/as_shinychat_tool.md),
or you can embed a live `McpApp` directly in Shiny with
[`mcp_host_ui()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_ui.md)
and
[`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_server.md)
(or the
[`mcp_embed()`](https://jameshwade.github.io/shinymcp/reference/mcp_embed.md)
shorthand).

Either way, the card is a portable MCP App iframe. When it runs inside
Shiny, the active Shiny session owns the live host state and runs tool
calls in R. The iframe is lightweight HTML plus the shinymcp bridge, so
you avoid starting a nested Shiny runtime for every chat card.

When shinychat exposes `display$full_screen`, shinymcp sets it for tool
cards. The embedded host shell also carries its own full-screen control,
which covers direct Shiny embeds and older shinychat development builds.

## Tool-card path with `chat_mod_server()`

``` r

library(shiny)
library(bslib)
library(ellmer)
library(shinychat)
library(shinymcp)

card_app <- mcp_app(
  ui = htmltools::tagList(
    mcp_text_input("name", "Name"),
    mcp_text("greeting")
  ),
  tools = list(
    list(
      name = "greet",
      description = "Generate a greeting card",
      inputSchema = list(
        type = "object",
        properties = list(name = list(type = "string"))
      ),
      fun = function(name = "world") {
        list(greeting = paste("Hello", name))
      }
    )
  ),
  name = "greeting-card"
)

greet_tool <- as_shinychat_tool(
  card_app,
  value_fn = function(raw_result) list(greeting = raw_result$greeting),
  summary = function(raw_result) raw_result$greeting,
  title = "Greeting Card"
)

ui <- page_fillable(chat_mod_ui("chat"))

server <- function(input, output, session) {
  client <- ellmer::chat("openai/gpt-4.1-nano")
  client$register_tool(greet_tool)
  chat_mod_server("chat", client)
}

shinyApp(ui, server)
```

The wrapped tool returns three things:

- A machine-facing value, the raw tool result transformed by `value_fn`.
- A human-facing shinychat tool card, a live embedded `McpApp` by
  default.
- Full-screen affordances for inspecting a larger card, using
  shinychat’s native tool-card mode when available.

## Content-streaming path with `chat_ui()` + `chat_append()`

When you already have a live Shiny session and want to append the card
yourself, reach for
[`mcp_content_result()`](https://jameshwade.github.io/shinymcp/reference/mcp_content_result.md):

``` r

ui <- page_fillable(chat_ui("chat"))

server <- function(input, output, session) {
  observeEvent(input$chat_user_input, {
    card <- mcp_content_result(
      app = card_app,
      value = list(status = "ready"),
      title = "Greeting Card"
    )

    chat_append("chat", card)
  })
}
```

## Direct embedding in Shiny

When you write the Shiny UI yourself, call the host shell helpers
directly:

``` r

ui <- page_fillable(
  mcp_host_ui("card")
)

server <- function(input, output, session) {
  host <- mcp_host_server(
    "card",
    app = card_app,
    trigger = "submit"
  )
}
```

`mcp_embed(card_app)` is the shorthand for dynamic server-side contexts
where a live session already exists.

The host object exposes read-only reactives, so the outer Shiny app can
watch the embedded card:

``` r

server <- function(input, output, session) {
  host <- mcp_host_server("card", app = card_app)

  observeEvent(host$model_context(), {
    # Current values the card is sending to the model context.
    str(host$model_context())
  })

  observeEvent(host$last_tool_call(), {
    # Raw R result plus formatted MCP structuredContent.
    str(host$last_raw_result())
    str(host$last_result()$structuredContent)
  })
}
```

## Interaction modes

[`mcp_embed()`](https://jameshwade.github.io/shinymcp/reference/mcp_embed.md)
and
[`mcp_host_server()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_server.md)
take a `trigger` that decides when the card calls its tool:

- `change` runs on every input change.
- `debounce` runs after a short quiet period.
- `submit` waits for the host shell Apply button.
- `manual` waits for an explicit host-side command such as
  `host$execute()`.

## What to reach for, and when

A few things hold up well in practice. Keep cards small and
single-purpose. Let tools run one at a time in shinychat until you have
a real reason to put many parallel cards in front of the model. Treat
the chat card as the human surface and the `value_fn` output as the
value the model reads back.

The choice between approaches comes down to where the app needs to run.
When you want a Shiny-only app with full reactive UI semantics, use
Shiny modules directly. When you want the same card to work in both
shinychat and MCP hosts, build it as an `McpApp`.
