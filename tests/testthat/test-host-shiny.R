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
      list(name = "peek", description = "For the model.", fun = function() {
        "peeked"
      }),
      list(name = "boom", description = "Fails.", fun = function() {
        stop("kaboom")
      })
    ),
    name = "greeter",
    tool_visibility = list(approve = "app", peek = "model"),
    ...
  )
}

# The attach event the host script sends for a card or pane.
host_attach_event <- function(descriptor, request_id = "a1") {
  list(
    type = "attach",
    instanceId = descriptor$instanceId,
    requestId = request_id,
    descriptor = descriptor
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
  # The server half sends the descriptor later.
  expect_null(helper_markup_config(html))
  expect_false(grepl("data-shinymcp-host-fallback", html, fixed = TRUE))

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

test_that("host markup carries the descriptor, title, and text fallback", {
  config <- list(instanceId = "i1", source = "greeter", title = "Greeter <1>")
  html <- as.character(mcp_host_markup(
    "i1",
    config = config,
    fallback = "Hello <b>"
  ))

  expect_match(
    html,
    '<span class="shinymcp-host-title">Greeter &lt;1&gt;</span>',
    fixed = TRUE
  )
  expect_match(html, 'title="Greeter &lt;1&gt;"', fixed = TRUE)
  expect_equal(helper_markup_config(html), config)
  # Shown only when the app can't be.
  expect_match(
    html,
    'data-shinymcp-host-fallback="" hidden>Hello &lt;b&gt;</div>',
    fixed = TRUE
  )

  bare <- as.character(mcp_host_markup(
    "i2",
    config = config,
    toolbar = FALSE,
    title = "Own title"
  ))
  expect_false(grepl("shinymcp-host-toolbar", bare, fixed = TRUE))
  expect_match(bare, 'title="Own title"', fixed = TRUE)
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

# ---- Registering instances ----

test_that("registering an instance keeps its source and builds a descriptor", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  app <- host_app(title = "Greeter", trigger = "submit", debounce_ms = 400)

  registered <- register_shiny_host_instance(
    session,
    app,
    instance_id = "i1",
    height = "320px"
  )
  config <- registered$config
  state <- registered$state
  registry <- session$userData$.shinymcp_hosts

  expect_identical(registry$instances$i1, state)
  expect_identical(registry$sources$greeter, state$source)
  expect_equal(state$kind, "pane")
  expect_equal(
    config[c("instanceId", "source", "tool", "title", "height", "trigger")],
    list(
      instanceId = "i1",
      source = "greeter",
      tool = "greet",
      title = "Greeter",
      height = "320px",
      trigger = "submit"
    )
  )
  expect_equal(as.character(to_json(config$arguments)), "{}")
  expect_null(config$result)
  expect_equal(config$version, as.character(utils::packageVersion("shinymcp")))
  # The page isn't in the descriptor; it's read when the card attaches.
  expect_null(config$html)
  expect_equal(state$config, list(trigger = "submit", debounceMs = 400))
})

test_that("registration takes a tool, arguments, a result, and a kind", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  app <- host_app()
  result <- app$run_tool("greet", list(name = "Ada"))

  registered <- register_shiny_host_instance(
    session,
    app,
    instance_id = "i1",
    tool = "approve",
    arguments = list(id = 3),
    result = result,
    kind = "card",
    title = "Approvals"
  )

  expect_equal(registered$config$tool, "approve")
  expect_equal(registered$config$arguments, list(id = 3))
  expect_equal(registered$config$result, result)
  expect_equal(registered$config$title, "Approvals")
  expect_equal(registered$state$kind, "card")
})

test_that("host settings override the app's interaction defaults", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  app <- host_app(trigger = "submit", debounce_ms = 400)

  registered <- register_shiny_host_instance(
    session,
    app,
    instance_id = "i1",
    trigger = "change",
    debounce_ms = 50
  )
  expect_equal(registered$config$trigger, "change")
  expect_equal(
    registered$state$config,
    list(trigger = "change", debounceMs = 50)
  )

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

test_that("the default tool is the first the model may call that shows an app", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(
      list(name = "internal", fun = function() 1, visibility = "app"),
      list(name = "open", fun = function() 1)
    )
  )
  expect_equal(default_source_tool(as_host_source(app)), "open")
  expect_null(default_source_tool(as_host_source(mcp_app(htmltools::div()))))
})

test_that("a tool with only the older flat ui/resourceUri key is read", {
  flat <- list(name = "old", `_meta` = list(`ui/resourceUri` = "ui://old"))
  expect_equal(tool_resource_uri(flat), "ui://old")
  expect_true(tool_wire_visible_to(flat, "app"))
  expect_true(tool_wire_visible_to(flat, "model"))
  # A _meta.ui that isn't an object is ignored, not an error.
  odd <- list(name = "odd", `_meta` = list(ui = "ui://odd"))
  expect_null(tool_resource_uri(odd))
  expect_true(tool_wire_visible_to(odd, "app"))
})

test_that("registration refuses a tool the source doesn't have, or no tool", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()

  expect_error(
    register_shiny_host_instance(session, host_app(), "i1", tool = "nope"),
    "has no tool called",
    class = "shinymcp_error_validation"
  )
  expect_error(
    register_shiny_host_instance(session, mcp_app(htmltools::div()), "i2"),
    "has no tool to open",
    class = "shinymcp_error_validation"
  )
  hosts <- session$userData$.shinymcp_hosts
  expect_length(ls(hosts$instances), 0)
})

test_that("a session keeps one registry for all its hosted apps", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()

  first <- ensure_shiny_host_registry(session)
  register_shiny_host_instance(session, host_app(), instance_id = "i1")
  register_shiny_host_instance(session, host_app(), instance_id = "i2")

  expect_identical(ensure_shiny_host_registry(session), first)
  expect_setequal(ls(first$instances), c("i1", "i2"))
  expect_setequal(ls(first$sources), "greeter")
  expect_error(ensure_shiny_host_registry(NULL), "running Shiny session")
})

test_that("hosted apps are disposed when the session ends", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  one <- register_shiny_host_instance(session, host_app(), "i1")$state
  two <- register_shiny_host_instance(session, host_app(), "i2")$state

  expect_false(one$disposed)
  session$close()
  expect_true(one$disposed)
  expect_true(two$disposed)
})

test_that("descriptors with HTML comments stay valid JSON in the markup", {
  skip_if_not_installed("shiny")
  session <- shiny::MockShinySession$new()
  app <- host_app()
  result <- list(content = list(list(type = "text", text = "<!-- a -->")))

  config <- register_shiny_host_instance(
    session,
    app,
    instance_id = "i1",
    result = result
  )$config
  parsed <- helper_markup_config(as.character(mcp_host_markup(
    "i1",
    config = config
  )))
  expect_equal(parsed$result$content[[1]]$text, "<!-- a -->")
})

# ---- Opening: the tool call and attaching ----

test_that("a pane's tool is called in R and its result reaches the page", {
  skip_if_not_installed("later")
  session <- helper_fake_session(user = "ada")
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  state$arguments <- list(name = "Bo")
  registry <- helper_host_registry(i1 = state)

  start_host_call(session, state)
  helper_drain()
  expect_equal(
    state$result$structuredContent,
    list(message = "Hello Bo (for ada)")
  )
  expect_equal(state$last_tool_call$name, "greet")
  # Not attached yet: the result waits for the attach.
  expect_length(session$sent, 0)

  handle_host_event(
    session,
    registry,
    host_attach_event(host_descriptor(state))
  )
  helper_drain()
  attached <- helper_sent(session, "shinymcp-host-attached")
  expect_length(attached, 1)
  reply <- attached[[1]]
  expect_true(reply$ok)
  expect_equal(reply$instanceId, "i1")
  expect_equal(reply$requestId, "a1")
  expect_equal(reply$toolResult, state$result)
  expect_equal(reply$toolInput, list(name = "Bo"))
  expect_equal(reply$tool$name, "greet")
  expect_match(reply$page$html, "<!DOCTYPE html>", fixed = TRUE)
  expect_equal(as.character(reply$appTools), c("greet", "approve", "boom"))
  expect_true(state$attached)
})

test_that("a result that arrives after the attach is sent to the page", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    host_attach_event(host_descriptor(state))
  )
  helper_drain()
  expect_null(helper_sent(session, "shinymcp-host-attached")[[1]]$toolResult)

  start_host_call(session, state)
  helper_drain()
  commands <- helper_sent(session, "shinymcp-host-command")
  expect_length(commands, 1)
  expect_equal(commands[[1]]$command, "tool-result")
  expect_equal(commands[[1]]$result, state$result)
})

test_that("a failed call cancels the tool call in the page", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  state$source$call_async <- function(...) {
    promises::promise_reject(simpleError("no route"))
  }
  state$attached <- TRUE

  start_host_call(session, state)
  helper_drain()
  commands <- helper_sent(session, "shinymcp-host-command")
  expect_equal(commands[[1]]$command, "tool-cancelled")
  expect_equal(commands[[1]]$reason, "no route")
  expect_equal(state$call_error, "no route")
})

test_that("a newer call replaces one still running", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  state$arguments <- list(name = "first")
  start_host_call(session, state)
  state$arguments <- list(name = "second")
  start_host_call(session, state)
  helper_drain()

  expect_equal(
    state$result$structuredContent$message,
    "Hello second (for nobody)"
  )
})

test_that("the page is read once per session, with the pane's settings", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  app <- host_app()
  reads <- 0
  one <- new_mcp_host_state(
    app,
    "i1",
    tool = "greet",
    config = list(trigger = "manual")
  )
  page <- one$source$page_async
  one$source$page_async <- function(...) {
    reads <<- reads + 1
    page(...)
  }
  two <- new_mcp_host_state(
    one$source,
    "i2",
    tool = "greet",
    config = list(trigger = "manual")
  )
  registry <- helper_host_registry(i1 = one, i2 = two)

  handle_host_event(session, registry, host_attach_event(host_descriptor(one)))
  handle_host_event(session, registry, host_attach_event(host_descriptor(two)))
  helper_drain()

  attached <- helper_sent(session, "shinymcp-host-attached")
  expect_length(attached, 2)
  expect_equal(reads, 1)
  expect_equal(helper_page_config(attached[[1]]$page$html)$trigger, "manual")
})

test_that("a restored card attaches from its descriptor without calling the tool", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  app <- host_app()
  calls <- 0
  source <- as_host_source(app)
  call <- source$call
  source$call <- function(...) {
    calls <<- calls + 1
    call(...)
  }
  registry <- new_host_registry()
  register_host_source(registry, source)
  saved <- list(content = list(list(type = "text", text = "saved")))
  descriptor <- list(
    instanceId = "old-card",
    source = "greeter",
    tool = "greet",
    arguments = list(name = "Ada"),
    result = saved
  )

  handle_host_event(session, registry, host_attach_event(descriptor))
  helper_drain()

  reply <- helper_sent(session, "shinymcp-host-attached")[[1]]
  expect_true(reply$ok)
  expect_equal(reply$toolResult, saved)
  expect_equal(reply$toolInput, list(name = "Ada"))
  expect_equal(calls, 0)
  state <- registry$instances[["old-card"]]
  expect_equal(state$kind, "card")
  expect_equal(state$tool, "greet")
})

test_that("cards whose source or tool isn't here can't attach", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  registry <- new_host_registry()
  register_host_source(registry, host_app())

  for (descriptor in list(
    list(instanceId = "c1", source = "elsewhere", tool = "greet"),
    list(instanceId = "c2", source = "greeter", tool = "nope"),
    list(instanceId = "c3", source = "greeter"),
    list(source = "greeter", tool = "greet")
  )) {
    handle_host_event(session, registry, host_attach_event(descriptor))
  }
  helper_drain()

  replies <- helper_sent(session, "shinymcp-host-attached")
  expect_length(replies, 4)
  for (reply in replies) {
    expect_false(reply$ok)
    expect_equal(reply$error, "This app isn't available any more.")
  }
  expect_length(ls(registry$instances), 0)
})

test_that("a page that can't be read fails the attach", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  state$source$page_async <- function(...) {
    promises::promise_reject(simpleError("gone"))
  }
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    host_attach_event(host_descriptor(state))
  )
  helper_drain()

  reply <- helper_sent(session, "shinymcp-host-attached")[[1]]
  expect_false(reply$ok)
  expect_equal(reply$error, "Couldn't load the app: gone")
  # A failed read isn't kept.
  expect_length(ls(registry$pages), 0)
})

# ---- Requests from the page ----

test_that("requests are answered over a custom message, as the session's user", {
  skip_if_not_installed("later")
  session <- helper_fake_session(user = "ada")
  state <- new_mcp_host_state(host_app(), instance_id = "i1", tool = "greet")
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

  helper_drain()
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

test_that("tool calls from the page run in process with the session's user and groups", {
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
  registry <- helper_host_registry(
    i1 = new_mcp_host_state(app, "i1", tool = "who")
  )

  handle_host_event(
    session,
    registry,
    helper_host_request("i1", "tools/call", list(name = "who"))
  )
  helper_drain()

  expect_equal(seen$transport, "in-process")
  expect_equal(seen$user, "ada")
  expect_equal(seen$groups, c("staff", "admins"))
})

test_that("the page can call only the tools it may", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    helper_host_request(
      "i1",
      "tools/call",
      list(name = "approve"),
      id = 1,
      request_id = "r1"
    )
  )
  # Visible to the model only.
  handle_host_event(
    session,
    registry,
    helper_host_request(
      "i1",
      "tools/call",
      list(name = "peek"),
      id = 2,
      request_id = "r2"
    )
  )
  handle_host_event(
    session,
    registry,
    helper_host_request(
      "i1",
      "tools/call",
      list(name = "nope"),
      id = 3,
      request_id = "r3"
    )
  )
  # Fields are matched exactly: `nameX` isn't `name`.
  handle_host_event(
    session,
    registry,
    helper_host_request(
      "i1",
      "tools/call",
      list(nameX = "approve"),
      id = 4,
      request_id = "r4"
    )
  )
  helper_drain()

  responses <- lapply(
    helper_sent(session, "shinymcp-host-response"),
    `[[`,
    "response"
  )
  by_id <- stats::setNames(responses, vapply(responses, function(r) r$id, 0))
  expect_equal(by_id[["1"]]$result$content[[1]]$text, "approved")
  expect_equal(by_id[["2"]]$error$code, RPC_INVALID_PARAMS)
  expect_equal(
    by_id[["2"]]$error$message,
    "The app can't call the tool \"peek\"."
  )
  expect_equal(by_id[["3"]]$error$code, RPC_INVALID_PARAMS)
  expect_equal(by_id[["4"]]$error$code, RPC_INVALID_PARAMS)
  expect_equal(state$last_tool_call$name, "approve")
})

test_that("the host passes on only the requests a page may make", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  registry <- helper_host_registry(
    i1 = new_mcp_host_state(host_app(), "i1", tool = "greet")
  )

  for (method in c("initialize", "tools/list", "sampling/createMessage")) {
    handle_host_event(session, registry, helper_host_request("i1", method))
  }
  handle_host_event(
    session,
    registry,
    list(instanceId = "i1", requestId = "r9", message = list(id = 10))
  )

  responses <- lapply(
    helper_sent(session, "shinymcp-host-response"),
    `[[`,
    "response"
  )
  expect_length(responses, 4)
  for (response in responses) {
    expect_equal(response$error$code, RPC_METHOD_NOT_FOUND)
  }
  expect_equal(
    responses[[1]]$error$message,
    "The host doesn't pass on initialize."
  )
})

test_that("the page can read the app's resources", {
  skip_if_not_installed("later")
  app <- host_app()
  session <- helper_fake_session()
  registry <- helper_host_registry(
    i1 = new_mcp_host_state(app, "i1", tool = "greet")
  )

  handle_host_event(
    session,
    registry,
    helper_host_request("i1", "resources/read", list(uri = "ui://greeter"))
  )
  helper_drain()

  contents <- session$sent[[1]]$message$response$result$contents[[1]]
  expect_equal(contents$uri, "ui://greeter")
  expect_equal(contents$text, app$html_resource())
})

test_that("requests for an app that's gone get an error at once", {
  session <- helper_fake_session()
  registry <- new_host_registry()

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

test_that("tool errors are answered as error results and recorded", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  registry <- helper_host_registry(i1 = state)

  handle_host_event(
    session,
    registry,
    helper_host_request("i1", "tools/call", list(name = "boom"))
  )
  helper_drain()

  result <- session$sent[[1]]$message$response$result
  expect_true(result$isError)
  expect_equal(result$content[[1]]$text, "Error: kaboom")
  expect_true(state$last_tool_call$result$isError)
})

test_that("notifications update the host state; card messages reach the chat host", {
  session <- helper_fake_session()
  pane <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  card <- new_mcp_host_state(host_app(), "i2", tool = "greet", kind = "card")
  registry <- helper_host_registry(i1 = pane, i2 = card)
  posted <- list()
  registry$chat_hosts <- list(
    chat = list(
      on_message = function(state, params) {
        posted[[length(posted) + 1]] <<- list(
          id = state$instance_id,
          params = params
        )
      }
    )
  )
  notify <- function(id, method, params) {
    handle_host_event(
      session,
      registry,
      list(
        instanceId = id,
        type = "notification",
        method = method,
        params = params
      )
    )
  }
  message <- list(
    role = "user",
    content = list(list(type = "text", text = "hi"))
  )

  notify(
    "i1",
    "ui/update-model-context",
    list(content = list(list(type = "text", text = "ctx")))
  )
  notify("i1", "ui/message", message)
  notify("i2", "ui/message", message)
  notify("i1", "ui/notifications/size-changed", list(width = 320, height = 240))

  expect_equal(pane$model_context$content[[1]]$text, "ctx")
  expect_true(is.numeric(pane$context_time))
  expect_length(pane$messages, 1)
  expect_equal(pane$last_size, list(width = 320, height = 240))
  # Only cards post to the chat.
  expect_equal(posted, list(list(id = "i2", params = message)))
  expect_length(session$sent, 0)

  # Notifications for unknown instances are ignored.
  expect_no_error(notify("gone", "ui/message", list()))
})

test_that("dispose events shut the instance down and forget it", {
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
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

# ---- The host's check of the page's calls (on_app_call) ----

# An instance whose page's calls go through `on_app_call`, with a count of
# the requests its source was sent.
checked_instance <- function(on_app_call, kind = "pane", app = host_app()) {
  state <- new_mcp_host_state(app, "i1", tool = "greet", kind = kind)
  state$on_app_call <- on_app_call
  sent <- new.env(parent = emptyenv())
  sent$n <- 0
  send <- state$source$send_async
  state$source$send_async <- function(message, context = list()) {
    sent$n <- sent$n + 1
    send(message, context)
  }
  list(state = state, registry = helper_host_registry(i1 = state), sent = sent)
}

test_that("on_app_call sees each tool call the page makes before it's sent", {
  skip_if_not_installed("later")
  seen <- list()
  pane <- checked_instance(function(call) {
    seen[[length(seen) + 1]] <<- list(call = call, sent = pane$sent$n)
    TRUE
  })
  session <- helper_fake_session(user = "ada")

  response <- helper_page_call(
    session,
    pane$registry,
    "i1",
    "greet",
    list(name = "Bo")
  )
  expect_length(seen, 1)
  expect_equal(seen[[1]]$sent, 0)
  expect_equal(pane$sent$n, 1)
  expect_equal(
    response$result$structuredContent,
    list(message = "Hello Bo (for ada)")
  )
  expect_equal(pane$state$last_tool_call$arguments, list(name = "Bo"))

  # Only tool calls: reading the app's resources isn't checked.
  handle_host_event(
    session,
    pane$registry,
    helper_host_request("i1", "resources/read", list(uri = "ui://greeter"))
  )
  helper_drain()
  expect_length(seen, 1)
  expect_equal(pane$sent$n, 2)
})

test_that("on_app_call is told the tool, its arguments, and where the call comes from", {
  skip_if_not_installed("later")
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(
      name = "save",
      description = "Save the note.",
      fun = function(note = "") "saved",
      annotations = list(destructive_hint = TRUE)
    )),
    name = "notes",
    title = "Notes"
  )
  seen <- list()
  pane <- checked_instance(
    function(call) {
      seen[[length(seen) + 1]] <<- call
      TRUE
    },
    app = app
  )
  session <- helper_fake_session(user = "ada")

  helper_page_call(session, pane$registry, "i1", "save", list(note = "Hi"))
  helper_page_call(session, pane$registry, "i1", "save")
  call <- seen[[1]]
  expect_named(
    call,
    c(
      "name",
      "arguments",
      "tool",
      "instance_id",
      "kind",
      "source",
      "chat",
      "title",
      "session"
    )
  )
  expect_equal(call$name, "save")
  expect_equal(call$arguments, list(note = "Hi"))
  expect_equal(call$tool$name, "save")
  expect_equal(call$tool$description, "Save the note.")
  expect_true(call$tool$annotations$destructiveHint)
  expect_equal(call$instance_id, "i1")
  expect_equal(call$kind, "pane")
  expect_equal(call$source, "notes")
  expect_null(call$chat)
  expect_equal(call$title, "Notes")
  expect_identical(call$session, session)
  # A call without arguments has none.
  expect_equal(seen[[2]]$arguments, list())
})

test_that("on_app_call refuses a call with FALSE or a reason", {
  skip_if_not_installed("later")
  pane <- checked_instance(function(call) {
    switch(
      call$arguments$name,
      Ann = FALSE,
      Bo = "Bo needs a manager's approval.",
      TRUE
    )
  })
  session <- helper_fake_session()

  refused <- helper_page_call(
    session,
    pane$registry,
    "i1",
    "greet",
    list(name = "Ann")
  )
  expect_equal(refused$id, 1)
  expect_equal(refused$error$code, RPC_INVALID_PARAMS)
  expect_equal(
    refused$error$message,
    "The host refused the call to \"greet\"."
  )
  expect_null(refused$result)

  reason <- helper_page_call(
    session,
    pane$registry,
    "i1",
    "greet",
    list(name = "Bo"),
    id = 2
  )
  expect_equal(reason$id, 2)
  expect_equal(reason$error$code, RPC_INVALID_PARAMS)
  expect_equal(reason$error$message, "Bo needs a manager's approval.")

  # Neither reached the source or was recorded as the pane's call.
  expect_equal(pane$sent$n, 0)
  expect_null(pane$state$last_tool_call)

  allowed <- helper_page_call(
    session,
    pane$registry,
    "i1",
    "greet",
    list(name = "Cy")
  )
  expect_equal(
    allowed$result$structuredContent$message,
    "Hello Cy (for nobody)"
  )
  expect_equal(pane$sent$n, 1)
})

test_that("on_app_call can answer with a promise", {
  skip_if_not_installed("later")
  pending <- list()
  pane <- checked_instance(function(call) {
    promises::promise(function(resolve, reject) {
      pending[[call$arguments$name]] <<- resolve
    })
  })
  session <- helper_fake_session()
  ask <- function(name) {
    handle_host_event(
      session,
      pane$registry,
      helper_host_request(
        "i1",
        "tools/call",
        list(name = "greet", arguments = list(name = name))
      )
    )
    helper_drain()
  }
  answer <- function(name, value) {
    pending[[name]](value)
    helper_drain()
    responses <- helper_sent(session, "shinymcp-host-response")
    responses[[length(responses)]]$response
  }

  ask("Ann")
  # Nothing is sent, or answered, while the host decides.
  expect_length(session$sent, 0)
  expect_equal(pane$sent$n, 0)
  expect_equal(
    answer("Ann", FALSE)$error$message,
    "The host refused the call to \"greet\"."
  )

  ask("Bo")
  expect_equal(answer("Bo", "Not now.")$error$message, "Not now.")
  expect_equal(pane$sent$n, 0)

  ask("Cy")
  expect_equal(
    answer("Cy", TRUE)$result$structuredContent$message,
    "Hello Cy (for nobody)"
  )
  expect_equal(pane$sent$n, 1)
})

test_that("an on_app_call that fails or doesn't answer refuses the call", {
  skip_if_not_installed("later")
  answers <- list(
    error = function() stop("no policy"),
    rejected = function() promises::promise_reject(simpleError("no answer")),
    null = function() NULL,
    vector = function() c(TRUE, TRUE),
    na = function() NA,
    promised_null = function() promises::promise_resolve(NULL)
  )
  pane <- checked_instance(function(call) answers[[call$arguments$name]]())
  session <- helper_fake_session()

  for (name in names(answers)) {
    expect_warning(
      response <- helper_page_call(
        session,
        pane$registry,
        "i1",
        "greet",
        list(name = name)
      ),
      "call to \"greet\" was refused",
      fixed = TRUE
    )
    expect_equal(response$error$code, RPC_INVALID_PARAMS)
    expect_equal(
      response$error$message,
      "The host refused the call to \"greet\"."
    )
  }
  expect_equal(pane$sent$n, 0)
  expect_null(pane$state$last_tool_call)

  # The app's author is told what went wrong; the page isn't.
  expect_warning(
    helper_page_call(
      session,
      pane$registry,
      "i1",
      "greet",
      list(name = "error")
    ),
    "no policy"
  )
  expect_warning(
    helper_page_call(
      session,
      pane$registry,
      "i1",
      "greet",
      list(name = "rejected")
    ),
    "no answer"
  )
  expect_warning(
    helper_page_call(
      session,
      pane$registry,
      "i1",
      "greet",
      list(name = "null")
    ),
    "or a string, not NULL"
  )
})

test_that("without on_app_call, the page's calls go to the source as before", {
  skip_if_not_installed("later")
  pane <- checked_instance(NULL)
  expect_length(host_app_call_hooks(pane$registry, pane$state), 0)
  expect_length(ls(pane$registry$app_call_hooks), 0)
  session <- helper_fake_session()

  expect_no_warning(
    response <- helper_page_call(
      session,
      pane$registry,
      "i1",
      "greet",
      list(name = "Bo")
    )
  )
  expect_equal(
    response$result$structuredContent$message,
    "Hello Bo (for nobody)"
  )
  expect_equal(pane$sent$n, 1)
  expect_equal(pane$state$last_tool_call$arguments, list(name = "Bo"))
})

test_that("a tool the page may not call is refused before on_app_call sees it", {
  skip_if_not_installed("later")
  seen <- character()
  pane <- checked_instance(function(call) {
    seen <<- c(seen, call$name)
    TRUE
  })
  session <- helper_fake_session()

  peek <- helper_page_call(session, pane$registry, "i1", "peek")
  expect_equal(peek$error$message, "The app can't call the tool \"peek\".")
  helper_page_call(session, pane$registry, "i1", "nope")
  expect_length(seen, 0)
  expect_equal(pane$sent$n, 0)
})

test_that("on_app_call can read reactive values", {
  skip_if_not_installed("later")
  skip_if_not_installed("shiny")
  allowed <- shiny::reactiveVal("greet")
  pane <- checked_instance(function(call) call$name %in% allowed())
  session <- helper_fake_session()

  expect_no_warning(helper_page_call(session, pane$registry, "i1", "greet"))
  expect_equal(pane$sent$n, 1)
  allowed("approve")
  refused <- helper_page_call(session, pane$registry, "i1", "greet")
  expect_equal(
    refused$error$message,
    "The host refused the call to \"greet\"."
  )
})

test_that("a restored card's calls go through every check the session has for its source", {
  skip_if_not_installed("later")
  checked <- character()
  pane_check <- function(call) {
    checked <<- c(checked, "pane")
    TRUE
  }
  chat_check <- function(call) {
    checked <<- c(checked, "chat")
    if (call$arguments$name == "Bo") "Not Bo." else TRUE
  }
  session <- helper_fake_session()
  registry <- new_host_registry()
  # A pane and a chat host show the same app; each registers its check,
  # once.
  app <- host_app()
  register_host_source(registry, app, pane_check)
  register_host_source(registry, app, chat_check)
  register_host_source(registry, app, chat_check)
  expect_length(registry$app_call_hooks$greeter, 2)

  # The card says it's a chat's that isn't here: the descriptor comes from
  # the browser, so it can't choose the card's checks.
  handle_host_event(
    session,
    registry,
    host_attach_event(list(
      instanceId = "c1",
      source = "greeter",
      tool = "greet",
      owner = "elsewhere"
    ))
  )
  helper_drain()
  expect_true(helper_sent(session, "shinymcp-host-attached")[[1]]$ok)

  refused <- helper_page_call(
    session,
    registry,
    "c1",
    "greet",
    list(name = "Bo")
  )
  expect_equal(refused$error$message, "Not Bo.")
  expect_equal(checked, c("pane", "chat"))
  expect_null(host_instance(registry, "c1")$last_tool_call)

  allowed <- helper_page_call(
    session,
    registry,
    "c1",
    "greet",
    list(name = "Cy")
  )
  expect_equal(
    allowed$result$structuredContent$message,
    "Hello Cy (for nobody)"
  )
})

test_that("a restored card that had its own check refuses calls until one is given", {
  skip_if_not_installed("later")
  app <- host_app()
  first <- new_host_registry()
  register_host_source(first, app)
  state <- new_mcp_host_state(
    first$sources$greeter,
    instance_id = "c1",
    tool = "greet",
    kind = "card"
  )
  state$on_app_call <- function(call) TRUE
  descriptor <- host_descriptor(state)
  expect_true(descriptor$checked)
  expect_null(
    host_descriptor(new_mcp_host_state(
      app,
      instance_id = "c2",
      tool = "greet"
    ))$checked
  )

  session <- helper_fake_session()
  registry <- new_host_registry()
  register_host_source(registry, app)
  handle_host_event(session, registry, host_attach_event(descriptor))
  helper_drain()
  refused <- helper_page_call(
    session,
    registry,
    "c1",
    "greet",
    list(name = "Bo")
  )
  expect_match(refused$error$message, "no check for them")
  expect_null(host_instance(registry, "c1")$last_tool_call)

  # Once the session gives a check for the source, it decides.
  register_host_source(registry, app, function(call) TRUE)
  allowed <- helper_page_call(
    session,
    registry,
    "c1",
    "greet",
    list(name = "Cy")
  )
  expect_equal(
    allowed$result$structuredContent$message,
    "Hello Cy (for nobody)"
  )
})

test_that("on_app_call must be a function", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  expect_error(
    mcp_host_server("h", host_app(), on_app_call = "allow"),
    "must be a function",
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_embed(host_app(), id = "h", on_app_call = TRUE),
    "must be a function",
    class = "shinymcp_error_validation"
  )
})

# ---- Host state ----

test_that("new host state starts empty", {
  app <- host_app()
  state <- new_mcp_host_state(app, instance_id = "i1", tool = "greet")

  expect_s3_class(state$source, "shinymcp_host_source")
  expect_equal(state$source$key, "greeter")
  expect_equal(state$instance_id, "i1")
  expect_equal(state$kind, "pane")
  expect_equal(state$tool, "greet")
  expect_equal(as.character(to_json(state$arguments)), "{}")
  expect_null(state$result)
  expect_null(state$model_context)
  expect_null(state$last_tool_call)
  expect_null(state$last_size)
  expect_equal(state$messages, list())
  expect_false(state$attached)
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
  state <- new_mcp_host_state(app, "i1", tool = "live")
  state$arguments <- list(name = "Ada")
  registry <- helper_host_registry(i1 = state)

  start_host_call(session, state)
  helper_drain()

  expect_match(state$result$content[[1]]$text, "Hi Ada", fixed = TRUE)
  expect_length(state$views, 1)
  expect_equal(app$runtime()$instance_count(), 1)

  handle_host_event(
    session,
    registry,
    list(instanceId = "i1", type = "dispose")
  )
  expect_equal(app$runtime()$instance_count(), 0)
})

test_that("the text of what an app sends is its text blocks and structured content", {
  params <- list(
    content = list(
      list(type = "text", text = "one"),
      list(type = "image", data = "x"),
      list(type = "text", text = "two")
    ),
    structuredContent = list(n = 3)
  )
  expect_equal(host_content_text(params), "one\ntwo\n{\"n\":3}")
  expect_equal(host_content_text(params, limit = 6), "one...")
  expect_equal(host_content_text(list()), "")
  # Empty structured content adds nothing.
  params$structuredContent <- setNames(list(), character())
  expect_equal(host_content_text(params), "one\ntwo")
})

# ---- mcp_host_server() ----

test_that("mcp_host_server() opens the app and sends the page its descriptor", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
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
          "open",
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
      expect_equal(config$source, "greeter")
      expect_equal(config$tool, "greet")
      expect_equal(config$title, "Greeter")
      expect_equal(config$height, "250px")
      expect_equal(config$arguments, list(name = "Ada"))

      # The tool is called as soon as the pane is set up.
      helper_drain()
      session$flushReact()
      expect_equal(session$returned$last_tool_call()$name, "greet")
      expect_equal(
        session$returned$last_result()$structuredContent,
        list(message = "Hello Ada (for nobody)")
      )

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
      helper_drain()
      expect_null(host$model_context())
      expect_equal(host$messages(), list())

      root$setInputs(
        shinymcp_host_event = helper_host_request(
          id,
          "tools/call",
          list(name = "greet", arguments = list(name = "Grace"))
        )
      )
      helper_drain()
      session$flushReact()

      responses <- capture$messages("shinymcp-host-response")
      expect_length(responses, 1)
      expect_equal(responses[[1]]$instanceId, id)
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

test_that("mcp_host_server() opens the app again with other arguments", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  capture <- helper_capture_session()

  shiny::testServer(
    function(id) {
      mcp_host_server(id, host_app(), arguments = list(name = "Ada"))
    },
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      id <- host$instance_id()
      helper_drain()

      host$open(list(name = "Bo"))
      commands <- capture$messages("shinymcp-host-command")
      expect_equal(commands[[1]], list(instanceId = id, command = "reopen"))
      helper_drain()
      session$flushReact()
      expect_equal(
        host$last_result()$structuredContent,
        list(message = "Hello Bo (for nobody)")
      )

      expect_error(
        host$open(tool = "nope"),
        class = "shinymcp_error_validation"
      )
    }
  )
})

test_that("a pane opened again doesn't take the old page's calls as its own", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  capture <- helper_capture_session()

  shiny::testServer(
    function(id) {
      mcp_host_server(id, host_app(), arguments = list(name = "Ada"))
    },
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      root <- session$rootScope()
      id <- host$instance_id()
      state <- root$userData$.shinymcp_hosts$instances[[id]]
      root$setInputs(
        shinymcp_host_event = host_attach_event(host_descriptor(state))
      )
      helper_drain()

      # The page's requests are answered when released, as by a slow server,
      # and each opens a live view.
      held <- list()
      send <- state$source$send_async
      state$source$send_async <- function(message, context = list()) {
        view <- paste0("view-", message$params$arguments$name)
        promises::promise(function(resolve, reject) {
          held[[length(held) + 1]] <<- function() {
            resolve(promises::then(send(message, context), function(response) {
              response$result[["_meta"]] <- list(
                "shinymcp/view" = list(instance = view)
              )
              response
            }))
          }
        })
      }
      ask <- function(name, request_id) {
        root$setInputs(
          shinymcp_host_event = helper_host_request(
            id,
            "tools/call",
            list(name = "greet", arguments = list(name = name)),
            request_id = request_id
          )
        )
        helper_drain()
      }
      release <- function() {
        for (answer in held) {
          answer()
        }
        held <<- list()
        helper_drain()
        session$flushReact()
      }

      # The old page's call is still running when the pane opens again, and
      # the old page calls again as it goes (a live view closing itself).
      ask("Old", "q1")
      host$open(list(name = "Bo"))
      helper_drain()
      ask("Leaving", "q2")
      release()

      expect_equal(host$last_tool_call()$arguments, list(name = "Bo"))
      # The old page still gets its answers, and its views close with the
      # pane.
      responses <- capture$messages("shinymcp-host-response")
      expect_equal(
        vapply(responses, function(r) r$requestId, ""),
        c("q1", "q2")
      )
      expect_setequal(state$views, c("view-Old", "view-Leaving"))

      # The new page's calls are the pane's.
      root$setInputs(
        shinymcp_host_event = host_attach_event(host_descriptor(state), "a2")
      )
      helper_drain()
      ask("New", "q3")
      release()
      expect_equal(host$last_tool_call()$arguments, list(name = "New"))
    }
  )
})

test_that("the old page's notifications after open() aren't the pane's", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  capture <- helper_capture_session()

  shiny::testServer(
    function(id) mcp_host_server(id, host_app()),
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      root <- session$rootScope()
      id <- host$instance_id()
      state <- root$userData$.shinymcp_hosts$instances[[id]]
      notify <- function(method, params) {
        root$setInputs(
          shinymcp_host_event = list(
            instanceId = id,
            type = "notification",
            method = method,
            params = params
          )
        )
      }
      root$setInputs(
        shinymcp_host_event = host_attach_event(host_descriptor(state), "a1")
      )
      helper_drain()
      notify("ui/update-model-context", list(structuredContent = list(n = 1)))
      expect_equal(host$model_context()$structuredContent, list(n = 1))

      # The old page is still there until the page script loads the new one.
      host$open(list(name = "Bo"))
      notify("ui/update-model-context", list(structuredContent = list(n = 2)))
      notify(
        "ui/message",
        list(role = "user", content = list(list(type = "text", text = "old")))
      )
      expect_equal(host$model_context()$structuredContent, list(n = 1))
      expect_equal(host$messages(), list())

      root$setInputs(
        shinymcp_host_event = host_attach_event(host_descriptor(state), "a2")
      )
      helper_drain()
      notify("ui/update-model-context", list(structuredContent = list(n = 3)))
      expect_equal(host$model_context()$structuredContent, list(n = 3))
    }
  )
})

test_that("an attach that finishes after a newer one leaves the pane to the newer page", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  apps <- list(
    mcp_app(
      mcp_text("a"),
      tools = list(list(name = "show_a", fun = function() list(a = "A"))),
      name = "first"
    ),
    mcp_app(
      mcp_text("b"),
      tools = list(list(
        name = "show_b",
        fun = function(label = "b") list(b = label)
      )),
      name = "second"
    )
  )
  capture <- helper_capture_session()
  shiny::testServer(
    function(id) mcp_host_server(id, apps, tool = "show_a"),
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      root <- session$rootScope()
      id <- host$instance_id()
      state <- root$userData$.shinymcp_hosts$instances[[id]]
      helper_drain()
      # The first app's page is slow to read.
      release <- NULL
      page_async <- state$source$page_async
      state$source$page_async <- function(uri, config) {
        page <- page_async(uri, config)
        if (!identical(uri, "ui://first")) {
          return(page)
        }
        promises::promise(function(resolve, reject) {
          release <<- function() resolve(page)
        })
      }

      root$setInputs(
        shinymcp_host_event = host_attach_event(host_descriptor(state), "a1")
      )
      helper_drain()
      host$open(tool = "show_b")
      root$setInputs(
        shinymcp_host_event = host_attach_event(host_descriptor(state), "a2")
      )
      helper_drain()
      expect_equal(state$title, "second")
      release()
      helper_drain()

      attached <- capture$messages("shinymcp-host-attached")
      by_request <- stats::setNames(
        attached,
        vapply(attached, function(m) m$requestId, "")
      )
      expect_true(by_request$a2$ok)
      expect_false(by_request$a1$ok)
      expect_equal(state$title, "second")

      # The page shown is the second app's, and its calls are the pane's.
      root$setInputs(
        shinymcp_host_event = helper_host_request(
          id,
          "tools/call",
          list(name = "show_b", arguments = list(label = "page")),
          request_id = "q1"
        )
      )
      helper_drain()
      session$flushReact()
      expect_equal(host$last_tool_call()$arguments, list(label = "page"))
    }
  )
})

test_that("opening another app's tool in a pane takes that app's trigger", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  apps <- list(
    mcp_app(
      mcp_text("a"),
      tools = list(list(name = "show_a", fun = function() list(a = "A"))),
      name = "first",
      trigger = "submit"
    ),
    mcp_app(
      mcp_text("b"),
      tools = list(list(name = "show_b", fun = function() list(b = "B"))),
      name = "second",
      debounce_ms = 800
    )
  )
  for (pane_trigger in list(NULL, "manual")) {
    capture <- helper_capture_session()
    shiny::testServer(
      function(id) {
        mcp_host_server(id, apps, tool = "show_a", trigger = pane_trigger)
      },
      args = list(id = "h"),
      session = capture$session,
      {
        host <- session$returned
        id <- host$instance_id()
        state <- capture$session$userData$.shinymcp_hosts$instances[[id]]
        expect_equal(state$config$trigger, pane_trigger %||% "submit")
        helper_drain()

        host$open(tool = "show_b")
        expected <- pane_trigger %||% "debounce"
        expect_equal(state$config$trigger, expected)
        expect_equal(state$config$debounceMs, 800)
        commands <- capture$messages("shinymcp-host-command")
        expect_equal(
          commands[[1]],
          list(instanceId = id, command = "reopen", trigger = expected)
        )
      }
    )
  }
})

test_that("a pane's title follows the tool it opens", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  apps <- list(
    mcp_app(
      mcp_text("a"),
      tools = list(list(
        name = "show_a",
        title = "Show A",
        fun = function() list(a = "A")
      )),
      name = "first"
    ),
    mcp_app(
      mcp_text("b"),
      tools = list(list(
        name = "show_b",
        title = "Show B",
        fun = function() list(b = "B")
      )),
      name = "second"
    )
  )
  capture <- helper_capture_session()
  shiny::testServer(
    function(id) mcp_host_server(id, apps, tool = "show_a"),
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      state <- capture$session$userData$.shinymcp_hosts$instances[[
        host$instance_id()
      ]]
      expect_equal(state$title, "Show A")
      helper_drain()
      host$open(tool = "show_b")
      expect_equal(state$title, "Show B")
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
        list(instanceId = id, command = "execute", inputs = list(name = "Zed"))
      )
      expect_equal(commands[[2]], list(instanceId = id, command = "execute"))
      expect_equal(commands[[3]], list(instanceId = id, command = "reset"))
      expect_equal(commands[[4]], list(instanceId = id, command = "dispose"))
      state <- session$rootScope()$userData$.shinymcp_hosts$instances[[id]]
      expect_true(state$disposed)
    }
  )
})

test_that("mcp_host_server() refuses a tool the app doesn't have", {
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

test_that("mcp_host_server() checks the page's calls with on_app_call", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  capture <- helper_capture_session()
  seen <- list()

  shiny::testServer(
    function(id) {
      mcp_host_server(
        id,
        host_app(),
        arguments = list(name = "Ada"),
        on_app_call = function(call) {
          seen[[length(seen) + 1]] <<- call
          if (call$name == "approve") "Ask a manager to approve it." else TRUE
        }
      )
    },
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      root <- session$rootScope()
      id <- host$instance_id()
      helper_drain()
      session$flushReact()
      # The call that opens the pane is the Shiny app's, not the page's.
      expect_length(seen, 0)
      expect_equal(host$last_tool_call()$arguments, list(name = "Ada"))

      request <- function(name, request_id) {
        root$setInputs(
          shinymcp_host_event = helper_host_request(
            id,
            "tools/call",
            list(name = name),
            request_id = request_id
          )
        )
        helper_drain()
        session$flushReact()
      }
      request("approve", "q1")
      request("greet", "q2")

      responses <- capture$messages("shinymcp-host-response")
      by_request <- stats::setNames(
        lapply(responses, `[[`, "response"),
        vapply(responses, function(r) r$requestId, "")
      )
      expect_equal(
        by_request$q1$error$message,
        "Ask a manager to approve it."
      )
      expect_equal(
        by_request$q2$result$structuredContent$message,
        "Hello world (for nobody)"
      )
      expect_equal(host$last_tool_call()$name, "greet")
      expect_equal(
        vapply(seen, function(call) call$name, ""),
        c("approve", "greet")
      )
      expect_equal(seen[[1]]$instance_id, id)
      expect_equal(seen[[1]]$kind, "pane")
      expect_null(seen[[1]]$chat)
      expect_identical(seen[[1]]$session, root)
    }
  )
})

# ---- mcp_embed() ----

test_that("mcp_embed() needs a session or an id", {
  skip_if_not_installed("shiny")
  app <- host_app()

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

test_that("mcp_embed() in a session registers the app and calls its tool", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
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
  registry <- session$userData$.shinymcp_hosts
  instances <- ls(registry$instances)

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
  expect_equal(config$tool, "greet")
  expect_equal(config$arguments, list(name = "Ada"))

  helper_drain()
  expect_equal(
    registry$instances[[instances]]$result$structuredContent,
    list(message = "Hello Ada (for nobody)")
  )

  second <- as.character(mcp_embed(app, id = "1st"))
  expect_match(second, '<div id="shinymcp-1st"', fixed = TRUE)
  expect_length(ls(registry$instances), 2)
})

test_that("mcp_embed() checks the page's calls with on_app_call", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  session <- shiny::MockShinySession$new()
  local_mocked_bindings(active_shiny_session = function() session)

  ui <- mcp_embed(host_app(), on_app_call = function(call) {
    call$name != "approve"
  })
  id <- helper_markup_config(as.character(ui))$instanceId
  registry <- session$userData$.shinymcp_hosts
  helper_drain()
  fake <- helper_fake_session()

  refused <- helper_page_call(fake, registry, id, "approve")
  expect_equal(
    refused$error$message,
    "The host refused the call to \"approve\"."
  )
  allowed <- helper_page_call(fake, registry, id, "greet")
  expect_equal(
    allowed$result$structuredContent$message,
    "Hello world (for nobody)"
  )
})

# ---- Apps from a remote server ----

test_that("a remote server's app attaches with its page and tools", {
  skip_if_not_installed("later")
  app <- serving_app(
    name = "fx",
    csp = list(connect_domains = "https://api.example.com"),
    prefers_border = FALSE
  )
  fx <- serving_client(McpServer$new(app), name = "remote")
  session <- helper_fake_session()
  state <- new_mcp_host_state(fx$client, "r1", tool = "echo")
  state$arguments <- list(x = "hi")
  registry <- helper_host_registry(r1 = state)

  start_host_call(session, state)
  handle_host_event(
    session,
    registry,
    host_attach_event(host_descriptor(state))
  )
  helper_drain()

  expect_equal(state$result$structuredContent, list(out = "hi"))
  reply <- helper_sent(session, "shinymcp-host-attached")[[1]]
  expect_true(reply$ok)
  expect_equal(reply$page$html, app$html_resource())
  expect_equal(
    unlist(reply$page$csp$connectDomains),
    "https://api.example.com"
  )
  expect_false(reply$page$prefersBorder)
  expect_equal(reply$tool$name, "echo")
  expect_equal(as.character(reply$appTools), c("echo", "boom", "refresh"))
  expect_equal(reply$toolResult, state$result)
})

test_that("a remote app's page calls go through the client, within its visibility", {
  skip_if_not_installed("later")
  app <- serving_app(
    name = "fx",
    tools = list(
      serving_echo_tool(),
      list(name = "refresh", visibility = "app", fun = function() {
        list(out = "refreshed")
      }),
      list(name = "secret", visibility = "model", fun = function() {
        list(out = "secret")
      })
    )
  )
  fx <- serving_client(McpServer$new(app), name = "remote")
  session <- helper_fake_session()
  registry <- helper_host_registry(
    r1 = new_mcp_host_state(fx$client, "r1", tool = "echo")
  )

  handle_host_event(
    session,
    registry,
    helper_host_request(
      "r1",
      "tools/call",
      list(name = "refresh"),
      id = "p-1",
      request_id = "q1"
    )
  )
  handle_host_event(
    session,
    registry,
    helper_host_request(
      "r1",
      "tools/call",
      list(name = "secret"),
      id = "p-2",
      request_id = "q2"
    )
  )
  handle_host_event(
    session,
    registry,
    helper_host_request(
      "r1",
      "resources/read",
      list(uri = "ui://fx"),
      id = "p-3",
      request_id = "q3"
    )
  )
  helper_drain()

  responses <- lapply(
    helper_sent(session, "shinymcp-host-response"),
    `[[`,
    "response"
  )
  by_id <- stats::setNames(responses, vapply(responses, function(r) r$id, ""))
  expect_equal(by_id[["p-1"]]$result$structuredContent, list(out = "refreshed"))
  expect_equal(by_id[["p-2"]]$error$code, RPC_INVALID_PARAMS)
  expect_equal(by_id[["p-3"]]$result$contents[[1]]$uri, "ui://fx")
  # The page's own ids come back; the server saw the client's.
  methods <- vapply(
    fx$requests(),
    function(r) jsonlite::parse_json(rawToChar(r$body))$method,
    ""
  )
  expect_false(
    "p-1" %in%
      vapply(
        fx$requests(),
        function(r) {
          as.character(jsonlite::parse_json(rawToChar(r$body))$id %||% "")
        },
        ""
      )
  )
  expect_equal(sum(methods == "tools/call"), 1)
})

test_that("a remote server that fails answers the page with an error", {
  skip_if_not_installed("later")
  client <- McpClient$new(
    "http://127.0.0.1:1/mcp",
    name = "down",
    transport = function(request, async = FALSE, timeout = 60) {
      promises::promise_reject(simpleError("Connection refused"))
    }
  )
  source <- as_host_source(client)
  source$tools_async <- function(refresh = FALSE) {
    promises::promise_resolve(list(list(
      name = "open",
      `_meta` = list(ui = list(resourceUri = "ui://down"))
    )))
  }
  session <- helper_fake_session()
  registry <- helper_host_registry(
    d1 = new_mcp_host_state(source, "d1", tool = "open")
  )

  handle_host_event(
    session,
    registry,
    helper_host_request("d1", "tools/call", list(name = "open"), id = 4)
  )
  handle_host_event(
    session,
    registry,
    host_attach_event(list(instanceId = "d1", source = "down", tool = "open"))
  )
  helper_drain()

  response <- helper_sent(session, "shinymcp-host-response")[[1]]$response
  expect_equal(response$id, 4)
  expect_equal(response$error$code, RPC_INTERNAL_ERROR)
  expect_match(response$error$message, "Couldn't reach")
  attached <- helper_sent(session, "shinymcp-host-attached")[[1]]
  expect_false(attached$ok)
  expect_match(attached$error, "^Couldn't load the app")
})

test_that("an instance without a title of its own takes its page's", {
  expect_equal(
    html_page_title("<html><head><title> A &amp; B </title></head></html>"),
    "A & B"
  )
  expect_null(html_page_title("<html><head></head></html>"))
  expect_null(html_page_title("<title></title>"))
  expect_null(html_page_title(NULL))

  skip_if_not_installed("later")
  fx <- serving_client(
    McpServer$new(serving_app(name = "fx", title = "Effects")),
    name = "remote"
  )
  session <- helper_fake_session()
  state <- new_mcp_host_state(fx$client, "r1", tool = "echo")
  expect_equal(state$title, "remote")
  registry <- helper_host_registry(r1 = state)

  handle_host_event(
    session,
    registry,
    host_attach_event(host_descriptor(state))
  )
  helper_drain()
  expect_equal(
    helper_sent(session, "shinymcp-host-attached")[[1]]$title,
    "Effects"
  )
  expect_equal(state$title, "Effects")

  named <- new_mcp_host_state(fx$client, "r2", tool = "echo", title = "Mine")
  expect_false(named$default_title)
})

# A client whose requests are counted by whether they block the session.
waiting_client <- function(server, name = "remote") {
  served <- serving_transport(server)
  counts <- new.env(parent = emptyenv())
  counts$blocking <- 0
  counts$down <- FALSE
  client <- McpClient$new(
    "http://127.0.0.1/mcp",
    name = name,
    transport = function(request, async = FALSE, timeout = 60) {
      if (!async) {
        counts$blocking <- counts$blocking + 1
      }
      if (counts$down) {
        return(promises::promise_reject(simpleError("Connection refused")))
      }
      served$transport(request, async = async, timeout = timeout)
    }
  )
  list(client = client, counts = counts, requests = served$requests)
}

request_methods <- function(requests) {
  vapply(
    requests,
    function(r) {
      if (is.null(r$body)) {
        return("")
      }
      jsonlite::parse_json(rawToChar(r$body))$method %||% ""
    },
    ""
  )
}

test_that("a remote app is registered without waiting on its server", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  remote <- waiting_client(McpServer$new(serving_app(name = "fx")))
  capture <- helper_capture_session()

  registered <- register_shiny_host_instance(
    capture$session,
    remote$client,
    instance_id = "r1",
    arguments = list(x = "hi")
  )
  state <- registered$state
  # Which tool opens the app is known once the server lists its tools.
  expect_null(registered$config$tool)
  expect_equal(registered$config$title, "remote")

  start_host_call(capture$session, state)
  helper_drain()
  expect_equal(state$tool, "echo")
  expect_equal(state$result$structuredContent, list(out = "hi"))
  expect_equal(remote$counts$blocking, 0)
  expect_equal(sum(request_methods(remote$requests()) == "tools/list"), 1)
})

test_that("a remote tool that isn't there shows where the app would be", {
  skip_if_not_installed("later")
  remote <- waiting_client(McpServer$new(serving_app(name = "fx")))
  session <- helper_fake_session()
  state <- new_mcp_host_state(remote$client, "r1", tool = "nope")
  registry <- helper_host_registry(r1 = state)

  start_host_call(session, state)
  handle_host_event(
    session,
    registry,
    host_attach_event(host_descriptor(state))
  )
  helper_drain()

  reply <- helper_sent(session, "shinymcp-host-attached")[[1]]
  expect_false(reply$ok)
  expect_match(reply$error, "has no tool called \"nope\"")
  expect_match(state$call_error, "has no tool called")
  expect_false("tools/call" %in% request_methods(remote$requests()))
})

test_that("a restored card from a remote server is checked when it attaches", {
  skip_if_not_installed("later")
  remote <- waiting_client(McpServer$new(serving_app(name = "fx")))
  session <- helper_fake_session()
  registry <- new_host_registry()
  register_host_source(registry, remote$client)
  saved <- list(content = list(list(type = "text", text = "saved")))

  handle_host_event(
    session,
    registry,
    host_attach_event(list(
      instanceId = "old",
      source = "remote",
      tool = "echo",
      result = saved
    ))
  )
  handle_host_event(
    session,
    registry,
    host_attach_event(
      list(instanceId = "gone", source = "remote", tool = "nope"),
      request_id = "a2"
    )
  )
  helper_drain()

  replies <- helper_sent(session, "shinymcp-host-attached")
  by_id <- stats::setNames(replies, vapply(replies, `[[`, "", "instanceId"))
  expect_true(by_id$old$ok)
  expect_equal(by_id$old$toolResult, saved)
  expect_false(by_id$gone$ok)
  expect_equal(by_id$gone$error, "This app isn't available any more.")
  expect_equal(ls(registry$instances), "old")
  expect_false("tools/call" %in% request_methods(remote$requests()))
  expect_equal(remote$counts$blocking, 0)
})

test_that("a server that couldn't be reached is tried again on the next attach", {
  skip_if_not_installed("later")
  remote <- waiting_client(McpServer$new(serving_app(name = "fx")))
  session <- helper_fake_session()
  state <- new_mcp_host_state(remote$client, "r1", tool = "echo")
  registry <- helper_host_registry(r1 = state)

  remote$counts$down <- TRUE
  handle_host_event(
    session,
    registry,
    host_attach_event(host_descriptor(state))
  )
  helper_drain()
  remote$counts$down <- FALSE
  handle_host_event(
    session,
    registry,
    host_attach_event(host_descriptor(state), request_id = "a2")
  )
  helper_drain()

  replies <- helper_sent(session, "shinymcp-host-attached")
  expect_false(replies[[1]]$ok)
  expect_match(replies[[1]]$error, "^Couldn't reach the app's server")
  expect_true(replies[[2]]$ok)
})

test_that("a remote pane opens another tool without waiting on its server", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  remote <- waiting_client(McpServer$new(serving_app(name = "fx")))
  capture <- helper_capture_session()

  shiny::testServer(
    function(id) {
      mcp_host_server(id, remote$client, arguments = list(x = "a"))
    },
    args = list(id = "h"),
    session = capture$session,
    {
      host <- session$returned
      helper_drain()
      state <- capture$session$userData$.shinymcp_hosts$instances[[
        host$instance_id()
      ]]
      expect_equal(state$result$structuredContent, list(out = "a"))

      # A tool that isn't there fails the call, not open().
      host$open(list(x = "b"), tool = "nope")
      helper_drain()
      expect_match(state$call_error, "has no tool called")
      expect_null(state$result)

      host$open(list(x = "c"), tool = "echo")
      helper_drain()
      expect_equal(state$result$structuredContent, list(out = "c"))
    }
  )
  expect_equal(remote$counts$blocking, 0)
})

test_that("answers that arrive after the app closed go nowhere", {
  skip_if_not_installed("later")
  session <- helper_fake_session()
  state <- new_mcp_host_state(host_app(), "i1", tool = "greet")
  registry <- helper_host_registry(i1 = state)
  calls <- 0
  state$on_tool_call <- function(value) calls <<- calls + 1

  handle_host_event(
    session,
    registry,
    helper_host_request("i1", "tools/call", list(name = "greet"))
  )
  mcp_host_dispose(state)
  helper_drain()

  expect_length(session$sent, 0)
  expect_equal(calls, 0)
})
