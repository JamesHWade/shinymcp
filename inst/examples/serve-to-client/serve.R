# serve-to-client/serve.R: an MCP server you can call from a real client.
#
# This is the same kind of mcp_app() as the other examples; the difference is how
# you run it. Instead of previewing it locally, you register this file as a stdio
# MCP server in your client's config (see README.md). The client then lists and
# calls the `greet` tool and renders its card.
library(shinymcp)

app <- mcp_app(
  ui = htmltools::tagList(
    mcp_text_input("name", "Your name", value = "world"),
    mcp_text("greeting")
  ),
  tools = list(
    ellmer::tool(
      fun = function(name = "world") {
        list(greeting = paste0("Hello, ", name, "!"))
      },
      name = "greet",
      description = "Greet a person by name",
      arguments = list(
        name = ellmer::type_string("The name to greet")
      )
    )
  ),
  name = "shinymcp-demo"
)

serve(app, type = "stdio")
