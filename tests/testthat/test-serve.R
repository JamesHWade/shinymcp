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
  registry
}

# ---- Protocol version negotiation ----

test_that("negotiate_protocol_version echoes supported client versions", {
  expect_equal(negotiate_protocol_version("2025-06-18"), "2025-06-18")
  expect_equal(negotiate_protocol_version("2024-11-05"), "2024-11-05")
  expect_equal(negotiate_protocol_version("2025-11-25"), "2025-11-25")
})

test_that("negotiate_protocol_version falls back to latest for unknown versions", {
  expect_equal(negotiate_protocol_version("1999-01-01"), SHINYMCP_PROTOCOL_VERSION)
  expect_equal(negotiate_protocol_version("2099-01-01"), SHINYMCP_PROTOCOL_VERSION)
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
  expect_null(tool[["_meta"]])
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
  expect_equal(as.character(meta$connectDomains), c("https://a.com", "https://b.com"))
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
