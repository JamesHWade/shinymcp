test_that("mcp_host_ui renders a host shell", {
  ui <- mcp_host_ui("card")
  rendered <- as.character(ui)

  expect_match(rendered, 'data-shinymcp-host')
  expect_match(rendered, 'data-shinymcp-host-frame')
  expect_match(rendered, "Apply")
  expect_match(rendered, "Reset")
})

test_that("mcp_embed requires an id outside a live session", {
  app <- mcp_app(htmltools::tags$div("test"), name = "embed-test")

  expect_error(
    mcp_embed(app),
    "Provide .*id.* outside a live Shiny session"
  )
})

test_that("host state records model context, size, and tool results", {
  app <- mcp_app(
    ui = htmltools::tagList(
      mcp_text_input("name", "Name"),
      mcp_text("message")
    ),
    tools = list(
      list(
        name = "greet",
        fun = function(name = "world") {
          list(message = paste("Hello", name))
        }
      )
    ),
    name = "host-state-test"
  )
  state <- new_mcp_host_state(app)

  seen_context <- NULL
  seen_size <- NULL
  seen_call <- NULL
  state$on_model_context <- function(value, state) {
    seen_context <<- value
  }
  state$on_size <- function(value, state) {
    seen_size <<- value
  }
  state$on_tool_call <- function(value, state) {
    seen_call <<- value
  }

  mcp_host_update_model_context(state, list(name = "Ada"))
  mcp_host_notify_size(state, width = 320, height = 240)
  result <- mcp_host_call_tool(state, "greet", list(name = "Ada"))

  expect_equal(state$model_context$name, "Ada")
  expect_equal(seen_context$name, "Ada")
  expect_equal(state$last_size$height, 240)
  expect_equal(seen_size$width, 320)
  expect_equal(result$structuredContent$message, "Hello Ada")
  expect_equal(state$last_result$structuredContent$message, "Hello Ada")
  expect_equal(state$last_raw_result$message, "Hello Ada")
  expect_equal(state$last_tool_call$arguments$name, "Ada")
  expect_equal(seen_call$name, "greet")
})
