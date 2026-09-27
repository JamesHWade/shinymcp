# Extracted from test-mcp-app.R:618

# prequel ----------------------------------------------------------------------
two_tool_app <- function(...) {
  mcp_app(
    htmltools::tagList(mcp_text_input("name", "Name"), mcp_text("message")),
    tools = list(
      list(
        name = "greet",
        description = "Greet someone.",
        fun = function(name = "world") list(message = paste("Hello", name))
      ),
      list(
        name = "approve",
        description = "Approve the greeting.",
        fun = function() "approved"
      )
    ),
    name = "two-tools",
    ...
  )
}

# test -------------------------------------------------------------------------
app <- mcp_app(htmltools::div())
expect_invisible(utils::capture.output(out <- print(app)))
