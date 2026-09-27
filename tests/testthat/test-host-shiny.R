# Hosting MCP Apps in Shiny (R/host-shiny.R, R/host-base.R)

host_app <- function(...) {
  mcp_app(
    htmltools::tagList(mcp_text_input("name", "Name"), mcp_text("message")),
    tools = list(
      list(
        name = "greet",
        description = "Greet someone.",
        fun = function(name = "world") {
          who <- mcp_request()$user %||% "nobody"
          list(message = paste0("Hello ", name, " (for ", who, ")"))
        }
      ),
      list(name = "approve", description = "Approve.", fun = function() {
        "approved"
      }),
      list(name = "boom", description = "Fails.", fun = function() {
        stop("kaboom")
      })
    ),
    name = "greeter",
    tool_visibility = list(approve = "app"),
    ...
  )
}

# ---- Markup ----

test_that("mcp_host_ui() renders the host shell", {
  skip_if_not_installed("shiny")
  ui <- mcp_host_ui("card", height = "400px")
  html <- as.character(ui)

  expect_match(
    html,
    '<div id="card-host" class="shinymcp-host" data-shinymcp-host=""',
    fixed = TRUE
  )
  expect_match(html, 'data-shinymcp-height="400px"', fixed = TRUE)
  expect_match(html, 'class="shinymcp-host-toolbar"', fixed = TRUE)
  expect_match(
    html,
    'data-shinymcp-host-busy="" hidden role="status">Working',
    fixed = TRUE
  )
  expect_match(
    html,
    'data-shinymcp-action="execute" hidden>Run</button>',
    fixed = TRUE
  )
  expect_match(
    html,
    'data-shinymcp-action="fullscreen" aria-pressed="false">Full screen</button>',
    fixed = TRUE
  )
  expect_match(
    html,
    'data-shinymcp-host-error="" role="alert" hidden',
    fixed = TRUE
  )
  expect_match(
    html,
    '<iframe class="shinymcp-host-frame" data-shinymcp-host-frame="" title="MCP App"></iframe>',
    fixed = TRUE
  )
  # The server half sends the configuration later.
  expect_null(helper_markup_config(html))
  expect_false(grepl("data-shinymcp-border", html, fixed = TRUE))

  deps <- htmltools::findDependencies(ui)
  expect_equal(vapply(deps, `[[`, character(1), "name"), "shinymcp-host")
  expect_equal(deps[[1]]$script, "shinymcp-host.js")
  expect_equal(deps[[1]]$stylesheet, "shinymcp-host.css")
})

test_that("mcp_host_ui() follows the app's size by default", {
  skip_if_not_installed("shiny")
  expect_match(
    as.character(mcp_host_ui("x")),
    'data-shinymcp-height="auto"',
    fixed = TRUE
  )
})

test_that("host markup carries the configuration and title", {
  config <- list(
    instanceId = "i1",
    title = "Greeter <1>",
    prefersBorder = FALSE,
    html = "<p>page</p>"
  )
  html <- as.character(mcp_host_markup("i1", config = config))

  expect_match(
    html,
    '<span class="shinymcp-host-title">Greeter &lt;1&gt;</span>',
    fixed = TRUE
  )
  expect_match(html, 'title="Greeter &lt;1&gt;"', fixed = TRUE)
  expect_match(html, 'data-shinymcp-border="false"', fixed = TRUE)
  expect_equal(helper_markup_config(html), config)

  bare <- as.character(mcp_host_markup(
    "i2",
    config = config,
    toolbar = FALSE,
    title = "Own title"
  ))
  expect_false(grepl("shinymcp-host-toolbar", bare, fixed = TRUE))
  expect_match(bare, 'title="Own title"', fixed = TRUE)
})

test_that("host markup leaves out the border attribute unless the app declines one", {
  html <- as.character(mcp_host_markup(
    "i1",
    config = list(prefersBorder = TRUE)
  ))
  expect_false(grepl("data-shinymcp-border", html, fixed = TRUE))
})

test_that("DOM ids are made safe", {
  expect_equal(sanitize_dom_id("host-abc_1"), "host-abc_1")
  expect_equal(sanitize_dom_id("a b.c"), "a-b-c")
  expect_equal(sanitize_dom_id("1st"), "shinymcp-1st")
})

test_that("root_shiny_session unwraps Shiny session proxies", {
  skip_if_not_installed("shiny")
  root <- shiny::MockShinySession$new()
  proxy <- root$makeScope("module")

  expect_s3_class(proxy, "session_proxy")
  expect_identical(root_shiny_session(root), root)
  expect_identical(root_shiny_session(proxy), root)
  expect_identical(root_shiny_session(proxy$makeScope("inner")), root)
  expect_null(root_shiny_session(NULL))
})

test_that("root_shiny_session keeps sessions without a root scope", {
  plain <- structure(
    list(userData = new.env(parent = emptyenv())),
    class = "ShinySession"
  )
  expect_identical(root_shiny_session(plain), plain)
})

test_that("there is no active session outside Shiny", {
  skip_if_not_installed("shiny")
  expect_null(active_shiny_session())
})

# ---- mcp_embed() ----

test_that("mcp_embed() needs a session or an id", {
  skip_if_not_installed("shiny")
  app <- mcp_app(htmltools::tags$div("test"), name = "embed-test")

  expect_error(
    mcp_embed(app),
    "inside a running Shiny session",
    class = "shinymcp_error"
  )

  ui <- mcp_embed(app, id = "emb", height = "300px")
  expect_equal(
    as.character(ui),
    as.character(mcp_host_ui("emb", height = "300px"))
  )
})

test_that("mcp_embed() in a session registers the app and embeds its configuration", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  local_mocked_bindings(active_shiny_session = function() session)
  app <- host_app(title = "Greeter")

  ui <- mcp_embed(
    app,
    arguments = list(name = "Ada"),
    trigger = "manual",
    height = "300px"
  )
  html <- as.character(ui)
  config <- helper_markup_config(html)
  instances <- ls(session$userData$.shinymcp_hosts$instances)

  expect_length(instances, 1)
  expect_equal(config$instanceId, instances)
  expect_match(instances, "^host-greeter-")
  expect_match(
    html,
    paste0('<div id="', instances, '" class="shinymcp-host"'),
    fixed = TRUE
  )
  expect_match(html, 'data-shinymcp-height="300px"', fixed = TRUE)
  expect_match(
    html,
    '<span class="shinymcp-host-title">Greeter</span>',
    fixed = TRUE
  )
  expect_equal(config$trigger, "manual")
  expect_equal(config$height, "300px")
  expect_equal(config$entryTool, "greet")
  expect_equal(config$initialArguments, list(name = "Ada"))

  second <- as.character(mcp_embed(app, id = "1st"))
  expect_match(second, '<div id="shinymcp-1st"', fixed = TRUE)
  expect_length(ls(session$userData$.shinymcp_hosts$instances), 2)
})

# ---- Registering instances ----

test_that("registering an instance builds the host configuration", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  app <- host_app(
    title = "Greeter",
    csp = list(connect_domains = "https://api.example.com"),
    permissions = "clipboard_write",
    prefers_border = FALSE,
    trigger = "submit",
    debounce_ms = 400
  )

  registered <- register_shiny_host_instance(
    session,
    app,
    instance_id = "i1",
    height = "320px"
  )
  config <- registered$config

  expect_true(is.environment(registered$state))
  expect_identical(
    session$userData$.shinymcp_hosts$instances$i1,
    registered$state
  )
  expect_equal(config$instanceId, "i1")
  expect_equal(config$title, "Greeter")
  expect_equal(config$version, as.character(utils::packageVersion("shinymcp")))
  expect_equal(
    as.character(config$csp$connectDomains),
    "https://api.example.com"
  )
  expect_equal(names(config$permissions), "clipboardWrite")
  expect_false(config$prefersBorder)
  expect_equal(config$height, "320px")
  expect_equal(config$trigger, "submit")
  # The first tool the model may call opens the app.
  expect_equal(config$entryTool, "greet")
  expect_equal(config$tool$name, "greet")
  expect_equal(config$tool[["_meta"]][["ui"]]$resourceUri, "ui://greeter")
  expect_equal(as.character(config$appTools), c("greet", "approve", "boom"))
  expect_null(config$initialResult)
  expect_equal(as.character(to_json(config$initialArguments)), "{}")

  # The page inside carries the interaction settings.
  page <- helper_page_config(config$html)
  expect_equal(page$trigger, "submit")
  expect_equal(page$debounceMs, 400)
})

test_that("registration takes an explicit entry tool, arguments, and result", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  app <- host_app()
  result <- app$run_tool("greet", list(name = "Ada"))

  config <- register_shiny_host_instance(
    session,
    app,
    instance_id = "i1",
    tool = "approve",
    arguments = list(id = 3),
    result = result
  )$config

  expect_equal(config$entryTool, "approve")
  expect_equal(config$tool$name, "approve")
  expect_equal(config$initialArguments, list(id = 3))
  expect_equal(config$initialResult, result)
})

test_that("host settings override the app's interaction defaults", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  app <- host_app(trigger = "submit", debounce_ms = 400)

  config <- register_shiny_host_instance(
    session,
    app,
    instance_id = "i1",
    trigger = "change",
    debounce_ms = 50
  )$config

  expect_equal(config$trigger, "change")
  page <- helper_page_config(config$html)
  expect_equal(page$trigger, "change")
  expect_equal(page$debounceMs, 50)

  expect_error(register_shiny_host_instance(
    session,
    app,
    instance_id = "i2",
    trigger = "bogus"
  ))
})

test_that("resolve_host_interaction() falls back to debounce at 250 ms", {
  expect_equal(
    resolve_host_interaction(mcp_app(htmltools::div())),
    list(trigger = "debounce", debounce_ms = 250)
  )
  app <- mcp_app(htmltools::div(), trigger = "change", debounce_ms = 10)
  expect_equal(
    resolve_host_interaction(app),
    list(trigger = "change", debounce_ms = 10)
  )
  expect_equal(
    resolve_host_interaction(app, trigger = "manual", debounce_ms = 99),
    list(trigger = "manual", debounce_ms = 99)
  )
})

test_that("the default entry tool is the first one the model may call", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(
      list(name = "internal", fun = function() 1, visibility = "app"),
      list(name = "open", fun = function() 1)
    )
  )
  expect_equal(default_entry_tool(app), "open")
  expect_null(default_entry_tool(mcp_app(htmltools::div())))

  expect_equal(tool_definition_for(app, "open")$name, "open")
  expect_null(tool_definition_for(app, "missing"))
})

test_that("apps without tools have no entry tool", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  config <- register_shiny_host_instance(
    session,
    mcp_app(htmltools::div()),
    instance_id = "i1"
  )$config

  expect_null(config$entryTool)
  expect_null(config$tool)
  expect_length(config$appTools, 0)
})

test_that("registration refuses a tool the app doesn't have", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()

  expect_error(
    register_shiny_host_instance(
      session,
      host_app(),
      instance_id = "i1",
      tool = "nope"
    ),
    class = "shinymcp_error_validation"
  )
})

test_that("a failed registration leaves no instance behind", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()

  try(
    register_shiny_host_instance(
      session,
      host_app(),
      instance_id = "i1",
      tool = "nope"
    ),
    silent = TRUE
  )
  hosts <- session$userData$.shinymcp_hosts
  expect_true(is.null(hosts) || length(ls(hosts$instances)) == 0)
})

test_that("a session keeps one registry for all its hosted apps", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()

  first <- ensure_shiny_host_registry(session)
  register_shiny_host_instance(session, host_app(), instance_id = "i1")
  register_shiny_host_instance(session, host_app(), instance_id = "i2")

  expect_identical(ensure_shiny_host_registry(session), first)
  expect_setequal(ls(first$instances), c("i1", "i2"))
  expect_error(ensure_shiny_host_registry(NULL), "running Shiny session")
})

test_that("hosted apps are disposed when the session ends", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  one <- register_shiny_host_instance(
    session,
    host_app(),
    instance_id = "i1"
  )$state
  two <- register_shiny_host_instance(
    session,
    host_app(),
    instance_id = "i2"
  )$state

  expect_false(one$disposed)
  session$close()
  expect_true(one$disposed)
  expect_true(two$disposed)
})

test_that("host configurations with HTML comments stay valid JSON", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  app <- mcp_app(
    htmltools::tagList(htmltools::HTML("<!-- a note -->"), mcp_text("x")),
    name = "commented"
  )

  config <- register_shiny_host_instance(
    session,
    app,
    instance_id = "i1"
  )$config
  parsed <- helper_markup_config(as.character(mcp_host_markup(
    "i1",
    config = config
  )))
  expect_equal(parsed$instanceId, "i1")
})

# ---- Answering the page ----

test_that("requests are answered after the reactive flush, over a custom message", {
  skip_if_not_installed("later")
  session <- helper_fake_session(user = "ada")
  state <- new_mcp_host_state(host_app(), instance_id = "i1")
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    helper_host_request(
      "i1",
      "tools/call",
      list(name = "greet", arguments = list(name = "Bo")),
      id = 7
    )
  )
  expect_length(session$sent, 0)

  later::run_now()
  expect_length(session$sent, 1)
  sent <- session$sent[[1]]
  expect_equal(sent$type, "shinymcp-host-response")
  expect_equal(sent$message$instanceId, "i1")
  expect_equal(sent$message$requestId, "r1")
  response <- sent$message$response
  expect_equal(response$jsonrpc, "2.0")
  expect_equal(response$id, 7)
  expect_null(attr(response, "http_status"))
  expect_equal(
    response$result$structuredContent,
    list(message = "Hello Bo (for ada)")
  )

  # The call is recorded on the host state.
  expect_equal(state$last_tool_call$name, "greet")
  expect_equal(state$last_tool_call$arguments, list(name = "Bo"))
  expect_equal(state$last_tool_call$result, response$result)
})

test_that("tool calls from the page run in process as the session's user", {
  skip_if_not_installed("later")
  seen <- NULL
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "who", fun = function() {
      seen <<- mcp_request()
      "ok"
    })),
    name = "who"
  )
  session <- helper_fake_session(user = "ada", groups = c("staff", "admins"))
  registry <- helper_host_registry(i1 = new_mcp_host_state(app, "i1"))

  handle_host_event(
    session,
    registry,
    helper_host_request("i1", "tools/call", list(name = "who"))
  )
  later::run_now()

  expect_equal(seen$transport, "in-process")
  expect_equal(seen$user, "ada")
  expect_equal(seen$groups, c("staff", "admins"))
  expect_equal(seen$caller, "model")
})

test_that("the page can read the app's resources", {
  skip_if_not_installed("later")
  app <- host_app()
  session <- helper_fake_session()
  registry <- helper_host_registry(i1 = new_mcp_host_state(app, "i1"))

  handle_host_event(
    session,
    registry,
    helper_host_request("i1", "resources/read", list(uri = "ui://greeter"))
  )
  later::run_now()

  contents <- session$sent[[1]]$message$response$result$contents[[1]]
  expect_equal(contents$uri, "ui://greeter")
  expect_equal(contents$text, app$html_resource())
})

test_that("requests for an app that's gone get an error at once", {
  session <- helper_fake_session()
  registry <- helper_host_registry()

  handle_host_event(
    session,
    registry,
    helper_host_request("gone", "tools/call", list(name = "greet"), id = 9)
  )

  expect_length(session$sent, 1)
  response <- session$sent[[1]]$message$response
  expect_equal(session$sent[[1]]$message$instanceId, "gone")
  expect_equal(response$id, 9)
  expect_equal(response$error$code, RPC_INVALID_REQUEST)
  expect_equal(response$error$message, "This app is no longer running.")
})

test_that("bad requests and unknown tools get JSON-RPC errors", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1")
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    list(
      instanceId = "i1",
      requestId = "r1",
      message = list(id = 10, method = "tools/call")
    )
  )
  handle_host_event(
    session,
    registry,
    helper_host_request(
      "i1",
      "tools/call",
      list(name = "nope"),
      id = 11,
      request_id = "r2"
    )
  )
  later::run_now()

  expect_equal(
    session$sent[[1]]$message$response$error$code,
    RPC_INVALID_REQUEST
  )
  expect_equal(session$sent[[2]]$message$requestId, "r2")
  expect_equal(
    session$sent[[2]]$message$response$error$code,
    RPC_INVALID_PARAMS
  )
  expect_match(
    session$sent[[2]]$message$response$error$message,
    "Unknown tool: nope"
  )
  expect_null(state$last_tool_call)
})

test_that("tool errors are answered as error results and recorded", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1")
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    helper_host_request("i1", "tools/call", list(name = "boom"))
  )
  later::run_now()

  result <- session$sent[[1]]$message$response$result
  expect_true(result$isError)
  expect_equal(result$content[[1]]$text, "Error: kaboom")
  expect_true(state$last_tool_call$result$isError)
})

test_that("notifications update the host state", {
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1")
  registry <- helper_host_registry(i1 = state)
  notify <- function(method, params) {
    handle_host_event(
      session,
      registry,
      list(
        instanceId = "i1",
        type = "notification",
        method = method,
        params = params
      )
    )
  }

  notify(
    "ui/update-model-context",
    list(content = list(list(type = "text", text = "ctx")))
  )
  notify(
    "ui/message",
    list(role = "user", content = list(list(type = "text", text = "hi")))
  )
  notify("ui/notifications/size-changed", list(width = 320, height = 240))

  expect_equal(state$model_context$content[[1]]$text, "ctx")
  expect_length(state$messages, 1)
  expect_equal(state$messages[[1]]$role, "user")
  expect_equal(state$last_size, list(width = 320, height = 240))
  expect_length(session$sent, 0)

  # Notifications for unknown instances are ignored.
  expect_no_error(handle_host_event(
    session,
    registry,
    list(
      instanceId = "gone",
      type = "notification",
      method = "ui/message",
      params = list()
    )
  ))
})

test_that("dispose events shut the instance down and forget it", {
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1")
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    list(instanceId = "i1", type = "dispose")
  )
  expect_true(state$disposed)
  expect_length(ls(registry$instances), 0)
  expect_no_error(handle_host_event(
    session,
    registry,
    list(instanceId = "i1", type = "dispose")
  ))
  expect_length(session$sent, 0)
})

# ---- Host state ----

test_that("new host state starts empty", {
  app <- host_app()
  state <- new_mcp_host_state(app, instance_id = "i1")

  expect_identical(state$app, app)
  expect_s3_class(state$server, "McpServer")
  expect_true(is.environment(state$session))
  expect_equal(state$instance_id, "i1")
  expect_null(state$model_context)
  expect_null(state$last_tool_call)
  expect_null(state$last_size)
  expect_equal(state$messages, list())
  expect_false(state$disposed)
  expect_match(new_mcp_host_state(app)$instance_id, "^host-")
})

test_that("notifications call the host's callbacks", {
  state <- new_mcp_host_state(host_app())
  seen <- list()
  state$on_model_context <- function(value) seen$context <<- value
  state$on_message <- function(value) seen$message <<- value
  state$on_size <- function(value) seen$size <<- value

  mcp_host_notification(
    state,
    "ui/update-model-context",
    list(structuredContent = list(name = "Ada"))
  )
  mcp_host_notification(state, "ui/message", list(role = "user"))
  mcp_host_notification(state, "ui/message", list(role = "user", n = 2))
  mcp_host_notification(
    state,
    "ui/notifications/size-changed",
    list(height = 200)
  )
  mcp_host_notification(state, "ui/unknown", list())
  mcp_host_notification(state, NULL, list())

  expect_equal(seen$context$structuredContent$name, "Ada")
  expect_equal(seen$message$n, 2)
  expect_length(state$messages, 2)
  expect_equal(seen$size, list(height = 200))
  expect_false(state$disposed)

  mcp_host_notification(state, "ui/resource-teardown", list())
  expect_true(state$disposed)
})

test_that("a failing callback is a warning, not an error", {
  state <- new_mcp_host_state(host_app())
  state$on_model_context <- function(value) stop("callback broke")

  expect_warning(
    mcp_host_notification(state, "ui/update-model-context", list(a = 1)),
    "callback broke"
  )
  expect_equal(state$model_context, list(a = 1))
})

test_that("recorded calls remember the views they opened", {
  state <- new_mcp_host_state(host_app())
  calls <- list()
  state$on_tool_call <- function(value) calls[[length(calls) + 1]] <<- value
  view_result <- function(id) {
    list(`_meta` = list(`shinymcp/view` = list(instance = id)))
  }

  mcp_host_record_call(state, "open", list(a = 1), view_result("v1"))
  mcp_host_record_call(state, "open", NULL, view_result("v2"))
  mcp_host_record_call(state, "open", NULL, view_result("v1"))
  mcp_host_record_call(state, "plain", NULL, list(content = list()))

  expect_equal(state$views, c("v1", "v2"))
  expect_length(calls, 4)
  expect_equal(
    calls[[1]],
    list(name = "open", arguments = list(a = 1), result = view_result("v1"))
  )
  expect_equal(state$last_tool_call$name, "plain")
  expect_equal(state$last_tool_call$arguments, list())
})

test_that("disposing closes the live views the host opened, once", {
  closed <- character()
  runtime <- list(
    bridge_config = function() list(),
    view = function(arguments, context = list()) {
      closed <<- c(closed, paste(arguments$action, arguments$instance))
      NULL
    }
  )
  app <- mcp_app(htmltools::div(), name = "live", runtime = runtime)
  state <- new_mcp_host_state(app)
  state$views <- c("v1", "v2")

  mcp_host_dispose(state)
  expect_true(state$disposed)
  expect_equal(closed, c("close v1", "close v2"))

  mcp_host_dispose(state)
  expect_equal(closed, c("close v1", "close v2"))
})

test_that("disposing an app without views or a runtime is harmless", {
  state <- new_mcp_host_state(host_app())
  expect_no_error(mcp_host_dispose(state))
  expect_true(state$disposed)
})

test_that("disposing a host closes the Shiny sessions it opened", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  shiny_app <- shiny::shinyApp(
    shiny::fluidPage(
      shiny::textInput("name", "Name", "x"),
      shiny::textOutput("greeting")
    ),
    function(input, output, session) {
      output$greeting <- shiny::renderText(paste("Hi", input$name))
    }
  )
  app <- as_mcp_app(shiny_app, name = "live")
  session <- helper_fake_session()
  state <- new_mcp_host_state(app, "i1")
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    helper_host_request(
      "i1",
      "tools/call",
      list(name = "live", arguments = list(name = "Ada"))
    )
  )
  later::run_now()

  result <- session$sent[[1]]$message$response$result
  expect_match(result$content[[1]]$text, "Hi Ada", fixed = TRUE)
  expect_length(state$views, 1)
  expect_equal(app$runtime()$instance_count(), 1)

  handle_host_event(
    session,
    registry,
    list(instanceId = "i1", type = "dispose")
  )
  expect_equal(app$runtime()$instance_count(), 0)
})

# ---- mcp_host_server() ----

test_that("mcp_host_server() sends the app to the page once the UI is flushed", {
  skip_if_not_installed("shiny")
  capture <- helper_capture_session()
  app <- host_app(title = "Greeter")

  shiny::testServer(
    function(id) {
      mcp_host_server(id, app, arguments = list(name = "Ada"), height = "250px")
    },
    args = list(id = "h"),
    session = capture$session,
    {
      expect_setequal(
        names(session$returned),
        c(
          "model_context",
          "last_tool_call",
          "last_result",
          "messages",
          "instance_id",
          "execute",
          "reset",
          "dispose"
        )
      )
      expect_length(capture$messages(), 0)

      session$flushReact()
      init <- capture$messages("shinymcp-host-init")
      expect_length(init, 1)
      expect_equal(init[[1]]$id, "h-host")
      config <- init[[1]]$config
      expect_equal(config$instanceId, session$returned$instance_id())
      expect_match(config$instanceId, "^host-greeter-")
      expect_equal(config$title, "Greeter")
      expect_equal(config$height, "250px")
      expect_equal(config$entryTool, "greet")
      expect_equal(config$initialArguments, list(name = "Ada"))
      expect_match(config$html, "<!DOCTYPE html>", fixed = TRUE)

      # Only once.
      session$flushReact()
      expect_length(capture$messages("shinymcp-host-init"), 1)
    }
  )
})

test_that("mcp_host_server() answers the page and exposes what happened", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  capture <- helper_capture_session()
  app <- host_app()

  shiny::testServer(
    function(id) mcp_host_server(id, app),
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      root <- session$rootScope()
      id <- host$instance_id()
      expect_null(host$last_tool_call())
      expect_null(host$model_context())
      expect_equal(host$messages(), list())

      root$setInputs(
        shinymcp_host_event = helper_host_request(
          id,
          "tools/call",
          list(name = "greet", arguments = list(name = "Grace"))
        )
      )
      later::run_now()
      session$flushReact()

      responses <- capture$messages("shinymcp-host-response")
      expect_length(responses, 1)
      expect_equal(responses[[1]]$instanceId, id)
      expect_equal(host$last_tool_call()$name, "greet")
      expect_equal(host$last_tool_call()$arguments, list(name = "Grace"))
      expect_equal(
        host$last_result()$structuredContent,
        list(message = "Hello Grace (for nobody)")
      )

      root$setInputs(
        shinymcp_host_event = list(
          instanceId = id,
          type = "notification",
          method = "ui/update-model-context",
          params = list(structuredContent = list(name = "Grace"))
        )
      )
      expect_equal(
        host$model_context(),
        list(structuredContent = list(name = "Grace"))
      )

      for (text in c("first", "second")) {
        root$setInputs(
          shinymcp_host_event = list(
            instanceId = id,
            type = "notification",
            method = "ui/message",
            params = list(
              role = "user",
              content = list(list(type = "text", text = text))
            )
          )
        )
      }
      expect_length(host$messages(), 2)
      expect_equal(host$messages()[[2]]$content[[1]]$text, "second")
    }
  )
})

test_that("mcp_host_server() commands reach the page", {
  skip_if_not_installed("shiny")
  capture <- helper_capture_session()

  shiny::testServer(
    function(id) mcp_host_server(id, host_app()),
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      id <- host$instance_id()

      host$execute(list(name = "Zed"))
      host$execute()
      host$reset()
      host$dispose()

      commands <- capture$messages("shinymcp-host-command")
      expect_equal(
        commands[[1]],
        list(
          instanceId = id,
          command = "execute",
          arguments = list(name = "Zed")
        )
      )
      expect_equal(commands[[2]], list(instanceId = id, command = "execute"))
      expect_equal(commands[[3]], list(instanceId = id, command = "reset"))
      expect_equal(commands[[4]], list(instanceId = id, command = "dispose"))
      state <- session$rootScope()$userData$.shinymcp_hosts$instances[[id]]
      expect_true(state$disposed)
    }
  )
})

test_that("mcp_host_server() refuses an entry tool the app doesn't have", {
  skip_if_not_installed("shiny")
  expect_error(
    shiny::testServer(
      function(id) mcp_host_server(id, host_app(), tool = "nope"),
      args = list(id = "h"),
      {
        NULL
      }
    ),
    class = "shinymcp_error_validation"
  )
})
