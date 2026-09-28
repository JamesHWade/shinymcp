# McpApp: construction, resources, tool definitions, and running tools.

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

# ---- Construction ----

test_that("mcp_app() makes an McpApp", {
  app <- mcp_app(
    htmltools::div("Hello"),
    name = "my-app",
    version = "1.2.0",
    title = "My App",
    description = "Says hello."
  )

  expect_s3_class(app, "McpApp")
  expect_equal(app$name, "my-app")
  expect_equal(app$version, "1.2.0")
  expect_equal(app$title, "My App")
  expect_equal(app$description, "Says hello.")
  expect_equal(app$resource_uri(), "ui://my-app")
  expect_null(app$runtime())
  expect_length(app$tools(), 0)
})

test_that("mcp_app() has sensible defaults", {
  app <- mcp_app(htmltools::div())

  expect_equal(app$name, "shinymcp-app")
  expect_equal(app$version, "0.1.0")
  expect_null(app$title)
  expect_null(app$description)
  expect_equal(
    app$interaction_defaults(),
    list(trigger = NULL, debounce_ms = NULL)
  )
})

test_that("McpApp$new() takes the same arguments as mcp_app()", {
  app <- McpApp$new(ui = htmltools::div("Hi"), name = "direct")
  expect_s3_class(app, "McpApp")
  expect_equal(app$resource_uri(), "ui://direct")
})

test_that("the UI must be htmltools", {
  expect_error(mcp_app("not ui"), class = "shinymcp_error_validation")
  expect_error(mcp_app(list(1)), class = "shinymcp_error_validation")
  expect_s3_class(mcp_app(htmltools::HTML("<p>raw</p>")), "McpApp")
  expect_s3_class(mcp_app(htmltools::tagList()), "McpApp")
})

test_that("the name must be a single non-empty string", {
  expect_error(
    mcp_app(htmltools::div(), name = ""),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), name = c("a", "b")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), name = NA_character_),
    class = "shinymcp_error_validation"
  )
})

test_that("tools must be a list of tools", {
  expect_error(
    mcp_app(htmltools::div(), tools = "x"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), tools = list(42)),
    "tool 1",
    class = "shinymcp_error_validation"
  )
})

test_that("a single tool doesn't need to be wrapped in a list", {
  skip_if_not_installed("ellmer")
  tool <- ellmer::tool(
    function(x = "a") x,
    name = "echo",
    description = "Echo",
    arguments = list(x = ellmer::type_string(required = FALSE))
  )

  app <- mcp_app(htmltools::div(), tools = tool)
  expect_equal(names(app$tools()), "echo")

  record <- new_mcp_tool("raw", handler = function(arguments, context) "raw")
  expect_equal(names(mcp_app(htmltools::div(), tools = record)$tools()), "raw")
})

test_that("tool names must be unique", {
  expect_error(
    mcp_app(
      htmltools::div(),
      tools = list(
        list(name = "a", fun = function() 1),
        list(name = "a", fun = function() 2)
      )
    ),
    class = "shinymcp_error_validation"
  )
})

test_that("ellmer tools are listed and called like any other", {
  skip_if_not_installed("ellmer")
  app <- mcp_app(
    htmltools::div("Hello"),
    tools = list(ellmer::tool(
      fun = function(x = "a") x,
      name = "echo",
      description = "Echo the input",
      arguments = list(x = ellmer::type_string("Value to echo"))
    )),
    name = "s7-test"
  )

  defs <- app$tool_definitions()
  expect_length(defs, 1)
  expect_equal(defs[[1]]$name, "echo")
  expect_equal(defs[[1]]$description, "Echo the input")
  expect_equal(defs[[1]]$inputSchema$type, "object")
  expect_equal(defs[[1]]$inputSchema$properties$x$type, "string")
  expect_equal(app$call_tool("echo", list(x = "hello")), "hello")
})

# ---- Visibility and outputs ----

test_that("tool_visibility hides app-only tools from the model", {
  app <- two_tool_app(tool_visibility = list(approve = "app"))

  expect_equal(app$tools()$approve$visibility, "app")
  expect_null(app$tools()$greet$visibility)
  expect_equal(names(app$tools("model")), "greet")
  expect_equal(names(app$tools("app")), c("greet", "approve"))
  expect_true(app$has_tool("approve"))
  expect_false(app$has_tool("nope"))
})

test_that("tool_visibility is validated", {
  expect_error(
    two_tool_app(tool_visibility = list(approve = "robot")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    two_tool_app(tool_visibility = "app"),
    class = "shinymcp_error_validation"
  )
  expect_warning(
    two_tool_app(tool_visibility = list(nope = "app")),
    "match no tool"
  )
})

test_that("tool_outputs declares the outputs each tool fills", {
  app <- two_tool_app(tool_outputs = list(greet = "message"))
  expect_equal(app$tools()$greet$outputs, "message")
  expect_null(app$tools()$approve$outputs)

  expect_error(
    two_tool_app(tool_outputs = list(greet = 1)),
    class = "shinymcp_error_validation"
  )
  expect_error(
    two_tool_app(tool_outputs = "message"),
    class = "shinymcp_error_validation"
  )
  expect_warning(two_tool_app(tool_outputs = list(nope = "x")), "match no tool")
})

test_that("tool_definitions() lists every tool with UI metadata", {
  app <- two_tool_app(
    tool_visibility = list(approve = "app"),
    tool_outputs = list(greet = "message")
  )
  defs <- app$tool_definitions()

  expect_equal(vapply(defs, `[[`, character(1), "name"), c("greet", "approve"))
  greet <- defs[[1]]
  expect_equal(greet[["_meta"]][["ui/resourceUri"]], "ui://two-tools")
  expect_equal(greet[["_meta"]][["ui"]], list(resourceUri = "ui://two-tools"))
  expect_equal(names(greet$outputSchema$properties), "message")
  expect_equal(as.character(defs[[2]][["_meta"]][["ui"]]$visibility), "app")
})

test_that("tool_definitions() can leave out UI metadata and app-only tools", {
  app <- two_tool_app(tool_visibility = list(approve = "app"))

  text_only <- app$tool_definitions(
    include_ui_meta = FALSE,
    include_app_only = FALSE
  )
  expect_equal(vapply(text_only, `[[`, character(1), "name"), "greet")
  expect_null(text_only[[1]][["_meta"]][["ui"]])
  expect_equal(text_only[[1]][["_meta"]][["ui/resourceUri"]], "ui://two-tools")

  no_meta <- app$tool_definitions(include_ui_meta = FALSE)
  expect_length(no_meta, 2)
})

test_that("tool definitions serialize to the MCP shape", {
  app <- two_tool_app(tool_visibility = list(approve = "app"))
  json <- jsonlite::parse_json(to_json(app$tool_definitions()))

  expect_equal(
    json[[1]]$inputSchema,
    list(type = "object", properties = list(name = list(type = "string")))
  )
  expect_equal(json[[2]]$inputSchema$properties, setNames(list(), character()))
  expect_equal(json[[2]][["_meta"]]$ui$visibility, list("app"))
})

test_that("output_types() finds output placeholders and Shiny outputs", {
  skip_if_not_installed("shiny")
  app <- mcp_app(
    htmltools::tagList(
      mcp_text("summary"),
      mcp_plot("chart"),
      mcp_table("rows"),
      mcp_html("note"),
      shiny::textOutput("shiny_text")
    ),
    name = "outputs"
  )

  expect_equal(
    app$output_types(),
    c(
      summary = "text",
      chart = "plot",
      rows = "table",
      note = "html",
      shiny_text = "text"
    )
  )
})

# ---- Interaction settings ----

test_that("trigger must be one of the known triggers", {
  for (trigger in c("debounce", "change", "submit", "manual")) {
    app <- mcp_app(htmltools::div(), trigger = trigger)
    expect_equal(app$interaction_defaults()$trigger, trigger)
  }
  expect_error(mcp_app(htmltools::div(), trigger = "sometimes"))
})

test_that("debounce_ms is kept as the app's default", {
  app <- mcp_app(htmltools::div(), trigger = "debounce", debounce_ms = 500)
  expect_equal(
    app$interaction_defaults(),
    list(trigger = "debounce", debounce_ms = 500)
  )
})

test_that("debounce_ms must be a non-negative number", {
  expect_error(
    mcp_app(htmltools::div(), debounce_ms = "fast"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), debounce_ms = -5),
    class = "shinymcp_error_validation"
  )
})

test_that("a theme wraps the UI in a bslib page", {
  skip_if_not_installed("bslib")
  app <- mcp_app(
    htmltools::div(mcp_text("x")),
    theme = bslib::bs_theme(version = 5),
    name = "themed"
  )
  html <- app$html_resource()

  expect_match(
    html,
    'class="shinymcp shinymcp-bootstrap shinymcp-bs5"',
    fixed = TRUE
  )
  expect_equal(helper_count(html, "<body"), 1)
  expect_false(grepl('<main class="shinymcp-app">', html, fixed = TRUE))
})

# ---- Resources ----

test_that("the UI resource is listed with its metadata", {
  app <- mcp_app(htmltools::div(), name = "plain", title = "Plain")
  resources <- app$resources()

  expect_length(resources, 1)
  expect_equal(
    resources[[1]],
    list(
      uri = "ui://plain",
      name = "plain",
      title = "Plain",
      description = "MCP App: plain",
      mimeType = "text/html;profile=mcp-app"
    )
  )
  expect_null(app$resource_meta())
})

test_that("resource_meta() carries CSP, permissions, domain, and border", {
  app <- mcp_app(
    htmltools::div(),
    name = "meta",
    csp = list(
      connect_domains = "https://api.example.com",
      resourceDomains = c("https://cdn.example.com", "https://b.example.com"),
      frame_domains = "https://frame.example.com",
      base_uri_domains = "https://base.example.com"
    ),
    permissions = c("camera", "clipboard_write"),
    prefers_border = FALSE,
    domain = "meta.example.com"
  )
  meta <- app$resource_meta()$ui

  expect_equal(as.character(meta$csp$connectDomains), "https://api.example.com")
  expect_equal(
    as.character(meta$csp$resourceDomains),
    c("https://cdn.example.com", "https://b.example.com")
  )
  expect_equal(as.character(meta$csp$frameDomains), "https://frame.example.com")
  expect_equal(
    as.character(meta$csp$baseUriDomains),
    "https://base.example.com"
  )
  expect_equal(names(meta$permissions), c("camera", "clipboardWrite"))
  expect_equal(meta$domain, "meta.example.com")
  expect_false(meta$prefersBorder)

  json <- jsonlite::parse_json(to_json(app$resource_meta()))
  expect_equal(json$ui$csp$connectDomains, list("https://api.example.com"))
  expect_equal(
    json$ui$permissions,
    list(
      camera = setNames(list(), character()),
      clipboardWrite = setNames(list(), character())
    )
  )
  expect_equal(app$resources()[[1]][["_meta"]], app$resource_meta())
})

test_that("permissions accept the list form", {
  app <- mcp_app(
    htmltools::div(),
    permissions = list(camera = list(), geolocation = list())
  )
  expect_equal(
    names(app$resource_meta()$ui$permissions),
    c("camera", "geolocation")
  )
})

test_that("csp and permissions are validated", {
  expect_error(
    mcp_app(htmltools::div(), csp = "x"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), csp = list(bogus = "x")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), permissions = "teleport"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), permissions = character()),
    class = "shinymcp_error_validation"
  )
})

test_that("read_resource() returns the page with its metadata", {
  app <- mcp_app(
    htmltools::div("Page"),
    name = "readable",
    prefers_border = TRUE
  )
  contents <- app$read_resource("ui://readable")

  expect_equal(contents$uri, "ui://readable")
  expect_equal(contents$mimeType, "text/html;profile=mcp-app")
  expect_equal(contents$text, app$html_resource())
  expect_equal(contents[["_meta"]], list(ui = list(prefersBorder = TRUE)))
  expect_true(app$has_resource("ui://readable"))
})

test_that("extra resources are listed and read", {
  app <- mcp_app(
    htmltools::div(),
    name = "extras",
    resources = list(
      "data://small" = "hello",
      "data://fn" = function() jsonlite::toJSON(list(a = 1:3)),
      "data://lines" = function() c("a", "b"),
      "data://full" = list(
        content = "c",
        mime_type = "application/json",
        name = "Full",
        description = "Described",
        meta = list(k = "v")
      )
    )
  )
  listed <- app$resources()

  expect_equal(
    vapply(listed, `[[`, character(1), "uri"),
    c("ui://extras", "data://small", "data://fn", "data://lines", "data://full")
  )
  expect_equal(
    listed[[2]],
    list(
      uri = "data://small",
      name = "data://small",
      description = "",
      mimeType = "text/plain"
    )
  )
  expect_equal(
    listed[[5]],
    list(
      uri = "data://full",
      name = "Full",
      description = "Described",
      mimeType = "application/json",
      `_meta` = list(k = "v")
    )
  )

  expect_equal(
    app$read_resource("data://small"),
    list(uri = "data://small", mimeType = "text/plain", text = "hello")
  )
  # Functions are called on each read; json objects become plain strings.
  fn <- app$read_resource("data://fn")$text
  expect_identical(fn, '{"a":[1,2,3]}')
  expect_false(inherits(fn, "json"))
  expect_equal(app$read_resource("data://lines")$text, "a\nb")
  expect_equal(app$read_resource("data://full")[["_meta"]], list(k = "v"))

  expect_true(app$has_resource("data://fn"))
  expect_false(app$has_resource("data://nope"))
})

test_that("resource functions run on every read", {
  count <- 0
  app <- mcp_app(
    htmltools::div(),
    resources = list("data://count" = function() {
      count <<- count + 1
      as.character(count)
    })
  )

  expect_equal(app$read_resource("data://count")$text, "1")
  expect_equal(app$read_resource("data://count")$text, "2")
})

test_that("reading an unknown resource is an error", {
  app <- mcp_app(htmltools::div(), name = "missing")
  err <- expect_error(
    app$read_resource("data://missing"),
    class = "shinymcp_error_resource"
  )
  expect_equal(err$uri, "data://missing")
})

test_that("extra resources are validated", {
  expect_error(
    mcp_app(htmltools::div(), resources = list("x")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), resources = list("a://b" = 1)),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(htmltools::div(), resources = list("a://b" = list(content = 1))),
    class = "shinymcp_error_validation"
  )
})

# ---- Running tools ----

test_that("call_tool() returns the tool's R value", {
  app <- helper_greeter_app()
  expect_equal(
    app$call_tool("greet", list(name = "Ada")),
    list(message = "Hello, Ada!")
  )
  expect_equal(app$call_tool("greet"), list(message = "Hello, world!"))
  expect_equal(app$call_tool("greet", NULL), list(message = "Hello, world!"))
})

test_that("run_tool() returns an MCP tool result", {
  app <- helper_greeter_app()
  result <- app$run_tool("greet", list(name = "Ada"))

  expect_equal(
    result$content,
    list(list(type = "text", text = "message: Hello, Ada!"))
  )
  expect_equal(result$structuredContent, list(message = "Hello, Ada!"))
  expect_equal(result[["_meta"]][["shinymcp/view"]]$tool, "greet")
  expect_null(result$isError)
})

test_that("errors propagate from call_tool() and become results in run_tool()", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "boom", fun = function() stop("kaboom"))),
    name = "failing"
  )

  expect_error(app$call_tool("boom"), "kaboom")
  result <- app$run_tool("boom")
  expect_true(result$isError)
  expect_equal(result$content[[1]]$text, "Error: kaboom")
})

test_that("unknown tools are an error in call_tool() and run_tool()", {
  app <- mcp_app(htmltools::div(), tools = list(), name = "empty")

  expect_error(
    app$call_tool("nonexistent"),
    class = "shinymcp_error_tool_not_found"
  )
  expect_error(
    app$run_tool("nonexistent"),
    class = "shinymcp_error_tool_not_found"
  )
  expect_error(app$call_tool(NULL), class = "shinymcp_error_tool_not_found")
})

test_that("run_tool() passes finished MCP results through", {
  wire <- structure(
    list(
      content = list(list(type = "text", text = "as is")),
      structuredContent = list(a = 1)
    ),
    class = "shinymcp_wire_result"
  )
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "wire", fun = function() wire)),
    name = "wire"
  )

  expect_equal(app$run_tool("wire"), unclass(wire))
})

test_that("run_tool() passes the caller to the tool", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "who", fun = function() mcp_request()$caller)),
    name = "caller"
  )

  expect_equal(app$run_tool("who")$content[[1]]$text, "model")
  expect_equal(
    app$run_tool("who", context = list(caller = "app"))$content[[1]]$text,
    "app"
  )
})

# ---- Printing ----

test_that("apps print a summary of their tools", {
  app <- two_tool_app(
    tool_visibility = list(approve = "app"),
    description = "Greets people."
  )
  expect_snapshot(print(app))
})

test_that("apps without tools say so", {
  expect_snapshot(print(mcp_app(
    htmltools::div(),
    name = "empty",
    version = "2.0.0"
  )))
})

test_that("apps backed by a Shiny server say so", {
  runtime <- list(bridge_config = function() list())
  app <- mcp_app(htmltools::div(), name = "live", runtime = runtime)
  expect_snapshot(print(app))
})

test_that("print() returns the app invisibly", {
  app <- mcp_app(htmltools::div())
  utils::capture.output(out <- withVisible(print(app)))
  expect_false(out$visible)
  expect_identical(out$value, app)
})

test_that("app names that aren't URI-safe are encoded in the resource URI", {
  app <- mcp_app(htmltools::div("hi"), name = "My Cars! (v2)")
  expect_identical(app$resource_uri(), "ui://My%20Cars%21%20%28v2%29")
  expect_true(app$has_resource(app$resource_uri()))
})

test_that("theme wraps a fragment but refuses a whole page", {
  skip_if_not_installed("bslib")
  skip_if_not_installed("shiny")
  themed <- mcp_app(htmltools::div("hi"), theme = bslib::bs_theme(version = 5))
  expect_match(themed$html_resource(), "bootstrap", fixed = TRUE)
  expect_error(
    mcp_app(shiny::fluidPage("hi"), theme = bslib::bs_theme()),
    "isn't already a page",
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_app(bslib::page_fluid("hi"), theme = bslib::bs_theme()),
    class = "shinymcp_error_validation"
  )
})
