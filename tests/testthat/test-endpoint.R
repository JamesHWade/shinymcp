# mcp_endpoint(): MCP inside a Shiny app (R/endpoint.R). The endpoint's
# httpHandler is called with fake Rook requests, the way Shiny calls it.

no_platform <- function(env = parent.frame()) {
  withr::local_envvar(
    RSTUDIO_PRODUCT = NA,
    CONNECT_SERVER = NA,
    R_CONFIG_ACTIVE = NA,
    .local_envir = env
  )
}

live_shiny_app <- function() {
  shiny::shinyApp(
    ui = shiny::fluidPage(
      shiny::selectInput("cyl", "Cylinders", c("4", "6", "8")),
      shiny::textOutput("count")
    ),
    server = function(input, output, session) {
      output$count <- shiny::renderText({
        paste(sum(mtcars$cyl == as.numeric(input$cyl)), "cars")
      })
    }
  )
}

get_page <- function(endpoint, path = "/") {
  endpoint$httpHandler(serving_request(method = "GET", path = path))
}

post_mcp <- function(endpoint, message, path = "/mcp", headers = list()) {
  endpoint$httpHandler(serving_request(message, path = path, headers = headers))
}

# ---- Apps ----

test_that("mcp_endpoint() returns a Shiny app that carries its MCP server", {
  skip_if_not_installed("shiny")
  app <- serving_app()
  endpoint <- mcp_endpoint(app)
  expect_s3_class(endpoint, "shiny.appobj")
  expect_true(is.function(endpoint$httpHandler))
  expect_s3_class(endpoint$mcpServer, "McpServer")
  expect_identical(endpoint$mcpServer$apps[[1]], app)
})

test_that("the endpoint answers MCP at /mcp", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(serving_app())
  response <- post_mcp(endpoint, serving_initialize(version = "2025-06-18"))

  expect_s3_class(response, "httpResponse")
  expect_equal(response$status, 200L)
  expect_equal(response$content_type, "application/json")
  expect_match(response$headers[["Mcp-Session-Id"]], "^mcp-")
  expect_null(response$headers[["Content-Type"]])
  expect_equal(serving_body(response)$result$protocolVersion, "2025-06-18")

  id <- response$headers[["Mcp-Session-Id"]]
  call <- post_mcp(
    endpoint,
    serving_rpc(
      "tools/call",
      list(name = "echo", arguments = list(x = "via shiny")),
      id = 2
    ),
    headers = list(`Mcp-Session-Id` = id)
  )
  expect_equal(serving_body(call)$result$structuredContent$out, "via shiny")
})

test_that("the endpoint serves modern requests", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(serving_app())
  message <- serving_modern("server/discover")
  response <- post_mcp(
    endpoint,
    message,
    headers = serving_modern_headers(message)
  )
  expect_equal(response$status, 200L)
  expect_equal(serving_body(response)$result$resultType, "complete")

  unknown <- serving_modern("tools/destroy")
  response <- post_mcp(
    endpoint,
    unknown,
    headers = serving_modern_headers(unknown)
  )
  expect_equal(response$status, 404L)
  expect_equal(response$content_type, "application/json")
})

test_that("empty MCP replies keep their status and headers", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(serving_app())
  note <- post_mcp(
    endpoint,
    serving_rpc("notifications/initialized", id = NULL)
  )
  expect_equal(note$status, 202L)
  expect_equal(note$content, "")

  preflight <- endpoint$httpHandler(serving_request(
    method = "OPTIONS",
    headers = list(Origin = "http://localhost:3000", Host = "localhost:3000")
  ))
  expect_equal(preflight$status, 200L)
  expect_equal(
    preflight$headers[["Access-Control-Allow-Origin"]],
    "http://localhost:3000"
  )
  expect_equal(
    preflight$headers[["Access-Control-Allow-Methods"]],
    "POST, DELETE, OPTIONS"
  )
})

test_that("browsers get the preview page at /", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(serving_app(title = "Echo <Explorer>"))
  response <- get_page(endpoint)

  expect_equal(response$status, 200L)
  expect_equal(response$content_type, "text/html; charset=utf-8")
  page <- response$content
  expect_match(page, "<title>Echo &lt;Explorer&gt;", fixed = TRUE)
  expect_match(page, "window.shinymcpHost", fixed = TRUE)
  config <- serving_preview_config(page)
  expect_equal(config$title, "Echo <Explorer>")
  expect_equal(config$endpoint, "mcp")
  expect_equal(config$entryTool, "echo")
  expect_identical(page, preview_page(endpoint$mcpServer, "echo"))
})

test_that("preview = FALSE answers browsers with a pointer to the endpoint", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(serving_app(), path = "/api/mcp", preview = FALSE)
  response <- get_page(endpoint)
  expect_equal(response$status, 404L)
  expect_equal(response$content_type, "text/plain")
  expect_equal(response$content, "This app serves MCP at /api/mcp.")
})

test_that("the endpoint can live at another path", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(serving_app(), path = "/api/mcp")
  expect_equal(
    post_mcp(endpoint, serving_rpc("ping"), path = "/api/mcp")$status,
    200L
  )
  expect_equal(
    post_mcp(endpoint, serving_rpc("ping"), path = "/api/mcp/")$status,
    200L
  )
  # Other paths go to the Shiny app, which only serves GET /.
  expect_null(post_mcp(endpoint, serving_rpc("ping"), path = "/mcp"))
  expect_null(get_page(endpoint, "/elsewhere"))
})

test_that("an endpoint can serve several apps", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(list(
    serving_app("alpha", tools = list(serving_echo_tool("alpha_echo"))),
    serving_app("beta", tools = list(serving_echo_tool("beta_echo")))
  ))
  tools <- serving_body(post_mcp(
    endpoint,
    serving_rpc("tools/list")
  ))$result$tools
  expect_equal(
    vapply(tools, function(t) t$name, character(1)),
    c("alpha_echo", "beta_echo")
  )

  config <- serving_preview_config(get_page(endpoint)$content)
  expect_equal(config$title, "shinymcp")
  expect_equal(config$entryTool, "alpha_echo")
})

test_that("mcp_endpoint() rejects things that aren't apps", {
  skip_if_not_installed("shiny")
  expect_error(mcp_endpoint(42), class = "shinymcp_error_validation")
  expect_error(mcp_endpoint(list()), class = "shinymcp_error_validation")
})

test_that("errors inside the MCP handler become a 500 JSON-RPC error", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(serving_app())
  req <- serving_request(path = "/mcp")
  req[["rook.input"]] <- list(read = function(...) stop("disk on fire"))

  response <- endpoint$httpHandler(req)
  expect_equal(response$status, 500L)
  expect_equal(response$content_type, "application/json")
  body <- serving_body(response)
  expect_null(body$id)
  expect_equal(body$error$code, -32603L)
  expect_match(body$error$message, "disk on fire")
})

test_that("shiny::runApp() can serve an McpApp through as.shiny.appobj()", {
  skip_if_not_installed("shiny")
  app <- serving_app()
  endpoint <- shiny::as.shiny.appobj(app)
  expect_s3_class(endpoint, "shiny.appobj")
  expect_identical(endpoint$mcpServer$apps[[1]], app)
  expect_equal(post_mcp(endpoint, serving_rpc("ping"))$status, 200L)
  expect_equal(get_page(endpoint)$status, 200L)
})

# ---- Shiny apps ----

test_that("a Shiny app keeps serving browsers and serves MCP at /mcp", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(
    live_shiny_app(),
    name = "cars",
    description = "Count cars by cylinders."
  )
  expect_equal(endpoint$mcpServer$apps[[1]]$name, "cars")
  expect_match(
    endpoint$mcpServer$instructions,
    "Count cars by cylinders.",
    fixed = TRUE
  )

  # Browsers get the Shiny app's own page.
  page <- get_page(endpoint)
  expect_equal(page$status, 200L)
  expect_match(page$content, 'id="cyl"', fixed = TRUE)
  expect_false(grepl("preview-config", page$content, fixed = TRUE))

  # Paths the Shiny app doesn't serve are left to it.
  expect_null(get_page(endpoint, "/elsewhere"))
  expect_null(post_mcp(endpoint, serving_rpc("ping"), path = "/"))

  tools <- serving_body(post_mcp(
    endpoint,
    serving_rpc("tools/list")
  ))$result$tools
  expect_equal(
    vapply(tools, function(t) t$name, character(1)),
    c("cars", "cars_view")
  )
})

test_that("MCP clients run the Shiny app's server function through the endpoint", {
  skip_if_not_installed("shiny")
  endpoint <- mcp_endpoint(live_shiny_app(), name = "cars")
  message <- serving_rpc(
    "tools/call",
    list(name = "cars", arguments = list(cyl = "6"))
  )
  response <- post_mcp(endpoint, message)
  expect_equal(response$status, 200L)
  result <- serving_body(response)$result
  expect_null(result$isError)
  expect_equal(result$structuredContent$outputs$count, "7 cars")
  endpoint$mcpServer$apps[[1]]$runtime()$close_all()
})

test_that("a shinyAppDir() app runs in its directory, and the process stays put", {
  skip_if_not_installed("shiny")
  local_app_dir_side_effects()
  # Its global.R defines a value in the global environment, as Shiny's does.
  withr::defer(suppressWarnings(rm("greeting", envir = globalenv())))
  dir <- withr::local_tempdir()
  writeLines("greeting <- 'Hello'", file.path(dir, "global.R"))
  writeLines("from its directory", file.path(dir, "note.txt"))
  writeLines(
    "shiny::fluidPage(shiny::textOutput('note'))",
    file.path(dir, "ui.R")
  )
  writeLines(
    paste(
      "function(input, output, session) output$note <-",
      "shiny::renderText(paste(greeting, readLines('note.txt')))"
    ),
    file.path(dir, "server.R")
  )
  here <- getwd()
  endpoint <- suppressPackageStartupMessages(
    mcp_endpoint(shiny::shinyAppDir(dir), name = "notes")
  )
  expect_identical(getwd(), here)
  app <- endpoint$mcpServer$apps[[1]]
  res <- app$run_tool("notes", list())
  expect_identical(
    res$structuredContent$outputs$note,
    "Hello from its directory"
  )
  expect_identical(getwd(), here)

  # runApp() changes into the app's directory for browsers, and back when
  # the app stops.
  endpoint$onStart()
  expect_identical(normalizePath(getwd()), normalizePath(dir))
  endpoint$onStop()
  expect_identical(getwd(), here)
})

test_that("a Shiny app can have apps built from tools next to it", {
  skip_if_not_installed("shiny")
  started <- FALSE
  shiny_app <- live_shiny_app()
  shiny_app$onStart <- function() started <<- TRUE
  endpoint <- mcp_endpoint(shiny_app, apps = serving_app(name = "fx"))

  # The Shiny app isn't served live, or started early.
  expect_false(started)
  expect_equal(
    vapply(endpoint$mcpServer$apps, function(a) a$name, character(1)),
    "fx"
  )
  expect_true(is.function(endpoint$onStart))

  page <- get_page(endpoint)
  expect_match(page$content, 'id="cyl"', fixed = TRUE)
  tools <- serving_body(post_mcp(
    endpoint,
    serving_rpc("tools/list")
  ))$result$tools
  expect_equal(
    vapply(tools, function(t) t$name, character(1)),
    c("echo", "boom", "refresh")
  )
  result <- serving_body(post_mcp(
    endpoint,
    serving_rpc("tools/call", list(name = "echo", arguments = list(x = "hi")))
  ))$result
  expect_equal(result$structuredContent, list(out = "hi"))

  two <- mcp_endpoint(
    live_shiny_app(),
    apps = list(
      serving_app(name = "a"),
      serving_app(name = "b", tools = list(serving_echo_tool("echo2")))
    )
  )
  expect_length(two$mcpServer$apps, 2)
})

test_that("apps go with a Shiny app, and live-serving arguments don't", {
  skip_if_not_installed("shiny")
  expect_error(
    mcp_endpoint(serving_app(), apps = serving_app(name = "other")),
    "goes with a Shiny app",
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_endpoint(live_shiny_app(), apps = serving_app(), name = "cars"),
    "is for serving a Shiny app live",
    class = "shinymcp_error_validation"
  )
})

# ---- Hosting platforms ----

test_that("on_hosted_platform() recognizes Posit Connect and shinyapps.io", {
  skip_if_not_installed("withr")
  no_platform()
  expect_false(on_hosted_platform())

  withr::with_envvar(
    c(RSTUDIO_PRODUCT = "CONNECT"),
    expect_true(on_hosted_platform())
  )
  withr::with_envvar(
    c(RSTUDIO_PRODUCT = "WORKBENCH"),
    expect_false(on_hosted_platform())
  )
  # People set CONNECT_SERVER on their own machines to deploy.
  withr::with_envvar(
    c(CONNECT_SERVER = "https://connect.example.com/"),
    expect_false(on_hosted_platform())
  )
  withr::with_envvar(c(CONNECT_SERVER = ""), expect_false(on_hosted_platform()))
  withr::with_envvar(
    c(R_CONFIG_ACTIVE = "shinyapps"),
    expect_true(on_hosted_platform())
  )
  withr::with_envvar(
    c(R_CONFIG_ACTIVE = "default"),
    expect_false(on_hosted_platform())
  )
})

test_that("loopback origins are allowed locally but refused on a hosting platform", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("withr")
  no_platform()
  local_endpoint <- mcp_endpoint(serving_app())
  expect_equal(
    post_mcp(
      local_endpoint,
      serving_rpc("ping"),
      headers = list(Origin = "http://localhost:3000", Host = "127.0.0.1:3838")
    )$status,
    200L
  )

  from_localhost <- list(
    Origin = "http://localhost:3000",
    Host = "connect.example.com"
  )

  withr::local_envvar(RSTUDIO_PRODUCT = "CONNECT")
  hosted_endpoint <- mcp_endpoint(serving_app())
  response <- post_mcp(
    hosted_endpoint,
    serving_rpc("ping"),
    headers = from_localhost
  )
  expect_equal(response$status, 403L)
  expect_equal(
    serving_body(response)$error$message,
    "Forbidden origin: http://localhost:3000"
  )

  # The content's own URL on Connect is still its own origin.
  own <- list(
    Origin = "https://connect.example.com",
    Host = "127.0.0.1:34567",
    `RStudio-Connect-App-Base-Url` = "https://connect.example.com/content/0a1b2c/"
  )
  expect_equal(
    post_mcp(hosted_endpoint, serving_rpc("ping"), headers = own)$status,
    200L
  )
})

test_that("allowed_origins reaches the endpoint's origin check", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("withr")
  withr::local_envvar(RSTUDIO_PRODUCT = "CONNECT")
  headers <- list(
    Origin = "https://chat.example.com",
    Host = "connect.example.com"
  )

  expect_equal(
    post_mcp(
      mcp_endpoint(serving_app()),
      serving_rpc("ping"),
      headers = headers
    )$status,
    403L
  )
  allowed <- mcp_endpoint(
    serving_app(),
    allowed_origins = "https://chat.example.com"
  )
  response <- post_mcp(allowed, serving_rpc("ping"), headers = headers)
  expect_equal(response$status, 200L)
  expect_equal(
    response$headers[["Access-Control-Allow-Origin"]],
    "https://chat.example.com"
  )
})

# ---- rook_to_shiny_response() ----

test_that("rook_to_shiny_response() moves Content-Type into the content type", {
  skip_if_not_installed("shiny")
  response <- rook_to_shiny_response(list(
    status = 201L,
    headers = list(
      `Content-Type` = "application/json",
      `Mcp-Session-Id` = "abc"
    ),
    body = "{}"
  ))
  expect_s3_class(response, "httpResponse")
  expect_equal(response$status, 201L)
  expect_equal(response$content_type, "application/json")
  expect_equal(response$content, "{}")
  expect_equal(response$headers[["Mcp-Session-Id"]], "abc")
  expect_null(response$headers[["Content-Type"]])
})

test_that("rook_to_shiny_response() defaults to an empty text body", {
  skip_if_not_installed("shiny")
  response <- rook_to_shiny_response(list(status = 202L))
  expect_equal(response$status, 202L)
  expect_equal(response$content_type, "text/plain")
  expect_equal(response$content, "")
})
