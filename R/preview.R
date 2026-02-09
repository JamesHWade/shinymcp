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
#' srv <- preview(app)
#'
#' # Stop when done
#' srv$stop()
#' }
#' @export
preview <- function(app, port = NULL, launch = TRUE) {
  rlang::check_installed("httpuv", reason = "to preview MCP Apps in a browser")

  app <- as_mcp_app(app)

  port <- port %||% httpuv::randomPort()
  host <- "127.0.0.1"

  # Pre-render the host HTML with the app name baked in

  host_html <- preview_host_html(app$name)
  app_html <- app$html_resource()

  server <- httpuv::startServer(host, port, list(
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
  ))

  url <- sprintf("http://%s:%d", host, port)
  cli::cli_inform(c(
    "i" = "Preview running at {.url {url}}",
    "i" = "Press {.kbd Ctrl+C} or call {.code $stop()} to stop."
  ))

  if (launch) {
    utils::browseURL(url)
  }

  result <- list(
    url = url,
    stop = function() {
      httpuv::stopServer(server)
      cli::cli_inform("Preview server stopped.")
    }
  )

  invisible(result)
}


# ---- Internal helpers -------------------------------------------------------

#' Coerce input to an McpApp
#'
#' If `x` is already an McpApp, return it. If it's a path, source the app.R
#' file and look for an McpApp in the resulting environment.
#'
#' @param x An McpApp object or character path.
#' @return An McpApp object.
#' @noRd
as_mcp_app <- function(x) {
  if (inherits(x, "McpApp")) {
    return(x)
  }

  if (is.character(x) && length(x) == 1) {
    # Try to source an app.R that creates an McpApp
    app_file <- if (file.info(x)$isdir) {
      file.path(x, "app.R")
    } else {
      x
    }

    if (!file.exists(app_file)) {
      cli::cli_abort("App file not found: {.file {app_file}}")
    }

    env <- new.env(parent = globalenv())
    source(app_file, local = env)

    # Find the McpApp object in the sourced environment
    for (nm in ls(env)) {
      obj <- get(nm, envir = env)
      if (inherits(obj, "McpApp")) {
        return(obj)
      }
    }

    cli::cli_abort(
      "No {.cls McpApp} object found in {.file {app_file}}."
    )
  }

  cli::cli_abort(
    "{.arg app} must be an {.cls McpApp} object or a path to an app directory."
  )
}


#' Read and populate the host HTML template
#'
#' @param app_name App name to embed in the template.
#' @return Character string of complete HTML.
#' @noRd
preview_host_html <- function(app_name) {
  template_path <- system.file(
    "preview", "host.html",
    package = "shinymcp",
    mustWork = TRUE
  )
  template <- paste(readLines(template_path, warn = FALSE), collapse = "\n")
  gsub("{{APP_NAME}}", htmltools::htmlEscape(app_name), template, fixed = TRUE)
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


#' Format an R tool result into the MCP tool-result shape
#'
#' Mirrors the logic in `handle_tools_call()` from serve.R.
#'
#' @param result The raw result from `McpApp$call_tool()`.
#' @return A list with `content` and optionally `structuredContent`.
#' @noRd
format_tool_result <- function(result) {
  if (is.list(result) && !is.null(names(result))) {
    text_parts <- vapply(result, function(x) {
      if (is.character(x) && nchar(x) < 10000) x else ""
    }, character(1))
    text_summary <- paste(text_parts[nzchar(text_parts)], collapse = "\n\n")

    list(
      content = list(list(type = "text", text = text_summary)),
      structuredContent = result
    )
  } else {
    list(
      content = list(list(type = "text", text = as.character(result)))
    )
  }
}
