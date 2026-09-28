# shinychat integration: apps as live tool cards (R/shinychat.R)

card_app <- function(...) {
  mcp_app(
    htmltools::tagList(mcp_text_input("name", "Name"), mcp_text("message")),
    tools = list(
      list(
        name = "greet",
        description = "Greet someone.",
        annotations = list(
          title = "Greeter",
          read_only_hint = TRUE,
          open_world_hint = FALSE
        ),
        inputSchema = list(
          type = "object",
          properties = list(
            name = list(type = "string", description = "Who to greet"),
            times = list(type = "integer", description = "How many times")
          ),
          required = list("name")
        ),
        fun = function(name = "world", times = 1L) {
          stopifnot(is.integer(times))
          list(
            message = paste(rep(paste("Hello", name), times), collapse = " ")
          )
        }
      ),
      list(
        name = "shout",
        description = "Shout.",
        fun = function(text = "hey") toupper(text)
      ),
      list(
        name = "approve",
        description = "Approve.",
        fun = function() "ok",
        visibility = "app"
      )
    ),
    name = "greeting-card",
    ...
  )
}

# ---- as_shinychat_tool() ----

test_that("each tool the model may call becomes an ellmer tool", {
  skip_if_not_installed("ellmer")
  wrapped <- as_shinychat_tool(card_app())

  expect_type(wrapped, "list")
  expect_equal(names(wrapped), c("greet", "shout"))
  for (tool in wrapped) {
    expect_s3_class(tool, "ellmer::ToolDef")
  }
  expect_equal(wrapped$greet@name, "greet")
  expect_equal(wrapped$greet@description, "Greet someone.")
})

test_that("a single tool is returned on its own", {
  skip_if_not_installed("ellmer")
  wrapped <- as_shinychat_tool(card_app(), tool = "shout")

  expect_s3_class(wrapped, "ellmer::ToolDef")
  expect_equal(wrapped@name, "shout")
})

test_that("tool arguments and annotations carry over", {
  skip_if_not_installed("ellmer")
  greet <- as_shinychat_tool(card_app(), tool = "greet")
  args <- greet@arguments@properties

  expect_equal(names(args), c("name", "times"))
  expect_equal(args$name@type, "string")
  expect_equal(args$name@description, "Who to greet")
  expect_true(args$name@required)
  expect_equal(args$times@type, "integer")
  expect_false(args$times@required)
  expect_equal(names(formals(greet)), c("name", "times"))

  expect_equal(greet@annotations$title, "Greeter")
  expect_true(greet@annotations$read_only_hint)
  expect_false(greet@annotations$open_world_hint)

  retitled <- as_shinychat_tool(card_app(), tool = "greet", title = "Say hi")
  expect_equal(retitled@annotations$title, "Say hi")
})

test_that("apps without tools for the model can't be wrapped", {
  skip_if_not_installed("ellmer")
  expect_error(
    as_shinychat_tool(mcp_app(htmltools::div())),
    "no tools for the model"
  )
  # App-only tools aren't offered to the model.
  expect_error(
    as_shinychat_tool(card_app(), tool = "approve"),
    "no tool the model can call",
    class = "shinymcp_error_validation"
  )
})

test_that("calling the tool runs it and returns a card result", {
  skip_if_not_installed("ellmer")
  greet <- as_shinychat_tool(card_app(), tool = "greet")
  result <- greet(name = "Ada", times = 2)

  expect_s3_class(result, "ellmer::ContentToolResult")
  # The model gets the structured result.
  expect_equal(result@value, list(message = "Hello Ada Hello Ada"))
  display <- result@extra$display
  expect_equal(display$title, "Greeter")
  expect_true(display$open)
  expect_false(display$show_request)
  expect_true(display$full_screen)
  # Outside a Shiny session the card shows the result's text.
  expect_equal(display$text, "message: Hello Ada Hello Ada")
  expect_null(display$html)
})

test_that("arguments the model leaves out take the tool's defaults", {
  skip_if_not_installed("ellmer")
  greet <- as_shinychat_tool(card_app(), tool = "greet")

  expect_equal(greet()@value, list(message = "Hello world"))
  expect_equal(greet(name = NULL)@value, list(message = "Hello world"))
})

test_that("results without structured content give the model text", {
  skip_if_not_installed("ellmer")
  shout <- as_shinychat_tool(card_app(), tool = "shout")
  result <- shout(text = "hey")

  expect_equal(result@value, "HEY")
  expect_equal(result@extra$display$text, "HEY")
})

test_that("card options are passed to the display", {
  skip_if_not_installed("ellmer")
  shout <- as_shinychat_tool(
    card_app(),
    tool = "shout",
    title = "Loud",
    icon = "megaphone",
    open = FALSE,
    show_request = TRUE,
    full_screen = FALSE,
    summary = "Shouted."
  )
  display <- shout(text = "hey")@extra$display

  expect_equal(display$title, "Loud")
  expect_equal(display$icon, "megaphone")
  expect_false(display$open)
  expect_true(display$show_request)
  expect_false(display$full_screen)
  expect_equal(display$text, "Shouted.")
})

test_that("value, summary, title, and icon can be computed from the call", {
  skip_if_not_installed("ellmer")
  greet <- as_shinychat_tool(
    card_app(),
    tool = "greet",
    value_fn = function(raw_result, arguments) {
      list(raw = raw_result$message, args = arguments)
    },
    summary = function(result) paste("Said:", result$structuredContent$message),
    title = function(arguments) paste("Greeting", arguments$name),
    icon = function(...) "wave"
  )
  result <- greet(name = "Bo")

  expect_equal(result@value, list(raw = "Hello Bo", args = list(name = "Bo")))
  expect_equal(result@extra$display$text, "Said: Hello Bo")
  expect_equal(result@extra$display$title, "Greeting Bo")
  expect_equal(result@extra$display$icon, "wave")
  # A computed title leaves the tool's own title in its annotations.
  expect_equal(greet@annotations$title, "Greeter")
})

test_that("tool calls from a chat are made as the model", {
  skip_if_not_installed("ellmer")
  seen <- NULL
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "who", fun = function() {
      seen <<- mcp_request()
      "ok"
    })),
    name = "who"
  )

  as_shinychat_tool(app)()
  expect_equal(seen$caller, "model")
  expect_equal(seen$transport, "shinychat")
})

test_that("ellmer tools keep their typed arguments through the wrapper", {
  skip_if_not_installed("ellmer")
  app <- mcp_app(
    htmltools::div("test"),
    tools = list(ellmer::tool(
      fun = function(x = "a", n = 1) list(out = paste(x, n)),
      name = "typed_tool",
      description = "A tool with typed arguments",
      arguments = list(
        x = ellmer::type_string("Input string"),
        n = ellmer::type_number("Count")
      )
    )),
    name = "typeobject-test"
  )

  wrapped <- as_shinychat_tool(app, summary = function(raw_result) {
    raw_result$out
  })
  expect_s3_class(wrapped, "ellmer::ToolDef")
  result <- wrapped(x = "hello", n = 2)
  expect_s3_class(result, "ellmer::ContentToolResult")
  expect_equal(result@extra$display$text, "hello 2")
})

test_that("chat cards open on the same result the app would render", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  local_mocked_bindings(active_shiny_session = function() session)
  base64 <- base64_file(helper_png_file())
  app <- mcp_app(
    mcp_plot("chart"),
    tools = list(list(name = "draw", fun = function() list(chart = base64))),
    name = "drawing"
  )

  card <- helper_value(as_shinychat_tool(app)())
  config <- helper_markup_config(as.character(card@extra$display$html))
  view <- config$result[["_meta"]][["shinymcp/view"]]
  expect_equal(view$outputs$chart$kind, "image")
  expect_equal(view$tool, "draw")
})

test_that("tools with free-form object arguments can be wrapped", {
  skip_if_not_installed("ellmer")
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(
      name = "filter",
      description = "Filter",
      fun = function(filters = NULL) length(filters),
      inputSchema = list(
        type = "object",
        properties = list(
          filters = list(type = "object", description = "Free-form filters")
        )
      )
    )),
    name = "free-form"
  )

  wrapped <- as_shinychat_tool(app)
  expect_s3_class(wrapped, "ellmer::ToolDef")
  expect_equal(wrapped(filters = list(a = 1, b = 2))@value, "2")
})

test_that("inside a Shiny session the card shows the live app", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  local_mocked_bindings(active_shiny_session = function() session)

  # In a session the tool doesn't block: it returns a promise.
  pending <- as_shinychat_tool(card_app(), tool = "greet", title = "Card")(
    name = "Ada"
  )
  expect_true(promises::is.promising(pending))
  result <- helper_value(pending)
  display <- result@extra$display
  html <- as.character(display$html)
  config <- helper_markup_config(html)
  instances <- ls(session$userData$.shinymcp_hosts$instances)

  expect_s3_class(display$html, "shiny.tag")
  expect_null(display$text)
  expect_equal(display$title, "Card")
  # Chat cards bring their own chrome.
  expect_false(grepl("shinymcp-host-toolbar", html, fixed = TRUE))
  expect_length(instances, 1)
  expect_equal(config$instanceId, instances)
  expect_equal(config$source, "greeting-card")
  expect_equal(config$tool, "greet")
  expect_equal(config$arguments, list(name = "Ada"))
  # The card opens on the result the model got, without calling the tool
  # again, and carries no page: it reads the page when it attaches.
  expect_equal(config$result$structuredContent, list(message = "Hello Ada"))
  expect_null(config$html)
  expect_equal(result@value, list(message = "Hello Ada"))
  state <- session$userData$.shinymcp_hosts$instances[[instances]]
  expect_equal(state$kind, "card")
  # Its text is there for where the app can't be shown.
  expect_match(html, "data-shinymcp-host-fallback", fixed = TRUE)
})

test_that("a tool that fails gives the model an error", {
  skip_if_not_installed("ellmer")
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "boom", fun = function() stop("kaboom"))),
    name = "broken"
  )
  result <- as_shinychat_tool(app)()

  expect_s3_class(result, "ellmer::ContentToolResult")
  expect_equal(result@error, "Error: kaboom")
})

test_that("tools that show no app return their result without a card", {
  skip_if_not_installed("ellmer")
  source <- new_host_source("fake", "plain", "Plain")
  source$tools <- function(refresh = FALSE) {
    list(list(
      name = "add",
      description = "Add.",
      inputSchema = list(
        type = "object",
        properties = list(a = list(type = "number"), b = list(type = "number"))
      )
    ))
  }
  source$call <- function(name, arguments = NULL, context = list()) {
    list(
      result = list(
        content = list(list(type = "text", text = "3")),
        structuredContent = list(sum = arguments$a + arguments$b)
      ),
      raw = NULL
    )
  }

  result <- as_shinychat_tool(source)(a = 1, b = 2)
  expect_equal(result@value, list(sum = 3))
  expect_null(result@extra$display)
})

# ---- Remote servers ----

test_that("a remote server's tools become cards", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shiny")
  fx <- serving_client(
    McpServer$new(serving_app(name = "fx")),
    name = "remote-fx"
  )

  wrapped <- as_shinychat_tool(fx$client)
  # The tool only the page may call isn't offered to the model.
  expect_equal(names(wrapped), c("echo", "boom"))
  expect_equal(names(formals(wrapped$echo)), "x")

  outside <- wrapped$echo(x = "hi")
  expect_equal(outside@value, list(out = "hi"))
  expect_equal(outside@extra$display$text, "out: hi")

  session <- shiny::MockShinySession$new()
  local_mocked_bindings(active_shiny_session = function() session)
  card <- helper_value(wrapped$echo(x = "live"))
  config <- helper_markup_config(as.character(card@extra$display$html))
  expect_equal(config$source, "remote-fx")
  expect_equal(config$tool, "echo")
  expect_equal(config$result$structuredContent, list(out = "live"))
  registry <- session$userData$.shinymcp_hosts
  expect_true(inherits(
    registry$sources[["remote-fx"]],
    "shinymcp_host_source_remote"
  ))

  failed <- helper_value(wrapped$boom())
  expect_match(failed@error, "kaboom")
})

# ---- mcp_content_result() ----

test_that("mcp_content_result() builds a card for the app's first tool", {
  skip_if_not_installed("ellmer")
  result <- mcp_content_result(
    card_app(),
    value = list(status = "ok"),
    arguments = list(name = "Ada"),
    title = "Card Title",
    icon = "star",
    show_request = TRUE,
    full_screen = FALSE
  )

  expect_s3_class(result, "ellmer::ContentToolResult")
  expect_equal(result@value, list(status = "ok"))
  expect_s3_class(result@request, "ellmer::ContentToolRequest")
  expect_equal(result@request@name, "greet")
  expect_equal(result@request@arguments, list(name = "Ada"))
  expect_match(result@request@id, "^call-")
  display <- result@extra$display
  expect_equal(display$title, "Card Title")
  expect_equal(display$icon, "star")
  expect_true(display$show_request)
  expect_false(display$full_screen)
})

test_that("mcp_content_result() shows text where the app can't render", {
  skip_if_not_installed("ellmer")
  app <- card_app()

  expect_equal(
    mcp_content_result(app, value = c("a", "b"))@extra$display$text,
    "a\nb"
  )
  expect_equal(
    mcp_content_result(app, value = 1, text = "custom")@extra$display$text,
    "custom"
  )
  expect_equal(mcp_content_result(app, value = 1)@request@arguments, list())
})

test_that("mcp_content_result() for an app without tools is named after the app", {
  skip_if_not_installed("ellmer")
  result <- mcp_content_result(
    mcp_app(htmltools::div(), name = "static"),
    value = "shown"
  )
  expect_equal(result@request@name, "static")
})

test_that("mcp_content_result() in a Shiny session embeds the app", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  local_mocked_bindings(active_shiny_session = function() session)

  result <- mcp_content_result(
    card_app(),
    value = list(status = "ok"),
    arguments = list(name = "Ada")
  )
  config <- helper_markup_config(as.character(result@extra$display$html))

  expect_equal(config$tool, "greet")
  expect_equal(config$arguments, list(name = "Ada"))
  # No result yet: R calls the tool, and the card gets the result when it
  # attaches.
  expect_null(config$result)
  helper_drain()
  state <- session$userData$.shinymcp_hosts$instances[[config$instanceId]]
  expect_equal(state$result$structuredContent, list(message = "Hello Ada"))
})

test_that("cards render in shinychat", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  local_mocked_bindings(active_shiny_session = function() session)

  card <- mcp_content_result(
    card_app(),
    value = list(status = "ok"),
    title = "Card Title"
  )
  rendered <- shinychat::contents_shinychat(card)
  expect_equal(rendered$tool_name, "greet")
  expect_equal(rendered$title, "Card Title")
  expect_equal(rendered$value_type, "html")

  # ellmer attaches the request when the model calls the tool.
  tool_result <- helper_value(
    as_shinychat_tool(card_app(), tool = "greet")(name = "Ada")
  )
  tool_result@request <- ellmer::ContentToolRequest(
    id = "call-1",
    name = "greet",
    arguments = list(name = "Ada")
  )
  rendered <- shinychat::contents_shinychat(tool_result)
  expect_equal(rendered$tool_name, "greet")
  expect_equal(rendered$value_type, "html")
})

test_that("text cards render in shinychat outside a session", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  card <- mcp_content_result(card_app(), value = "plain", text = "Plain text")
  rendered <- shinychat::contents_shinychat(card)
  expect_equal(rendered$tool_name, "greet")
  expect_equal(rendered$value_type, "text")
})

# ---- Helpers ----

test_that("call_with_supported_args() passes only the arguments a function takes", {
  args <- list(raw_result = 1, result = 2, arguments = 3)

  expect_equal(call_with_supported_args(function() "none", args), "none")
  expect_equal(call_with_supported_args(function(result) result, args), 2)
  expect_equal(
    call_with_supported_args(
      function(arguments, raw_result) arguments + raw_result,
      args
    ),
    4
  )
  expect_equal(
    call_with_supported_args(function(...) length(list(...)), args),
    3
  )
})

test_that("the model value is the structured content, else the text", {
  expect_equal(
    default_model_value(list(
      structuredContent = list(a = 1),
      content = list(list(type = "text", text = "t"))
    )),
    list(a = 1)
  )
  expect_equal(
    default_model_value(list(
      content = list(
        list(type = "text", text = "one"),
        list(type = "image", data = "x"),
        list(type = "text", text = "two")
      )
    )),
    "one\ntwo"
  )
  expect_equal(result_text(NULL), "")
})
