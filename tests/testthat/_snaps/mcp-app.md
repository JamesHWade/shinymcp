# apps print a summary of their tools

    Code
      print(app)
    Message
      <McpApp> two-tools 0.1.0
      Greets people.
      UI resource: <ui://two-tools>
      Tools:
      * greet
      * approve (app only)

# apps without tools say so

    Code
      print(mcp_app(htmltools::div(), name = "empty", version = "2.0.0"))
    Message
      <McpApp> empty 2.0.0
      UI resource: <ui://empty>
      No tools.

# apps backed by a Shiny server say so

    Code
      print(app)
    Message
      <McpApp> live 0.1.0
      UI resource: <ui://live>
      Runs a live Shiny server function for each view.
      No tools.

