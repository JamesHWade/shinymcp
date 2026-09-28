# McpServer and the MCP protocol (R/protocol.R). Transports feed the server
# parsed messages; these tests call McpServer$handle() directly.

modern_version <- "2026-07-28"
legacy_versions <- c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")

# Send initialize on a fresh legacy session and return that session.
initialize_session <- function(server, ui = TRUE, version = "2025-06-18", ...) {
  session <- server$new_session()
  server$handle(
    serving_initialize(ui = ui, version = version, ...),
    list(transport = "test", session = session)
  )
  session
}

tool_names <- function(response) {
  vapply(response$result$tools, function(tool) tool$name, character(1))
}

# ---- Versions and capabilities ----

test_that("the server speaks the modern and legacy versions, newest first", {
  expect_equal(SHINYMCP_PROTOCOL_VERSIONS, c(modern_version, legacy_versions))
  expect_equal(SHINYMCP_PROTOCOL_VERSION, "2025-11-25")
})

test_that("negotiate_protocol_version() echoes each supported legacy version", {
  for (version in legacy_versions) {
    expect_equal(negotiate_protocol_version(version), version)
  }
})

test_that("negotiate_protocol_version() offers the latest legacy version otherwise", {
  expect_equal(negotiate_protocol_version("1999-01-01"), "2025-11-25")
  expect_equal(negotiate_protocol_version("2099-12-31"), "2025-11-25")
  # The stateless version is not negotiated through initialize.
  expect_equal(negotiate_protocol_version(modern_version), "2025-11-25")
  expect_equal(negotiate_protocol_version(NULL), "2025-11-25")
  expect_equal(negotiate_protocol_version(""), "2025-11-25")
  expect_equal(negotiate_protocol_version(20250618), "2025-11-25")
  expect_equal(negotiate_protocol_version(list("2025-06-18")), "2025-11-25")
  expect_equal(
    negotiate_protocol_version(c("2025-06-18", "2024-11-05")),
    "2025-11-25"
  )
})

test_that("capabilities_support_ui() reads the MCP Apps extension", {
  ui <- function(...) {
    list(extensions = list(`io.modelcontextprotocol/ui` = list(...)))
  }

  expect_true(capabilities_support_ui(serving_ui_capabilities()))
  expect_true(capabilities_support_ui(ui(
    mimeTypes = list("text/plain", "text/html;profile=mcp-app")
  )))
  expect_true(capabilities_support_ui(ui(
    mimeTypes = "text/html;profile=mcp-app"
  )))
  # No mimeTypes is read as the default HTML profile.
  expect_true(capabilities_support_ui(ui()))
  expect_true(capabilities_support_ui(from_json(
    '{"extensions":{"io.modelcontextprotocol/ui":{}}}'
  )))

  expect_false(capabilities_support_ui(ui(mimeTypes = list("text/html"))))
  expect_false(capabilities_support_ui(list(
    extensions = list(`io.example/other` = list())
  )))
  expect_false(capabilities_support_ui(list(tools = list())))
  expect_false(capabilities_support_ui(list()))
  expect_false(capabilities_support_ui(NULL))
})

test_that("client_supports_mcp_apps() reads initialize params", {
  expect_true(client_supports_mcp_apps(list(
    capabilities = serving_ui_capabilities()
  )))
  expect_false(client_supports_mcp_apps(list(capabilities = list())))
  expect_false(client_supports_mcp_apps(list()))
})

test_that("an empty mimeTypes list does not declare MCP Apps support", {
  expect_false(capabilities_support_ui(
    from_json('{"extensions":{"io.modelcontextprotocol/ui":{"mimeTypes":[]}}}')
  ))
})

test_that("a UI extension that isn't an object declares no MCP Apps support", {
  declared <- function(value) {
    from_json(sprintf(
      '{"extensions":{"io.modelcontextprotocol/ui":%s}}',
      value
    ))
  }
  for (value in c("false", "true", "0", '"text/html;profile=mcp-app"', "[1]")) {
    expect_false(capabilities_support_ui(declared(value)), label = value)
  }

  # Such a client is served as one without MCP Apps: no app-only tools.
  server <- McpServer$new(serving_app())
  session <- server$new_session()
  server$handle(
    serving_rpc(
      "initialize",
      list(protocolVersion = "2025-06-18", capabilities = declared("false"))
    ),
    list(session = session)
  )
  expect_false(session$client_supports_ui)
  listed <- server$handle(
    serving_rpc("tools/list", id = 2),
    list(session = session)
  )
  expect_equal(tool_names(listed), c("echo", "boom"))
})

test_that("message fields are matched exactly, never by prefix", {
  calls <- 0
  server <- McpServer$new(serving_app(
    tools = list(list(
      name = "echo",
      fun = function(x = "") {
        calls <<- calls + 1
        list(out = x)
      }
    ))
  ))

  named_by_prefix <- server$handle(serving_rpc(
    "tools/call",
    list(nameExtra = "echo")
  ))
  expect_equal(named_by_prefix$error$code, RPC_INVALID_PARAMS)
  params_by_prefix <- server$handle(list(
    jsonrpc = "2.0",
    id = 1,
    method = "tools/call",
    paramsX = list(name = "echo")
  ))
  expect_equal(params_by_prefix$error$code, RPC_INVALID_PARAMS)
  expect_equal(calls, 0)

  # A field that starts with "id" isn't the id.
  bad <- server$handle(list(jsonrpc = "2.0", method = 5, idempotent = 1))
  expect_true("id" %in% names(bad))
  expect_null(bad$id)
})

# ---- JSON-RPC helpers ----

test_that("jsonrpc_response() and jsonrpc_error() build JSON-RPC 2.0 messages", {
  expect_equal(
    serving_json_text(jsonrpc_response(3, json_object())),
    '{"jsonrpc":"2.0","id":3,"result":{}}'
  )

  err <- jsonrpc_error(7, -32601L, "Method not found: x")
  expect_equal(attr(err, "http_status"), 200L)
  expect_equal(
    serving_json_text(strip_http_status(err)),
    '{"jsonrpc":"2.0","id":7,"error":{"code":-32601,"message":"Method not found: x"}}'
  )

  err <- jsonrpc_error(
    NULL,
    -32022L,
    "Unsupported",
    data = list(requested = "x"),
    status = 400L
  )
  expect_equal(attr(err, "http_status"), 400L)
  expect_equal(
    serving_json_text(strip_http_status(err)),
    '{"jsonrpc":"2.0","id":null,"error":{"code":-32022,"message":"Unsupported","data":{"requested":"x"}}}'
  )
})

test_that("rpc_stop() signals a condition carrying the JSON-RPC error", {
  cnd <- tryCatch(
    rpc_stop(
      "Bad thing",
      code = -32602L,
      data = list(why = "x"),
      status = 404L
    ),
    shinymcp_rpc_error = function(e) e
  )
  expect_s3_class(cnd, "shinymcp_rpc_error")
  expect_equal(conditionMessage(cnd), "Bad thing")
  expect_equal(e_code(cnd), -32602L)
  expect_equal(cnd$data, list(why = "x"))
  expect_equal(cnd$status, 404L)
})

# ---- Constructing a server ----

test_that("a server for one app is named after it and describes it", {
  server <- McpServer$new(serving_app(description = "Echo things back."))
  expect_equal(server$name, "shinymcp-fx")
  expect_equal(server$version, as.character(utils::packageVersion("shinymcp")))
  expect_equal(
    server$instructions,
    "This server provides interactive apps:\n- fx: Echo things back."
  )
  expect_length(server$apps, 1)
})

test_that("a server for several apps lists the described ones in its instructions", {
  alpha <- serving_app(
    "alpha",
    tools = list(serving_echo_tool("alpha_echo")),
    title = "Alpha",
    description = "First."
  )
  beta <- serving_app("beta", tools = list(serving_echo_tool("beta_echo")))
  gamma <- serving_app(
    "gamma",
    tools = list(serving_echo_tool("gamma_echo")),
    description = "Third."
  )
  server <- McpServer$new(list(alpha, beta, gamma))
  expect_equal(server$name, "shinymcp")
  expect_equal(
    server$instructions,
    "This server provides interactive apps:\n- Alpha: First.\n- gamma: Third."
  )
})

test_that("server name, version and instructions can be given", {
  server <- McpServer$new(
    serving_app(),
    name = "custom",
    version = "9.9.9",
    instructions = "Use me."
  )
  expect_equal(server$name, "custom")
  expect_equal(server$version, "9.9.9")
  expect_equal(server$instructions, "Use me.")
})

test_that("server_instructions() is NULL when no app has a description", {
  expect_null(server_instructions(list(serving_app())))
  expect_null(McpServer$new(serving_app())$instructions)
})

test_that("as_app_list() accepts an app or a list of apps", {
  app <- serving_app()
  expect_identical(as_app_list(app)[[1]], app)
  two <- as_app_list(list(app, serving_app("other", tools = list())))
  expect_length(two, 2)
  expect_equal(vapply(two, function(a) a$name, character(1)), c("fx", "other"))
})

test_that("as_app_list() rejects duplicate names and non-apps", {
  expect_error(
    as_app_list(list(serving_app(), serving_app(tools = list()))),
    class = "shinymcp_error_validation"
  )
  expect_error(as_app_list(list()), class = "shinymcp_error_validation")
  expect_error(as_app_list(42), class = "shinymcp_error_validation")
  expect_error(
    McpServer$new(list(serving_app(), 42)),
    class = "shinymcp_error_validation"
  )
})

test_that("a Shiny app object can be served directly", {
  skip_if_not_installed("shiny")
  shiny_app <- shiny::shinyApp(
    shiny::fluidPage(
      shiny::textInput("who", "Who"),
      shiny::textOutput("hello")
    ),
    function(input, output, session) {
      output$hello <- shiny::renderText(input$who)
    }
  )
  server <- McpServer$new(shiny_app)
  expect_length(server$apps, 1)
  expect_equal(server$apps[[1]]$name, "shiny-app")
})

test_that("tool names must be unique across the apps a server serves", {
  alpha <- serving_app("alpha", tools = list(serving_echo_tool()))
  beta <- serving_app("beta", tools = list(serving_echo_tool()))
  expect_error(
    McpServer$new(list(alpha, beta)),
    "echo",
    class = "shinymcp_error_validation"
  )
})

test_that("resource URIs must be unique across the apps a server serves", {
  alpha <- serving_app(
    "alpha",
    tools = list(serving_echo_tool("alpha_echo")),
    resources = list("ui://beta" = "shadowing beta's page")
  )
  beta <- serving_app("beta", tools = list(serving_echo_tool("beta_echo")))
  expect_error(
    McpServer$new(list(alpha, beta)),
    "ui://beta",
    class = "shinymcp_error_validation"
  )
})

# ---- Legacy era: initialize ----

test_that("initialize echoes a supported version and describes the server", {
  server <- McpServer$new(serving_app())
  response <- server$handle(
    serving_initialize(version = "2025-06-18"),
    list(session = server$new_session())
  )

  expect_equal(response$jsonrpc, "2.0")
  expect_equal(response$id, 1)
  expect_null(attr(response, "http_status"))
  result <- response$result
  expect_equal(result$protocolVersion, "2025-06-18")
  expect_equal(
    result$serverInfo,
    list(name = "shinymcp-fx", version = server$version)
  )
  expect_equal(result$capabilities$tools, list(listChanged = FALSE))
  expect_equal(
    result$capabilities$resources,
    list(subscribe = FALSE, listChanged = FALSE)
  )
  expect_named(result$capabilities$extensions, "io.modelcontextprotocol/ui")
  # Legacy results carry no modern metadata.
  expect_null(result$resultType)
  expect_null(result[["_meta"]])

  json <- serving_json_text(response)
  expect_match(
    json,
    '"extensions":{"io.modelcontextprotocol/ui":{}}',
    fixed = TRUE
  )
})

test_that("initialize offers the latest legacy version for versions it doesn't know", {
  server <- McpServer$new(serving_app())
  session <- initialize_session(server, version = "2099-01-01")
  expect_equal(session$protocol_version, "2025-11-25")

  response <- server$handle(serving_initialize(version = "2099-01-01"), list())
  expect_equal(response$result$protocolVersion, "2025-11-25")
})

test_that("initialize records the client's MCP Apps support in the session", {
  server <- McpServer$new(serving_app())

  session <- initialize_session(
    server,
    ui = TRUE,
    client = list(name = "ui-client", version = "2.0")
  )
  expect_true(session$client_supports_ui)
  expect_true(session$initialized)
  expect_equal(session$protocol_version, "2025-06-18")
  expect_equal(session$client_info, list(name = "ui-client", version = "2.0"))

  session <- initialize_session(server, ui = FALSE)
  expect_false(session$client_supports_ui)
  expect_true(session$initialized)

  # The extension without mimeTypes means the default HTML profile.
  session <- server$new_session()
  server$handle(
    serving_rpc(
      "initialize",
      list(
        protocolVersion = "2025-06-18",
        capabilities = list(
          extensions = list(`io.modelcontextprotocol/ui` = json_object())
        )
      )
    ),
    list(session = session)
  )
  expect_true(session$client_supports_ui)

  # A client that renders other MIME types only doesn't get apps.
  session <- server$new_session()
  server$handle(
    serving_rpc(
      "initialize",
      list(
        protocolVersion = "2025-06-18",
        capabilities = list(
          extensions = list(
            `io.modelcontextprotocol/ui` = list(mimeTypes = list("text/html"))
          )
        )
      )
    ),
    list(session = session)
  )
  expect_false(session$client_supports_ui)
})

test_that("instructions are omitted, not null, when no app has a description", {
  server <- McpServer$new(serving_app())
  response <- server$handle(
    serving_initialize(),
    list(session = server$new_session())
  )
  expect_false("instructions" %in% names(response$result))
  expect_false(grepl("null", serving_json_text(response), fixed = TRUE))

  described <- McpServer$new(serving_app(description = "Echo things back."))
  response <- described$handle(
    serving_initialize(),
    list(session = described$new_session())
  )
  expect_equal(response$result$instructions, described$instructions)
})

test_that("initialize works without a transport session", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_initialize(version = "2024-11-05"))
  expect_equal(response$result$protocolVersion, "2024-11-05")
})

test_that("a new legacy session is lenient until the client initializes", {
  session <- new_mcp_session()
  expect_true(is.environment(session))
  expect_true(session$client_supports_ui)
  expect_equal(session$protocol_version, "2025-11-25")
  expect_null(session$client_info)
  expect_false(session$initialized)
  expect_true(is.numeric(session$created))
  expect_false(identical(new_mcp_session(), session))
})

# ---- Legacy era: other methods ----

test_that("ping answers an empty object and echoes the request id", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_rpc("ping", id = "abc-1"))
  expect_equal(
    serving_json_text(response),
    '{"jsonrpc":"2.0","id":"abc-1","result":{}}'
  )
})

test_that("notifications get no response and run nothing", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))

  expect_null(server$handle(serving_rpc(
    "notifications/initialized",
    id = NULL
  )))
  expect_null(server$handle(serving_rpc(
    "notifications/cancelled",
    list(requestId = 1),
    id = NULL
  )))
  expect_null(server$handle(serving_rpc(
    "tools/call",
    list(name = "context"),
    id = NULL
  )))
  expect_null(server$handle(serving_rpc("no/such/method", id = NULL)))
  expect_equal(recorder$calls, 0L)
})

test_that("responses sent by the client get no response", {
  server <- McpServer$new(serving_app())
  expect_null(server$handle(list(
    jsonrpc = "2.0",
    id = 3,
    result = json_object()
  )))
  expect_null(server$handle(list(
    jsonrpc = "2.0",
    id = 4,
    error = list(code = -1, message = "no")
  )))
  # A result can be null.
  expect_null(server$handle(from_json(
    '{"jsonrpc":"2.0","id":5,"result":null}'
  )))
})

test_that("a request whose id is null or not a string or number is refused", {
  server <- McpServer$new(serving_app())
  for (json in c(
    '{"jsonrpc":"2.0","id":null,"method":"ping"}',
    '{"jsonrpc":"2.0","id":true,"method":"ping"}',
    '{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}',
    '{"jsonrpc":"2.0","id":[1],"method":"ping"}'
  )) {
    response <- server$handle(from_json(json))
    expect_false(is.null(response), info = json)
    expect_null(response$id, info = json)
    expect_equal(response$error$code, -32600L, info = json)
    expect_match(
      serving_json_text(strip_http_status(response)),
      '"id":null',
      fixed = TRUE
    )
  }
  # Without an id at all, it's a notification: no answer.
  expect_null(server$handle(from_json('{"jsonrpc":"2.0","method":"ping"}')))
})

test_that("a message that is neither request nor response is refused", {
  server <- McpServer$new(serving_app())
  for (json in c(
    '{"jsonrpc":"2.0","id":1}',
    '{"jsonrpc":"2.0","id":1,"method":null}'
  )) {
    response <- server$handle(from_json(json))
    expect_equal(response$id, 1, info = json)
    expect_equal(response$error$code, -32600L, info = json)
    expect_equal(attr(response, "http_status"), 400L, info = json)
  }
  response <- server$handle(list(jsonrpc = "2.0"))
  expect_null(response$id)
  expect_equal(response$error$code, -32600L)
})

test_that("messages that aren't JSON-RPC 2.0 are invalid requests", {
  server <- McpServer$new(serving_app())

  response <- server$handle(list(id = 4, method = "ping"))
  expect_equal(response$id, 4)
  expect_equal(response$error$code, -32600L)
  expect_match(response$error$message, "JSON-RPC 2.0")
  expect_equal(attr(response, "http_status"), 400L)

  response <- server$handle(list(jsonrpc = "1.0", id = 5, method = "ping"))
  expect_equal(response$id, 5)
  expect_equal(response$error$code, -32600L)

  response <- server$handle(list())
  expect_null(response$id)
  expect_equal(response$error$code, -32600L)
  expect_match(
    serving_json_text(strip_http_status(response)),
    '"id":null',
    fixed = TRUE
  )
})

test_that("a message that is not an object is an invalid request", {
  server <- McpServer$new(serving_app())
  for (message in list(42, "ping", TRUE)) {
    response <- server$handle(message)
    expect_equal(response$error$code, -32600L)
    expect_equal(attr(response, "http_status"), 400L)
  }
})

test_that("a method that is not a string is an invalid request", {
  server <- McpServer$new(serving_app())
  for (method in list(4L, 1, TRUE)) {
    response <- server$handle(list(jsonrpc = "2.0", id = 1, method = method))
    expect_null(response$result)
    expect_equal(response$error$code, -32600L)
  }
})

test_that("malformed params give a JSON-RPC error, not an R error", {
  server <- McpServer$new(serving_app())
  bad_capabilities <- serving_modern("tools/list")
  bad_capabilities$params[["_meta"]][[
    "io.modelcontextprotocol/clientCapabilities"
  ]] <- "x"
  malformed <- list(
    list(jsonrpc = "2.0", id = 1, method = "tools/list", params = "x"),
    list(
      jsonrpc = "2.0",
      id = 1,
      method = "tools/list",
      params = list(`_meta` = "x")
    ),
    bad_capabilities,
    serving_modern("tools/list", version = list())
  )
  for (message in malformed) {
    response <- tryCatch(server$handle(message), error = function(e) e)
    expect_false(inherits(response, "error"))
    expect_false(is.null(response$error))
  }
})

test_that("unknown methods are not found, with HTTP status 200 in the legacy era", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_rpc("tools/destroy", id = 9))
  expect_equal(response$id, 9)
  expect_equal(response$error$code, -32601L)
  expect_equal(response$error$message, "Method not found: tools/destroy")
  expect_equal(attr(response, "http_status"), 200L)
})

test_that("empty listings serialize as JSON arrays", {
  server <- McpServer$new(serving_app(tools = list()))
  expect_equal(
    serving_json_text(server$handle(serving_rpc("tools/list"))),
    '{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}'
  )
  expect_equal(
    serving_json_text(server$handle(serving_rpc("resources/templates/list"))),
    '{"jsonrpc":"2.0","id":1,"result":{"resourceTemplates":[]}}'
  )
  expect_equal(
    serving_json_text(server$handle(serving_rpc("prompts/list"))),
    '{"jsonrpc":"2.0","id":1,"result":{"prompts":[]}}'
  )
})

test_that("legacy results carry no caching hints or server info", {
  server <- McpServer$new(serving_app())
  for (method in c("tools/list", "resources/list", "prompts/list")) {
    result <- server$handle(serving_rpc(method))$result
    expect_null(result$resultType)
    expect_null(result$ttlMs)
    expect_null(result$cacheScope)
    expect_null(result[["_meta"]])
  }
})

# ---- Modern era ----

test_that("server/discover advertises versions and capabilities without nulls", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_modern("server/discover"))
  result <- response$result

  expect_equal(
    as.character(unlist(result$supportedVersions)),
    c(modern_version, legacy_versions)
  )
  expect_equal(result$capabilities$tools, list(listChanged = FALSE))
  expect_named(result$capabilities$extensions, "io.modelcontextprotocol/ui")
  expect_equal(result$ttlMs, 60000)
  expect_equal(result$cacheScope, "public")
  expect_equal(result$resultType, "complete")
  expect_equal(
    result[["_meta"]][["io.modelcontextprotocol/serverInfo"]],
    list(name = "shinymcp-fx", version = server$version)
  )
  expect_false("instructions" %in% names(result))

  json <- serving_json_text(response)
  expect_false(grepl("null", json, fixed = TRUE))
  expect_match(
    json,
    '"supportedVersions":["2026-07-28","2025-11-25"',
    fixed = TRUE
  )
})

test_that("server/discover includes instructions when there are some", {
  server <- McpServer$new(serving_app(description = "Echo things back."))
  result <- server$handle(serving_modern("server/discover"))$result
  expect_equal(result$instructions, server$instructions)
})

test_that("modern results are complete and carry the server's info", {
  server <- McpServer$new(serving_app())
  info <- list(name = "shinymcp-fx", version = server$version)
  messages <- list(
    serving_modern("ping"),
    serving_modern("tools/list"),
    serving_modern("resources/list"),
    serving_modern("resources/read", list(uri = "ui://fx")),
    serving_modern(
      "tools/call",
      list(name = "echo", arguments = list(x = "hi"))
    )
  )
  for (message in messages) {
    result <- server$handle(message)$result
    expect_equal(result$resultType, "complete", info = message$method)
    expect_equal(
      result[["_meta"]][["io.modelcontextprotocol/serverInfo"]],
      info,
      info = message$method
    )
  }
  # A tool result keeps its own _meta next to the server info.
  result <- server$handle(serving_modern(
    "tools/call",
    list(name = "echo", arguments = list(x = "hi"))
  ))$result
  expect_equal(result[["_meta"]][["shinymcp/view"]]$tool, "echo")
})

test_that("unsupported modern versions are rejected with -32022", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_modern(
    "tools/list",
    version = "2027-01-01",
    id = 12
  ))

  expect_equal(response$id, 12)
  expect_equal(response$error$code, -32022L)
  expect_equal(response$error$message, "Unsupported protocol version")
  expect_equal(
    as.character(unlist(response$error$data$supported)),
    c(modern_version, legacy_versions)
  )
  expect_equal(response$error$data$requested, "2027-01-01")
  expect_equal(attr(response, "http_status"), 400L)
  expect_match(
    serving_json_text(strip_http_status(response)),
    '"data":{"supported":["2026-07-28",',
    fixed = TRUE
  )

  # Legacy versions are negotiated with initialize, not sent per request.
  response <- server$handle(serving_modern(
    "tools/list",
    version = "2025-06-18"
  ))
  expect_equal(response$error$code, -32022L)
  expect_equal(response$error$data$requested, "2025-06-18")
})

test_that("modern notifications with an unsupported version get no response", {
  server <- McpServer$new(serving_app())
  expect_null(server$handle(serving_modern(
    "notifications/initialized",
    version = "2027-01-01",
    id = NULL
  )))
  expect_null(server$handle(serving_modern(
    "notifications/initialized",
    id = NULL
  )))
})

test_that("unknown methods are not found, with HTTP status 404 in the modern era", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_modern("tools/destroy"))
  expect_equal(response$error$code, -32601L)
  expect_equal(attr(response, "http_status"), 404L)
})

test_that("modern list results carry caching hints", {
  server <- McpServer$new(serving_app())
  for (method in c(
    "tools/list",
    "resources/list",
    "resources/templates/list",
    "prompts/list"
  )) {
    result <- server$handle(serving_modern(method))$result
    expect_equal(result$ttlMs, 60000, info = method)
    expect_equal(result$cacheScope, "private", info = method)
  }
  result <- server$handle(serving_modern(
    "resources/read",
    list(uri = "ui://fx")
  ))$result
  expect_equal(result$ttlMs, 0)
  expect_equal(result$cacheScope, "private")
})

test_that("modern clients declare MCP Apps support on each request", {
  server <- McpServer$new(serving_app())
  # A legacy session that declared no UI support doesn't affect modern requests.
  context <- list(session = initialize_session(server, ui = FALSE))

  with_ui <- server$handle(serving_modern("tools/list", ui = TRUE), context)
  expect_equal(tool_names(with_ui), c("echo", "boom", "refresh"))
  expect_equal(
    with_ui$result$tools[[1]][["_meta"]][["ui"]]$resourceUri,
    "ui://fx"
  )

  without_ui <- server$handle(serving_modern("tools/list", ui = FALSE), context)
  expect_equal(tool_names(without_ui), c("echo", "boom"))
  expect_null(without_ui$result$tools[[1]][["_meta"]][["ui"]])
  expect_equal(
    without_ui$result$tools[[1]][["_meta"]][["ui/resourceUri"]],
    "ui://fx"
  )
})

test_that("initialize is always the legacy handshake", {
  server <- McpServer$new(serving_app())
  message <- serving_initialize(version = "2025-03-26")
  message$params[["_meta"]] <- list(
    `io.modelcontextprotocol/protocolVersion` = modern_version
  )
  response <- server$handle(message, list(session = server$new_session()))
  expect_equal(response$result$protocolVersion, "2025-03-26")
  expect_null(response$result$resultType)
})

# ---- tools/list ----

test_that("tools/list links every tool to the app's ui:// resource", {
  server <- McpServer$new(serving_app())
  # No initialize: served leniently, as a client with MCP Apps support.
  response <- server$handle(serving_rpc("tools/list"))
  tools <- response$result$tools

  expect_equal(tool_names(response), c("echo", "boom", "refresh"))
  for (tool in tools) {
    expect_equal(tool[["_meta"]][["ui/resourceUri"]], "ui://fx")
    expect_equal(tool[["_meta"]][["ui"]]$resourceUri, "ui://fx")
  }
  expect_null(tools[[1]][["_meta"]][["ui"]]$visibility)
  expect_equal(
    as.character(unlist(tools[[3]][["_meta"]][["ui"]]$visibility)),
    "app"
  )
  expect_match(
    serving_json_text(response),
    '"visibility":["app"]',
    fixed = TRUE
  )
})

test_that("tools/list describes each tool's arguments", {
  server <- McpServer$new(serving_app())
  echo <- server$handle(serving_rpc("tools/list"))$result$tools[[1]]
  expect_equal(echo$description, "Echo x back.")
  expect_equal(echo$inputSchema$type, "object")
  expect_equal(echo$inputSchema$properties$x$type, "string")
})

test_that("clients without MCP Apps support get no app-only tools and no nested ui", {
  server <- McpServer$new(serving_app())
  session <- initialize_session(server, ui = FALSE)
  response <- server$handle(
    serving_rpc("tools/list", id = 2),
    list(session = session)
  )

  expect_equal(tool_names(response), c("echo", "boom"))
  for (tool in response$result$tools) {
    expect_null(tool[["_meta"]][["ui"]])
    # The flat key stays for hosts that predate capability negotiation.
    expect_equal(tool[["_meta"]][["ui/resourceUri"]], "ui://fx")
  }
})

test_that("clients with MCP Apps support see app-only tools", {
  server <- McpServer$new(serving_app())
  session <- initialize_session(server, ui = TRUE)
  response <- server$handle(
    serving_rpc("tools/list", id = 2),
    list(session = session)
  )
  expect_equal(tool_names(response), c("echo", "boom", "refresh"))
})

test_that("ellmer tools are listed with their argument schema", {
  skip_if_not_installed("ellmer")
  app <- mcp_app(
    ui = htmltools::tags$div(mcp_text("greeting")),
    tools = list(ellmer::tool(
      function(name = "world") list(greeting = paste0("Hello, ", name, "!")),
      name = "greet",
      description = "Greet someone.",
      arguments = list(
        name = ellmer::type_string("Who to greet.", required = FALSE)
      )
    )),
    name = "greeter"
  )
  server <- McpServer$new(app)

  tool <- server$handle(serving_rpc("tools/list"))$result$tools[[1]]
  expect_equal(tool$name, "greet")
  expect_equal(tool$description, "Greet someone.")
  expect_equal(tool$inputSchema$properties$name$type, "string")
  expect_equal(tool$inputSchema$properties$name$description, "Who to greet.")

  result <- server$handle(serving_rpc(
    "tools/call",
    list(name = "greet", arguments = list(name = "Ada"))
  ))$result
  expect_equal(result$structuredContent$greeting, "Hello, Ada!")
})

# ---- tools/call ----

test_that("tools/call runs the tool and returns its result", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_rpc(
    "tools/call",
    list(name = "echo", arguments = list(x = "hi")),
    id = 21
  ))

  expect_equal(response$id, 21)
  expect_null(response$error)
  result <- response$result
  expect_equal(result$content[[1]], list(type = "text", text = "out: hi"))
  expect_equal(result$structuredContent, list(out = "hi"))
  expect_null(result$isError)
  expect_equal(result[["_meta"]][["shinymcp/view"]]$tool, "echo")
})

test_that("tools/call uses the tool's defaults when arguments are left out", {
  server <- McpServer$new(serving_app())
  result <- server$handle(serving_rpc("tools/call", list(name = "echo")))$result
  expect_equal(result$structuredContent, list(out = "default"))

  result <- server$handle(serving_rpc(
    "tools/call",
    list(name = "echo", arguments = json_object())
  ))$result
  expect_equal(result$structuredContent, list(out = "default"))
})

test_that("tools/call needs a tool name", {
  server <- McpServer$new(serving_app())
  for (params in list(
    NULL,
    list(),
    list(name = 5),
    list(name = ""),
    list(name = c("echo", "boom"))
  )) {
    response <- server$handle(serving_rpc("tools/call", params))
    expect_equal(response$error$code, -32602L)
    expect_equal(response$error$message, "Missing required parameter: name")
  }
})

test_that("tools/call reports unknown tools as invalid params", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_rpc("tools/call", list(name = "nope")))
  expect_equal(response$error$code, -32602L)
  expect_equal(response$error$message, "Unknown tool: nope")
  expect_equal(attr(response, "http_status"), 200L)
})

test_that("tools/call needs arguments to be an object", {
  server <- McpServer$new(serving_app())
  for (arguments in list("x", 5, TRUE)) {
    response <- server$handle(serving_rpc(
      "tools/call",
      list(name = "echo", arguments = arguments)
    ))
    expect_equal(response$error$code, -32602L)
    expect_equal(response$error$message, "Tool arguments must be an object.")
  }
})

test_that("a tool that fails returns an error result, not a protocol error", {
  server <- McpServer$new(serving_app())
  response <- server$handle(serving_rpc("tools/call", list(name = "boom")))
  expect_null(response$error)
  expect_null(attr(response, "http_status"))
  expect_true(response$result$isError)
  expect_equal(response$result$content[[1]]$type, "text")
  expect_match(response$result$content[[1]]$text, "^Error: .*kaboom")
})

test_that("unexpected errors while dispatching become internal errors", {
  BrokenApp <- R6::R6Class(
    "BrokenApp",
    inherit = McpApp,
    public = list(
      run_tool = function(name, arguments = list(), context = list()) {
        stop("the tool runner fell over")
      }
    )
  )
  broken <- BrokenApp$new(
    ui = htmltools::tags$div(),
    tools = list(serving_echo_tool()),
    name = "broken"
  )
  server <- McpServer$new(broken)

  response <- server$handle(serving_rpc(
    "tools/call",
    list(name = "echo"),
    id = 31
  ))
  expect_equal(response$id, 31)
  expect_null(response$result)
  expect_equal(response$error$code, -32603L)
  expect_equal(
    response$error$message,
    "Internal error: the tool runner fell over"
  )
  expect_equal(attr(response, "http_status"), 200L)

  modern <- server$handle(serving_modern("tools/call", list(name = "echo")))
  expect_equal(modern$error$code, -32603L)
})

test_that("a resource that fails to render becomes an internal error", {
  app <- serving_app(
    resources = list("ui://fx/data" = function() stop("no data today"))
  )
  server <- McpServer$new(app)
  response <- server$handle(serving_rpc(
    "resources/read",
    list(uri = "ui://fx/data")
  ))
  expect_equal(response$error$code, -32603L)
  expect_match(response$error$message, "^Internal error: .*no data today")
})

# ---- The request context tools see ----

test_that("tools see the transport's context through mcp_request()", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))
  context <- list(
    transport = "http",
    headers = list(host = "example.com", `x-test` = "1"),
    user = "ada",
    groups = c("eng", "ops")
  )
  server$handle(serving_rpc("tools/call", list(name = "context")), context)

  seen <- recorder$context
  expect_equal(recorder$calls, 1L)
  expect_equal(seen$caller, "model")
  expect_equal(seen$transport, "http")
  expect_equal(seen$headers, context$headers)
  expect_equal(seen$user, "ada")
  expect_equal(seen$groups, c("eng", "ops"))
  expect_equal(seen$era, "legacy")
  # No initialize: the lenient session defaults.
  expect_equal(seen$protocol_version, "2025-11-25")
  expect_true(seen$supports_ui)
  expect_null(seen$client)
  expect_equal(seen$skip_deps, character())
})

test_that("the transport defaults to in-process with no user", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))
  server$handle(serving_rpc("tools/call", list(name = "context")))
  expect_equal(recorder$context$transport, "in-process")
  expect_null(recorder$context$user)
  expect_null(recorder$context$groups)
  expect_null(recorder$context$headers)
})

test_that("calls marked by the app's own UI report caller app", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))
  call_as <- function(caller) {
    server$handle(serving_rpc(
      "tools/call",
      list(name = "context", `_meta` = list(`shinymcp/caller` = caller))
    ))
    recorder$context$caller
  }
  expect_equal(call_as("app"), "app")
  expect_equal(call_as("model"), "model")
  expect_equal(call_as("admin"), "model")
  expect_equal(call_as(list("app", "model")), "model")
})

test_that("view and dependency hints from the UI reach the call context", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))
  server$handle(serving_rpc(
    "tools/call",
    list(
      name = "context",
      `_meta` = list(
        `shinymcp/deps` = list("bootstrap", "htmlwidgets"),
        `shinymcp/view` = "view-1"
      )
    )
  ))
  expect_equal(recorder$context$skip_deps, c("bootstrap", "htmlwidgets"))
  expect_equal(recorder$context$view, "view-1")
})

test_that("legacy calls report the negotiated version and client", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))
  session <- initialize_session(
    server,
    ui = FALSE,
    version = "2025-03-26",
    client = list(name = "old-client", version = "0.1")
  )
  server$handle(
    serving_rpc("tools/call", list(name = "context"), id = 2),
    list(session = session)
  )

  expect_equal(recorder$context$era, "legacy")
  expect_equal(recorder$context$protocol_version, "2025-03-26")
  expect_equal(
    recorder$context$client,
    list(name = "old-client", version = "0.1")
  )
  expect_false(recorder$context$supports_ui)
})

test_that("modern calls report the request's version, client and UI support", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))

  server$handle(serving_modern(
    "tools/call",
    list(name = "context"),
    client = list(name = "new-client", version = "3.0")
  ))
  expect_equal(recorder$context$era, "modern")
  expect_equal(recorder$context$protocol_version, modern_version)
  expect_equal(
    recorder$context$client,
    list(name = "new-client", version = "3.0")
  )
  expect_true(recorder$context$supports_ui)

  server$handle(serving_modern(
    "tools/call",
    list(name = "context"),
    ui = FALSE
  ))
  expect_false(recorder$context$supports_ui)
})

test_that("the request context is gone once the call returns", {
  recorder <- serving_recorder()
  server <- McpServer$new(serving_app(tools = list(recorder$tool)))
  server$handle(
    serving_rpc("tools/call", list(name = "context")),
    list(transport = "http")
  )
  expect_equal(recorder$context$transport, "http")
  expect_null(mcp_request())
})

test_that("resource content functions see the request context", {
  app <- serving_app(
    resources = list(
      "ui://fx/whoami" = function() {
        paste(mcp_request()$transport, mcp_request()$user %||% "nobody")
      }
    )
  )
  server <- McpServer$new(app)
  response <- server$handle(
    serving_rpc("resources/read", list(uri = "ui://fx/whoami")),
    list(transport = "http", user = "ada")
  )
  expect_equal(response$result$contents[[1]]$text, "http ada")
  expect_null(mcp_request())
})

# ---- Resources ----

test_that("resources/list lists the app's page and its extra resources", {
  app <- serving_app(
    title = "Fixture",
    resources = list(
      "ui://fx/data" = list(
        content = "{}",
        mime_type = "application/json",
        description = "Data."
      )
    )
  )
  server <- McpServer$new(app)
  resources <- server$handle(serving_rpc("resources/list"))$result$resources

  expect_length(resources, 2)
  expect_equal(resources[[1]]$uri, "ui://fx")
  expect_equal(resources[[1]]$name, "fx")
  expect_equal(resources[[1]]$title, "Fixture")
  expect_equal(resources[[1]]$description, "MCP App: fx")
  expect_equal(resources[[1]]$mimeType, "text/html;profile=mcp-app")
  expect_null(resources[[1]][["_meta"]])
  expect_equal(resources[[2]]$uri, "ui://fx/data")
  expect_equal(resources[[2]]$mimeType, "application/json")
  expect_equal(resources[[2]]$description, "Data.")
})

test_that("a resource's _meta carries the app's CSP and border preference", {
  app <- serving_app(
    csp = list(connect_domains = "https://api.example.com"),
    prefers_border = FALSE
  )
  server <- McpServer$new(app)

  listed <- server$handle(serving_rpc("resources/list"))$result$resources[[1]]
  expect_equal(
    as.character(unlist(listed[["_meta"]][["ui"]]$csp$connectDomains)),
    "https://api.example.com"
  )
  expect_false(listed[["_meta"]][["ui"]]$prefersBorder)

  read <- server$handle(serving_rpc("resources/read", list(uri = "ui://fx")))
  expect_equal(
    as.character(unlist(
      read$result$contents[[1]][["_meta"]][["ui"]]$csp$connectDomains
    )),
    "https://api.example.com"
  )
  expect_match(
    serving_json_text(read),
    '"connectDomains":["https://api.example.com"]',
    fixed = TRUE
  )
})

test_that("resources/read returns the app page with its bridge configuration", {
  server <- McpServer$new(serving_app(title = "Fixture"))
  response <- server$handle(serving_rpc(
    "resources/read",
    list(uri = "ui://fx")
  ))
  contents <- response$result$contents

  expect_length(contents, 1)
  expect_equal(contents[[1]]$uri, "ui://fx")
  expect_equal(contents[[1]]$mimeType, "text/html;profile=mcp-app")
  html <- contents[[1]]$text
  expect_match(html, "^<!DOCTYPE html>")
  expect_match(html, "<title>Fixture</title>", fixed = TRUE)
  expect_match(
    html,
    '<script id="shinymcp-config" type="application/json">',
    fixed = TRUE
  )
  expect_match(html, '<script id="shinymcp-bridge">', fixed = TRUE)

  config <- regmatches(
    html,
    regexec(
      '<script id="shinymcp-config" type="application/json">(.*?)</script>',
      html,
      perl = TRUE
    )
  )[[1]][[2]]
  config <- jsonlite::fromJSON(config, simplifyVector = FALSE)
  expect_equal(config$app, "fx")
  expect_equal(
    vapply(config$tools, function(t) t$name, character(1)),
    c("echo", "boom", "refresh")
  )
})

test_that("resources/read serves extra resources", {
  app <- serving_app(
    resources = list(
      "ui://fx/data" = list(
        content = function() '{"a":1}',
        mime_type = "application/json"
      ),
      "ui://fx/readme" = "hello"
    )
  )
  server <- McpServer$new(app)

  data <- server$handle(serving_rpc(
    "resources/read",
    list(uri = "ui://fx/data")
  ))$result$contents[[1]]
  expect_equal(
    data,
    list(uri = "ui://fx/data", mimeType = "application/json", text = '{"a":1}')
  )
  readme <- server$handle(serving_rpc(
    "resources/read",
    list(uri = "ui://fx/readme")
  ))$result$contents[[1]]
  expect_equal(readme$mimeType, "text/plain")
  expect_equal(readme$text, "hello")
})

test_that("resources/read needs a uri", {
  server <- McpServer$new(serving_app())
  for (message in list(
    serving_rpc("resources/read", list()),
    serving_modern("resources/read")
  )) {
    response <- server$handle(message)
    expect_equal(response$error$code, -32602L)
    expect_equal(response$error$message, "Missing required parameter: uri")
  }
})

test_that("unknown resources are -32002 in the legacy era and -32602 in the modern era", {
  server <- McpServer$new(serving_app())

  legacy <- server$handle(serving_rpc(
    "resources/read",
    list(uri = "ui://nope")
  ))
  expect_equal(legacy$error$code, -32002L)
  expect_equal(legacy$error$message, "Resource not found: ui://nope")
  expect_equal(legacy$error$data, list(uri = "ui://nope"))

  modern <- server$handle(serving_modern(
    "resources/read",
    list(uri = "ui://nope")
  ))
  expect_equal(modern$error$code, -32602L)
  expect_equal(modern$error$data, list(uri = "ui://nope"))
})

# ---- Several apps on one server ----

test_that("a server with several apps routes each request to the app that owns it", {
  alpha <- serving_app(
    "alpha",
    tools = list(serving_echo_tool("alpha_echo", reply = "from alpha")),
    title = "Alpha"
  )
  beta <- serving_app(
    "beta",
    tools = list(serving_echo_tool("beta_echo", reply = "from beta")),
    title = "Beta",
    resources = list("ui://beta/data" = "beta data")
  )
  server <- McpServer$new(list(alpha, beta))

  tools <- server$handle(serving_rpc("tools/list"))$result$tools
  expect_equal(
    vapply(tools, function(t) t$name, character(1)),
    c("alpha_echo", "beta_echo")
  )
  expect_equal(tools[[1]][["_meta"]][["ui"]]$resourceUri, "ui://alpha")
  expect_equal(tools[[2]][["_meta"]][["ui"]]$resourceUri, "ui://beta")

  call <- function(name) {
    server$handle(serving_rpc(
      "tools/call",
      list(name = name)
    ))$result$structuredContent$out
  }
  expect_equal(call("alpha_echo"), "from alpha")
  expect_equal(call("beta_echo"), "from beta")

  resources <- server$handle(serving_rpc("resources/list"))$result$resources
  expect_equal(
    vapply(resources, function(r) r$uri, character(1)),
    c("ui://alpha", "ui://beta", "ui://beta/data")
  )

  read <- function(uri) {
    server$handle(serving_rpc(
      "resources/read",
      list(uri = uri)
    ))$result$contents[[1]]$text
  }
  expect_match(read("ui://alpha"), "<title>Alpha</title>", fixed = TRUE)
  expect_match(read("ui://beta"), "<title>Beta</title>", fixed = TRUE)
  expect_equal(read("ui://beta/data"), "beta data")

  expect_equal(server$tool_app("beta_echo")$name, "beta")
  expect_null(server$tool_app("nope"))
  expect_null(server$tool_app(NULL))
  expect_equal(server$resource_app("ui://alpha")$name, "alpha")
  expect_equal(server$resource_app("ui://beta/data")$name, "beta")
  expect_null(server$resource_app("ui://gamma"))
})
