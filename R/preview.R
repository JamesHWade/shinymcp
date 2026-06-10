# Local browser preview for MCP Apps

#' Preview an MCP App in a web browser
#'
#' Starts a local HTTP server and opens the MCP App in a browser. A lightweight
#' host page emulates the MCP Apps postMessage protocol so that tools are fully
#' functional — inputs trigger tool calls, and outputs update in real time, just
#' like they would inside Claude Desktop.
#'
#' @param app An [McpApp] object, or a path to a directory containing an MCP
#'   App `app.R` (which will be [source()]d to obtain the app object).
#' @param port Port for the local server. `NULL` (the default) picks a random
#'   available port.
#' @param launch Whether to open the browser automatically (default `TRUE`).
#' @return Invisibly, a list with `url` (the preview URL) and `stop()` (a
#'   function to shut down the server).
#'
#' @examples
#' \dontrun{
#' app <- mcp_app(
#'   ui = htmltools::tags$div(
#'     mcp_text_input("name", "Your name"),
#'     mcp_text("greeting")
#'   ),
#'   tools = list(
#'     list(
#'       name = "greet",
#'       fun = function(name = "world") {
#'         list(greeting = paste0("Hello, ", name, "!"))
#'       }
#'     )
#'   )
#' )
#'
#' # Opens in browser with working inputs/outputs
#' srv <- preview_app(app)
#'
#' # Stop when done
#' srv$stop()
#' }
#' @export
preview_app <- function(app, port = NULL, launch = TRUE) {
  rlang::check_installed("httpuv", reason = "to preview MCP Apps in a browser")

  app <- coerce_preview_mcp_app(app)

  host <- "127.0.0.1"

  # Pre-render the host HTML with the app name baked in
  host_html <- preview_host_html(app$name)
  app_html <- app$html_resource()

  server_info <- preview_start_server(
    host = host,
    port = port,
    app = list(
      call = function(req) {
        tryCatch(
          preview_route(req, app, host_html, app_html),
          error = function(e) {
            list(
              status = 500L,
              headers = list(`Content-Type` = "text/plain"),
              body = paste("Internal server error:", conditionMessage(e))
            )
          }
        )
      }
    )
  )
  server <- server_info$server
  port <- server_info$port

  stop_server <- function() {
    httpuv::stopServer(server)
    cli::cli_inform("Preview server stopped.")
  }

  url <- sprintf("http://%s:%d", host, port)
  cli::cli_inform(c(
    "i" = "Preview running at {.url {url}}",
    "i" = "Press {.kbd Ctrl+C} or call {.code $stop()} to stop."
  ))

  if (launch) {
    tryCatch(
      utils::browseURL(url),
      error = function(e) {
        cli::cli_warn("Could not open browser: {e$message}")
      }
    )
  }

  result <- list(url = url, stop = stop_server)
  invisible(result)
}

#' Start a preview server on an explicit or discovered local port
#'
#' @param host Host interface.
#' @param port Optional explicit port.
#' @param app httpuv app object.
#' @return A list with `server` and `port`.
#' @noRd
coerce_preview_mcp_app <- function(x) {
  as_mcp_app(x)
}

#' @noRd
preview_start_server <- function(host, port = NULL, app) {
  candidates <- if (!is.null(port)) {
    port
  } else {
    unique(c(
      tryCatch(httpuv::randomPort(), error = function(...) integer()),
      sample(3000:9000, 25)
    ))
  }

  last_error <- NULL
  for (candidate in candidates) {
    server <- tryCatch(
      httpuv::startServer(host, candidate, app),
      error = function(e) {
        last_error <<- e
        NULL
      }
    )
    if (!is.null(server)) {
      return(list(server = server, port = candidate))
    }
  }

  stop(last_error %||% simpleError("Could not bind a preview server port."))
}


#' Read and populate the host HTML template
#'
#' @param app_name App name to embed in the template.
#' @return Character string of complete HTML.
#' @noRd
preview_host_html <- function(app_name) {
  template_path <- system.file(
    "preview",
    "host.html",
    package = "shinymcp",
    mustWork = TRUE
  )
  template <- paste(readLines(template_path, warn = FALSE), collapse = "\n")
  host_js <- paste(
    readLines(system_file("js", "shinymcp-host.js"), warn = FALSE),
    collapse = "\n"
  )

  rendered <- gsub(
    "{{APP_NAME}}",
    htmltools::htmlEscape(app_name),
    template,
    fixed = TRUE
  )
  gsub("{{HOST_JS}}", host_js, rendered, fixed = TRUE)
}


#' Route an HTTP request to the right handler
#'
#' @param req A Rook request object.
#' @param app The McpApp.
#' @param host_html Pre-rendered host page HTML.
#' @param app_html Pre-rendered app HTML.
#' @return A Rook response list.
#' @noRd
preview_route <- function(req, app, host_html, app_html) {
  path <- req$PATH_INFO

  if (path == "/" || path == "") {
    return(list(
      status = 200L,
      headers = list(`Content-Type` = "text/html; charset=utf-8"),
      body = host_html
    ))
  }

  if (path == "/app.html") {
    return(list(
      status = 200L,
      headers = list(`Content-Type` = "text/html; charset=utf-8"),
      body = app_html
    ))
  }

  if (path == "/tool" && identical(req$REQUEST_METHOD, "POST")) {
    return(preview_handle_tool(req, app))
  }

  if (path == "/resource" && identical(req$REQUEST_METHOD, "POST")) {
    return(preview_handle_resource(req, app, app_html))
  }

  list(
    status = 404L,
    headers = list(`Content-Type` = "text/plain"),
    body = "Not found"
  )
}


#' Handle a tool call from the preview host page
#'
#' @param req A Rook request object (POST to /tool).
#' @param app The McpApp.
#' @return A Rook response with JSON body.
#' @noRd
preview_handle_tool <- function(req, app) {
  body <- rawToChar(req$rook.input$read())
  params <- from_json(body)

  tool_name <- params$name
  arguments <- params$arguments %||% list()

  result <- tryCatch(
    {
      raw_result <- app$call_tool(tool_name, arguments)
      format_tool_result(raw_result)
    },
    error = function(e) {
      list(
        content = list(list(type = "text", text = paste("Error:", e$message))),
        isError = TRUE
      )
    }
  )

  list(
    status = 200L,
    headers = list(`Content-Type` = "application/json"),
    body = to_json(result)
  )
}


#' Handle a resources/read from the preview host page
#'
#' @param req A Rook request object (POST to /resource).
#' @param app The McpApp.
#' @param app_html Pre-rendered app HTML for the app's own ui:// resource.
#' @return A Rook response with a JSON `contents` payload, or an `error`.
#' @noRd
preview_handle_resource <- function(req, app, app_html) {
  body <- rawToChar(req$rook.input$read())
  params <- tryCatch(from_json(body), error = function(e) NULL)
  uri <- params$uri

  if (is.null(uri)) {
    return(list(
      status = 400L,
      headers = list(`Content-Type` = "application/json"),
      body = to_json(list(error = "Missing required parameter: uri"))
    ))
  }

  result <- tryCatch(
    {
      if (identical(uri, app$resource_uri())) {
        list(
          contents = list(compact_list(list(
            uri = uri,
            mimeType = SHINYMCP_UI_MIME_TYPE,
            text = app_html,
            `_meta` = app$resource_meta()
          )))
        )
      } else {
        list(contents = list(app$read_extra_resource(uri)))
      }
    },
    error = function(e) {
      list(error = conditionMessage(e))
    }
  )

  status <- if (is.null(result$error)) 200L else 404L
  list(
    status = status,
    headers = list(`Content-Type` = "application/json"),
    body = to_json(result)
  )
}
