# hello-mcp-minimal: the smallest possible MCP App.
#
# One input, one tool, one output. No theme, no plot. This is the shape every
# other example builds on: an `ui` of mcp_* components, a list of ellmer tools
# whose argument names match the input ids and whose return-list names match the
# output ids, then mcp_app() + serve().
library(shinymcp)

ui <- htmltools::tagList(
  mcp_text_input("name", "Your name", value = "world"),
  mcp_text("greeting")
)

tools <- list(
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
)

app <- mcp_app(ui, tools, name = "hello-mcp-minimal")
serve(app)
