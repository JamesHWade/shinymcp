make_test_app <- function(...) {
  McpApp$new(
    ui = htmltools::tags$div("Test"),
    tools = list(
      list(
        name = "echo",
        description = "Echo the input",
        inputSchema = list(
          type = "object",
          properties = list(x = list(type = "string"))
        ),
        fun = function(x = "a") list(out = x)
      )
    ),
    name = "serve-test",
    ...
  )
}

make_test_registry <- function(app) {
  registry <- ResourceRegistry$new()
  registry$register(
    uri = app$resource_uri(),
    name = app$name,
    description = paste("MCP App:", app$name),
    mime_type = SHINYMCP_UI_MIME_TYPE,
    content_fn = function() app$html_resource(),
    meta = app$resource_meta()
  )
  for (res in app$extra_resources()) {
    registry$register(
      uri = res$uri,
      name = res$name,
      description = res$description,
      mime_type = res$mime_type,
      content_fn = res$content_fn,
      meta = res$meta
    )
  }
  registry
}

# ---- Protocol version negotiation ----

test_that("negotiate_protocol_version echoes supported client versions", {
  expect_equal(negotiate_protocol_version("2025-06-18"), "2025-06-18")
  expect_equal(negotiate_protocol_version("2024-11-05"), "2024-11-05")
  expect_equal(negotiate_protocol_version("2025-11-25"), "2025-11-25")
})

test_that("negotiate_protocol_version falls back to latest for unknown versions", {
  expect_equal(
    negotiate_protocol_version("1999-01-01"),
    SHINYMCP_PROTOCOL_VERSION
  )
  expect_equal(
    negotiate_protocol_version("2099-01-01"),
    SHINYMCP_PROTOCOL_VERSION
  )
  expect_equal(negotiate_protocol_version(NULL), SHINYMCP_PROTOCOL_VERSION)
  expect_equal(negotiate_protocol_version(list()), SHINYMCP_PROTOCOL_VERSION)
})

# ---- MCP Apps extension capability detection ----

test_that("client_supports_mcp_apps detects the ui extension capability", {
  with_ext <- list(
    capabilities = list(
      extensions = list(
        "io.modelcontextprotocol/ui" = list(
          mimeTypes = list("text/html;profile=mcp-app")
        )
      )
    )
  )
  expect_true(client_supports_mcp_apps(with_ext))

  no_ext <- list(capabilities = list(tools = list()))
  expect_false(client_supports_mcp_apps(no_ext))

  expect_false(client_supports_mcp_apps(list()))
})

test_that("client_supports_mcp_apps handles mime type mismatches", {
  wrong_mime <- list(
    capabilities = list(
      extensions = list(
        "io.modelcontextprotocol/ui" = list(mimeTypes = list("text/plain"))
      )
    )
  )
  expect_false(client_supports_mcp_apps(wrong_mime))

  # Missing mimeTypes is treated leniently as supporting the default
  no_mime <- list(
    capabilities = list(
      extensions = list("io.modelcontextprotocol/ui" = list())
    )
  )
  expect_true(client_supports_mcp_apps(no_mime))
})

# ---- initialize handling ----

test_that("initialize negotiates version and records UI capability", {
  app <- make_test_app()
  registry <- make_test_registry(app)
  session <- new_mcp_session()

  response <- dispatch_message(
    list(
      jsonrpc = "2.0",
      id = 1,
      method = "initialize",
      params = list(
        protocolVersion = "2025-06-18",
        capabilities = list(
          extensions = list(
            "io.modelcontextprotocol/ui" = list(
              mimeTypes = list("text/html;profile=mcp-app")
            )
          )
        )
      )
    ),
    app,
    registry,
    session
  )

  expect_equal(response$result$protocolVersion, "2025-06-18")
  expect_true(session$client_supports_ui)
  expect_true("tools" %in% names(response$result$capabilities))
  expect_true("resources" %in% names(response$result$capabilities))
})

test_that("tools/list omits _meta.ui for clients without the extension", {
  app <- make_test_app()
  registry <- make_test_registry(app)
  session <- new_mcp_session()

  dispatch_message(
    list(
      jsonrpc = "2.0",
      id = 1,
      method = "initialize",
      params = list(protocolVersion = "2025-06-18", capabilities = list())
    ),
    app,
    registry,
    session
  )
  expect_false(session$client_supports_ui)

  response <- dispatch_message(
    list(jsonrpc = "2.0", id = 2, method = "tools/list"),
    app,
    registry,
    session
  )
  tool <- response$result$tools[[1]]
  expect_equal(tool$name, "echo")
  # The nested _meta.ui block is withheld, but the deprecated flat key is
  # kept so draft-era hosts (which never advertise the extension) still
  # find the UI resource.
  expect_null(tool[["_meta"]]$ui)
  expect_equal(tool[["_meta"]][["ui/resourceUri"]], "ui://serve-test")
})

test_that("tools/list includes _meta.ui by default and for capable clients", {
  app <- make_test_app()
  registry <- make_test_registry(app)

  # No initialize at all: lenient default includes UI metadata
  response <- dispatch_message(
    list(jsonrpc = "2.0", id = 1, method = "tools/list"),
    app,
    registry
  )
  tool <- response$result$tools[[1]]
  expect_equal(tool[["_meta"]]$ui$resourceUri, "ui://serve-test")
  expect_equal(tool[["_meta"]][["ui/resourceUri"]], "ui://serve-test")
})

test_that("ping returns an empty result", {
  app <- make_test_app()
  registry <- make_test_registry(app)

  response <- dispatch_message(
    list(jsonrpc = "2.0", id = 7, method = "ping"),
    app,
    registry
  )
  expect_equal(response$id, 7)
  expect_length(response$result, 0)
  expect_null(response$error)
})

# ---- Resource _meta ----

test_that("resources include _meta.ui when the app declares CSP metadata", {
  app <- make_test_app(
    csp = list(connect_domains = "https://api.example.com"),
    prefers_border = TRUE
  )
  registry <- make_test_registry(app)

  listed <- dispatch_message(
    list(jsonrpc = "2.0", id = 1, method = "resources/list"),
    app,
    registry
  )
  resource <- listed$result$resources[[1]]
  expect_equal(
    as.character(resource[["_meta"]]$ui$csp$connectDomains),
    "https://api.example.com"
  )
  expect_true(resource[["_meta"]]$ui$prefersBorder)

  read <- dispatch_message(
    list(
      jsonrpc = "2.0",
      id = 2,
      method = "resources/read",
      params = list(uri = "ui://serve-test")
    ),
    app,
    registry
  )
  contents <- read$result$contents[[1]]
  expect_equal(contents$mimeType, SHINYMCP_UI_MIME_TYPE)
  expect_equal(
    as.character(contents[["_meta"]]$ui$csp$connectDomains),
    "https://api.example.com"
  )
})

test_that("resources omit _meta when the app declares nothing", {
  app <- make_test_app()
  registry <- make_test_registry(app)

  expect_null(app$resource_meta())

  listed <- dispatch_message(
    list(jsonrpc = "2.0", id = 1, method = "resources/list"),
    app,
    registry
  )
  expect_null(listed$result$resources[[1]][["_meta"]])
})

# ---- CSP helpers ----

test_that("csp_to_meta converts snake_case keys and keeps arrays", {
  meta <- csp_to_meta(list(
    connect_domains = c("https://a.com", "https://b.com"),
    resource_domains = "https://cdn.com"
  ))
  expect_equal(
    as.character(meta$connectDomains),
    c("https://a.com", "https://b.com")
  )
  expect_equal(as.character(meta$resourceDomains), "https://cdn.com")

  # Arrays survive JSON serialization as arrays even when length 1
  json <- to_json(list(csp = meta))
  expect_match(as.character(json), '"resourceDomains":\\["https://cdn.com"\\]')
})

test_that("csp_to_meta accepts spec camelCase keys and rejects unknown ones", {
  meta <- csp_to_meta(list(connectDomains = "https://a.com"))
  expect_equal(as.character(meta$connectDomains), "https://a.com")

  expect_error(
    csp_to_meta(list(bogus_field = "x")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    csp_to_meta(list("unnamed")),
    class = "shinymcp_error_validation"
  )
})

# ---- Tool visibility ----

test_that("tool_visibility appears in _meta.ui.visibility", {
  app <- make_test_app(tool_visibility = list(echo = "app"))
  defs <- app$tool_definitions()
  expect_equal(as.character(defs[[1]][["_meta"]]$ui$visibility), "app")

  # Serialized as an array per the spec
  json <- to_json(defs[[1]])
  expect_match(as.character(json), '"visibility":\\["app"\\]')
})

test_that("plain-list tools can carry their own visibility and outputSchema", {
  app <- McpApp$new(
    ui = htmltools::tags$div("Test"),
    tools = list(
      list(
        name = "refresh",
        description = "App-only refresh",
        visibility = c("app"),
        outputSchema = list(
          type = "object",
          properties = list(out = list(type = "string"))
        ),
        fun = function() list(out = "ok")
      )
    ),
    name = "vis-test"
  )
  defs <- app$tool_definitions()
  expect_equal(as.character(defs[[1]][["_meta"]]$ui$visibility), "app")
  expect_equal(defs[[1]]$outputSchema$type, "object")
})

test_that("invalid tool_visibility is rejected", {
  expect_error(
    make_test_app(tool_visibility = list(echo = "everyone")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    make_test_app(tool_visibility = c("app")),
    class = "shinymcp_error_validation"
  )
})

# ---- Bridge config ----

test_that("trigger and debounce_ms flow into the embedded bridge config", {
  app <- make_test_app(trigger = "change", debounce_ms = 100)
  html <- app$html_resource()

  config <- jsonlite::fromJSON(
    regmatches(
      html,
      regexpr(
        '(?<=<script id="shinymcp-config" type="application/json">).*?(?=</script>)',
        html,
        perl = TRUE
      )
    ),
    simplifyVector = TRUE
  )
  expect_equal(config$trigger, "change")
  expect_equal(config$debounceMs, 100)
})

test_that("invalid trigger is rejected", {
  expect_error(make_test_app(trigger = "sometimes"))
})

# ---- Extra resources ----

test_that("extra resources are listed and readable", {
  app <- make_test_app(
    resources = list(
      "ui://serve-test/data" = list(
        content = function() '{"a":1}',
        mime_type = "application/json",
        description = "Lazy data"
      ),
      "ui://serve-test/readme" = "hello"
    )
  )
  registry <- make_test_registry(app)

  listed <- dispatch_message(
    list(jsonrpc = "2.0", id = 1, method = "resources/list"),
    app,
    registry
  )
  uris <- vapply(listed$result$resources, function(r) r$uri, character(1))
  expect_setequal(
    uris,
    c("ui://serve-test", "ui://serve-test/data", "ui://serve-test/readme")
  )

  read <- dispatch_message(
    list(
      jsonrpc = "2.0",
      id = 2,
      method = "resources/read",
      params = list(uri = "ui://serve-test/data")
    ),
    app,
    registry
  )
  contents <- read$result$contents[[1]]
  expect_equal(contents$mimeType, "application/json")
  expect_equal(contents$text, '{"a":1}')

  # Static string shorthand defaults to text/plain
  static <- app$read_extra_resource("ui://serve-test/readme")
  expect_equal(static$mimeType, "text/plain")
  expect_equal(static$text, "hello")
})

test_that("read_extra_resource errors for unknown URIs", {
  app <- make_test_app()
  expect_error(
    app$read_extra_resource("ui://serve-test/nope"),
    class = "shinymcp_error_resource"
  )
})

test_that("invalid resources specs are rejected", {
  expect_error(
    make_test_app(resources = list("ui://x" = 42)),
    class = "shinymcp_error_validation"
  )
  expect_error(
    make_test_app(resources = list(list(content = "x"))),
    class = "shinymcp_error_validation"
  )
  expect_error(
    make_test_app(resources = list("ui://x" = list(content = 1:3))),
    class = "shinymcp_error_validation"
  )
})

test_that("function resources are evaluated lazily on each read", {
  counter <- 0
  app <- make_test_app(
    resources = list(
      "ui://serve-test/count" = function() {
        counter <<- counter + 1
        as.character(counter)
      }
    )
  )
  expect_equal(counter, 0)
  expect_equal(app$read_extra_resource("ui://serve-test/count")$text, "1")
  expect_equal(app$read_extra_resource("ui://serve-test/count")$text, "2")
})

# ---- outputSchema generation ----

test_that("tool_outputs generates an outputSchema with UI-derived descriptions", {
  app <- McpApp$new(
    ui = htmltools::tagList(
      mcp_plot("scatter"),
      mcp_text("stats")
    ),
    tools = list(
      list(
        name = "explore",
        description = "Explore",
        inputSchema = list(
          type = "object",
          properties = list(species = list(type = "string"))
        ),
        fun = function(species) list(scatter = "...", stats = "...")
      )
    ),
    name = "schema-test",
    tool_outputs = list(explore = c("scatter", "stats"))
  )

  defs <- app$tool_definitions()
  schema <- defs[[1]]$outputSchema
  expect_equal(schema$type, "object")
  expect_equal(schema$properties$scatter$type, "string")
  expect_match(schema$properties$scatter$description, "Base64-encoded PNG")
  expect_match(schema$properties$stats$description, "Text content")
  expect_setequal(unlist(schema$required), c("scatter", "stats"))
})

test_that("tools without tool_outputs get no outputSchema", {
  app <- make_test_app()
  defs <- app$tool_definitions()
  expect_null(defs[[1]]$outputSchema)
})

test_that("build_output_schema falls back for outputs not in the UI", {
  schema <- build_output_schema("mystery", c(known = "text"))
  expect_match(schema$properties$mystery$description, "Value for output")
  expect_null(build_output_schema(character(0)))
})

test_that("invalid tool_outputs is rejected", {
  expect_error(
    make_test_app(tool_outputs = list(echo = 1:3)),
    class = "shinymcp_error_validation"
  )
  expect_error(
    make_test_app(tool_outputs = c("out")),
    class = "shinymcp_error_validation"
  )
})

# ---- HTTP session management ----

fake_http_req <- function(body = NULL, method = "POST", session_id = NULL) {
  req <- list(
    REQUEST_METHOD = method,
    HTTP_MCP_SESSION_ID = session_id,
    rook.input = list(
      read_lines = function() if (is.null(body)) character(0) else body
    )
  )
  req
}

init_body <- function(with_ui = FALSE) {
  capabilities <- if (with_ui) {
    list(
      extensions = list(
        "io.modelcontextprotocol/ui" = list(
          mimeTypes = list("text/html;profile=mcp-app")
        )
      )
    )
  } else {
    list()
  }
  as.character(to_json(list(
    jsonrpc = "2.0",
    id = 1,
    method = "initialize",
    params = list(
      protocolVersion = "2025-06-18",
      capabilities = capabilities
    )
  )))
}

tools_list_body <- function() {
  as.character(to_json(list(jsonrpc = "2.0", id = 2, method = "tools/list")))
}

test_that("initialize assigns an Mcp-Session-Id header", {
  app <- make_test_app()
  registry <- make_test_registry(app)
  sessions <- new.env(parent = emptyenv())

  response <- handle_http_request(
    fake_http_req(init_body()),
    app,
    registry,
    sessions
  )
  expect_equal(response$status, 200L)
  sid <- response$headers[["Mcp-Session-Id"]]
  expect_true(is.character(sid) && nzchar(sid))
  expect_false(is.null(sessions[[sid]]))

  # Non-initialize responses don't carry the header
  follow_up <- handle_http_request(
    fake_http_req(tools_list_body(), session_id = sid),
    app,
    registry,
    sessions
  )
  expect_null(follow_up$headers[["Mcp-Session-Id"]])
})

test_that("HTTP sessions isolate capability negotiation per client", {
  app <- make_test_app()
  registry <- make_test_registry(app)
  sessions <- new.env(parent = emptyenv())

  resp_ui <- handle_http_request(
    fake_http_req(init_body(with_ui = TRUE)),
    app,
    registry,
    sessions
  )
  sid_ui <- resp_ui$headers[["Mcp-Session-Id"]]

  resp_plain <- handle_http_request(
    fake_http_req(init_body(with_ui = FALSE)),
    app,
    registry,
    sessions
  )
  sid_plain <- resp_plain$headers[["Mcp-Session-Id"]]
  expect_false(identical(sid_ui, sid_plain))

  tools_ui <- from_json(
    handle_http_request(
      fake_http_req(tools_list_body(), session_id = sid_ui),
      app,
      registry,
      sessions
    )$body
  )
  tools_plain <- from_json(
    handle_http_request(
      fake_http_req(tools_list_body(), session_id = sid_plain),
      app,
      registry,
      sessions
    )$body
  )

  expect_false(is.null(tools_ui$result$tools[[1]][["_meta"]]$ui))
  expect_null(tools_plain$result$tools[[1]][["_meta"]]$ui)
  # Both keep the deprecated flat key for draft-era hosts
  expect_equal(
    tools_plain$result$tools[[1]][["_meta"]][["ui/resourceUri"]],
    "ui://serve-test"
  )
})

test_that("DELETE terminates an HTTP session and stale ids get 404", {
  app <- make_test_app()
  registry <- make_test_registry(app)
  sessions <- new.env(parent = emptyenv())

  sid <- handle_http_request(
    fake_http_req(init_body(with_ui = FALSE)),
    app,
    registry,
    sessions
  )$headers[["Mcp-Session-Id"]]
  expect_false(is.null(sessions[[sid]]))

  deleted <- handle_http_request(
    fake_http_req(method = "DELETE", session_id = sid),
    app,
    registry,
    sessions
  )
  expect_equal(deleted$status, 204L)
  expect_null(sessions[[sid]])

  # Requests on a terminated/unknown session id are rejected per the
  # streamable-HTTP spec so the client re-initializes
  stale <- handle_http_request(
    fake_http_req(tools_list_body(), session_id = sid),
    app,
    registry,
    sessions
  )
  expect_equal(stale$status, 404L)
})

test_that("unknown session ids do not mint sessions", {
  app <- make_test_app()
  registry <- make_test_registry(app)
  sessions <- new.env(parent = emptyenv())

  response <- handle_http_request(
    fake_http_req(tools_list_body(), session_id = "made-up-id"),
    app,
    registry,
    sessions
  )
  expect_equal(response$status, 404L)
  expect_length(ls(sessions), 0)
})

test_that("header-less clients keep their negotiated session via __default__", {
  app <- make_test_app()
  registry <- make_test_registry(app)
  sessions <- new.env(parent = emptyenv())

  # Initialize without a header, declaring NO UI support
  handle_http_request(
    fake_http_req(init_body(with_ui = FALSE)),
    app,
    registry,
    sessions
  )

  # Follow-up without echoing the header still reflects that negotiation
  tools <- from_json(
    handle_http_request(
      fake_http_req(tools_list_body()),
      app,
      registry,
      sessions
    )$body
  )
  expect_null(tools$result$tools[[1]][["_meta"]]$ui)
})

test_that("prune_http_sessions caps the session store", {
  sessions <- new.env(parent = emptyenv())
  for (i in 1:5) {
    session <- new_mcp_session()
    session$created <- i
    sessions[[paste0("sid-", i)]] <- session
  }
  sessions[["__default__"]] <- new_mcp_session()

  prune_http_sessions(sessions, max_sessions = 3)

  remaining <- ls(sessions)
  expect_true("__default__" %in% remaining)
  expect_setequal(
    setdiff(remaining, "__default__"),
    c("sid-3", "sid-4", "sid-5")
  )
})

test_that("non-POST methods other than DELETE are rejected", {
  app <- make_test_app()
  registry <- make_test_registry(app)
  sessions <- new.env(parent = emptyenv())

  response <- handle_http_request(
    fake_http_req(method = "GET"),
    app,
    registry,
    sessions
  )
  expect_equal(response$status, 405L)
})

# ---- Host-side resources/read ----

test_that("mcp_host_read_resource serves the app and extra resources", {
  app <- make_test_app(
    resources = list("ui://serve-test/data" = "payload")
  )
  state <- new_mcp_host_state(app, instance_id = "test-instance")

  own <- mcp_host_read_resource(state, "ui://serve-test")
  expect_equal(own$contents[[1]]$mimeType, SHINYMCP_UI_MIME_TYPE)
  expect_match(own$contents[[1]]$text, "<!DOCTYPE html>")

  extra <- mcp_host_read_resource(state, "ui://serve-test/data")
  expect_equal(extra$contents[[1]]$text, "payload")

  expect_error(
    mcp_host_read_resource(state, "ui://other"),
    class = "shinymcp_error_resource"
  )
})

# ---- Review follow-ups ----

test_that("mcp_tools excludes app-only tools and carries visibility", {
  app <- McpApp$new(
    ui = htmltools::tags$div("Test"),
    tools = list(
      list(name = "for_model", description = "", fun = function() "ok"),
      list(name = "ui_only", description = "", fun = function() "ok")
    ),
    name = "vis-filter",
    tool_visibility = list(ui_only = "app", for_model = c("model", "app"))
  )

  tools <- app$mcp_tools()
  expect_length(tools, 1)
  expect_equal(tools[[1]]$name, "for_model")
  expect_equal(tools[[1]][["_meta"]]$ui$resourceUri, "ui://vis-filter")
  expect_equal(
    as.character(tools[[1]][["_meta"]]$ui$visibility),
    c("model", "app")
  )
  expect_equal(tools[[1]][["_meta"]][["ui/resourceUri"]], "ui://vis-filter")
})

test_that("tool_visibility/tool_outputs names are checked against tools", {
  expect_warning(
    make_test_app(tool_visibility = list(echoo = "app")),
    "match no tool"
  )
  expect_warning(
    make_test_app(tool_outputs = list(wrong_name = "out")),
    "match no tool"
  )
  expect_no_warning(make_test_app(tool_outputs = list(echo = "out")))
})

test_that("resource text is coerced to a plain string (json class, vectors)", {
  app <- make_test_app(
    resources = list(
      "ui://serve-test/json" = function() {
        jsonlite::toJSON(list(a = 1), auto_unbox = TRUE)
      },
      "ui://serve-test/lines" = function() c("line 1", "line 2")
    )
  )
  registry <- make_test_registry(app)

  json_entry <- app$read_extra_resource("ui://serve-test/json")
  expect_identical(class(json_entry$text), "character")
  expect_equal(as.character(json_entry$text), "{\"a\":1}")

  via_registry <- registry$read_resource("ui://serve-test/json")
  expect_identical(class(via_registry$text), "character")

  lines_entry <- app$read_extra_resource("ui://serve-test/lines")
  expect_equal(lines_entry$text, "line 1\nline 2")
})

test_that("resolve_host_interaction defers to the app's declaration", {
  declared <- make_test_app(trigger = "change", debounce_ms = 50)
  undeclared <- make_test_app()

  # Host didn't specify: app's declaration wins
  expect_equal(
    resolve_host_interaction(declared, NULL, NULL),
    list(trigger = "change", debounce_ms = 50)
  )
  # Host specified: host wins
  expect_equal(
    resolve_host_interaction(declared, "submit", 500),
    list(trigger = "submit", debounce_ms = 500)
  )
  # Nothing declared anywhere: package defaults
  expect_equal(
    resolve_host_interaction(undeclared, NULL, NULL),
    list(trigger = "debounce", debounce_ms = 250)
  )
})

test_that("warn_host_only_trigger flags submit/manual apps", {
  expect_warning(
    warn_host_only_trigger(make_test_app(trigger = "submit"), "serve()"),
    "only works inside"
  )
  expect_no_warning(
    warn_host_only_trigger(make_test_app(trigger = "change"), "serve()")
  )
  expect_no_warning(warn_host_only_trigger(make_test_app(), "serve()"))
})
