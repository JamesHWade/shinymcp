test_that("format_tool_result handles typed result fragments", {
  result <- format_tool_result(list(
    summary = mcp_result_text("ready"),
    table = mcp_result_table(data.frame(x = 1, y = 2))
  ))

  expect_equal(result$structuredContent$summary, "ready")
  expect_match(result$structuredContent$table, "<table")
  expect_match(result$content[[1]]$text, "ready")
})

test_that("format_tool_result handles bare typed results", {
  result <- format_tool_result(mcp_result_text("ready"))

  expect_equal(
    result$structuredContent[[SHINYMCP_SINGLE_RESULT_KEY]]$type,
    "text"
  )
  expect_equal(
    result$structuredContent[[SHINYMCP_SINGLE_RESULT_KEY]]$value,
    "ready"
  )
  expect_false("kind" %in% names(result$structuredContent))
  expect_match(result$content[[1]]$text, "ready")
})

make_greeting_card_app <- function() {
  mcp_app(
    ui = htmltools::tagList(
      mcp_text_input("name", "Name"),
      mcp_text("message")
    ),
    tools = list(
      list(
        name = "greet",
        description = "Generate a greeting",
        inputSchema = list(
          type = "object",
          properties = list(
            name = list(type = "string")
          )
        ),
        fun = function(name = "world") {
          list(message = paste("Hello", name))
        }
      )
    ),
    name = "greeting-card"
  )
}

test_that("mcp_content_result is renderable by shinychat", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  app <- make_greeting_card_app()
  result <- mcp_content_result(
    app = app,
    value = list(status = "ok"),
    title = "Card Title",
    show_request = FALSE,
    html = htmltools::tags$div(class = "card-body", "Interactive card")
  )

  expect_true(inherits(result, "ellmer::ContentToolResult"))
  expect_equal(result@extra$display$title, "Card Title")
  expect_false(result@extra$display$show_request)
  expect_true(result@extra$display$full_screen)
  expect_s3_class(result@extra$display$html, "shiny.tag")
  expect_true(inherits(result@request, "ellmer::ContentToolRequest"))

  rendered <- shinychat::contents_shinychat(result)
  expect_equal(rendered$tool_name, "greet")
  expect_equal(rendered$tool_title, "Card Title")
  expect_equal(rendered$value_type, "html")
})

test_that("as_shinychat_tool wraps a single app tool", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  app <- make_greeting_card_app()

  wrapped <- as_shinychat_tool(
    app,
    summary = function(raw_result) raw_result$message,
    title = "Greeting Card"
  )

  expect_true(inherits(wrapped, "ellmer::ToolDef"))

  result <- wrapped(name = "Ada")
  expect_true(inherits(result, "ellmer::ContentToolResult"))
  expect_equal(result@extra$display$title, "Greeting Card")
  expect_equal(result@extra$display$text, "Hello Ada")
  expect_true(result@extra$display$full_screen)
  expect_equal(result@value$message, "Hello Ada")
  expect_true(inherits(result@request, "ellmer::ContentToolRequest"))

  rendered <- shinychat::contents_shinychat(result)
  expect_equal(rendered$tool_name, "greet")
  expect_equal(rendered$value_type, "text")
})

test_that("full_screen = FALSE propagates through the result chain", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  app <- make_greeting_card_app()

  result <- mcp_content_result(
    app = app,
    value = list(status = "ok"),
    full_screen = FALSE,
    html = htmltools::tags$div("card")
  )
  expect_false(result@extra$display$full_screen)

  wrapped <- as_shinychat_tool(app, full_screen = FALSE)
  tool_result <- wrapped(name = "Ada")
  expect_false(tool_result@extra$display$full_screen)
})

test_that("as_shinychat_tool handles ellmer TypeObject arguments", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  app <- mcp_app(
    ui = htmltools::tags$div("test"),
    tools = list(
      ellmer::tool(
        fun = function(x = "a", n = 1) list(out = paste(x, n)),
        name = "typed_tool",
        description = "A tool with TypeObject args",
        arguments = list(
          x = ellmer::type_string("Input string"),
          n = ellmer::type_number("Count")
        )
      )
    ),
    name = "typeobject-test"
  )

  # If ellmer_tool_arguments() regresses on TypeObject, wrapping would error
  # or the tool would be uncallable.
  wrapped <- as_shinychat_tool(
    app,
    summary = function(raw_result) raw_result$out
  )
  expect_true(inherits(wrapped, "ellmer::ToolDef"))

  result <- wrapped(x = "hello", n = 2)
  expect_true(inherits(result, "ellmer::ContentToolResult"))
  expect_equal(result@extra$display$text, "hello 2")
})
