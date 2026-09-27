# preview_app(): a local MCP Apps host in the browser

#' Preview an MCP App in a browser
#'
#' @description
#' `preview_app()` serves the app over MCP on a local port and opens a page
#' that hosts it the way a chat client does: the app runs in a sandboxed
#' iframe under the same Content Security Policy a client would apply, and
#' every message goes through the app's real MCP endpoint. Alongside the app
#' the page shows what the model would see (the text and structured content
#' of each tool result), the context the app publishes for the model, and a
#' log of the protocol messages.
#'
#' When the page opens it calls the app's first tool (or `tool`) with
#' `arguments`, as a model would, and shows the app with the result. Use
#' the arguments box on the page to call it again with other values.
#'
#' @param app An [McpApp], a list of apps, a Shiny app, or a path to one.
#' @param arguments Named list of arguments for the first call.
#' @param tool Name of the tool to call first. Defaults to the first tool
#'   the model can call.
#' @param port Port to listen on. `NULL` picks a free one.
#' @param launch Whether to open the page in a browser.
#' @return Invisibly, a list with the preview's `url` and a `stop()`
#'   function.
#' @family serving
#' @export
#' @examples
#' \dontrun{
#' preview <- preview_app(app, arguments = list(species = "Gentoo"))
#' preview$stop()
#' }
preview_app <- function(app, arguments = NULL, tool = NULL, port = NULL, launch = interactive()) {
  rlang::check_installed("httpuv", reason = "to preview MCP Apps in a browser.")
  server <- McpServer$new(app)
  for (a in server$apps) {
    warn_host_only_trigger(a, "preview_app()")
  }
  host <- "127.0.0.1"
  handler <- mcp_http_handler(server, path = "/mcp", local = TRUE)
  entry <- tool %||% unlist(lapply(server$apps, default_entry_tool))[1]
  page <- preview_page(server, entry, arguments)

  started <- start_local_server(host, port, list(
    call = function(req) {
      tryCatch(
        {
          path <- req$PATH_INFO %||% "/"
          if (path %in% c("/", "/index.html")) {
            list(
              status = 200L,
              headers = list(`Content-Type` = "text/html; charset=utf-8", `Cache-Control` = "no-store"),
              body = page
            )
          } else {
            handler(req) %||%
              list(status = 404L, headers = list(`Content-Type` = "text/plain"), body = "Not found")
          }
        },
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

  url <- sprintf("http://%s:%d/", host, started$port)
  cli::cli_inform(
    c("i" = "Previewing at {.url {url}}", " " = "Call {.code $stop()} on the result to stop."),
    class = "shinymcp_message"
  )
  if (isTRUE(launch)) {
    utils::browseURL(url)
  }
  invisible(list(
    url = url,
    port = started$port,
    stop = function() {
      httpuv::stopServer(started$server)
      invisible(NULL)
    }
  ))
}

#' The preview host page
#' @noRd
preview_page <- function(server, entry = NULL, arguments = NULL) {
  config <- list(
    title = if (length(server$apps) == 1) server$apps[[1]]$title %||% server$apps[[1]]$name else "shinymcp",
    endpoint = "mcp",
    entryTool = entry,
    arguments = arguments %||% json_object(),
    protocolVersion = SHINYMCP_MODERN_VERSIONS[[1]],
    appsProtocolVersion = SHINYMCP_APPS_PROTOCOL_VERSION,
    version = as.character(utils::packageVersion("shinymcp"))
  )
  fill_template(read_package_file("preview", "host.html"), list(
    TITLE = htmltools::htmlEscape(config$title),
    HOST_JS = escape_inline_close(read_package_file("js", "shinymcp-host.js"), "script"),
    CONFIG = json_for_script(config)
  ))
}

#' Replace `{{KEY}}` placeholders in one pass
#'
#' Text inserted for one placeholder is never scanned for others.
#' @noRd
fill_template <- function(template, values) {
  matches <- gregexpr("\\{\\{[A-Z_]+\\}\\}", template, perl = TRUE)
  found <- regmatches(template, matches)[[1]]
  regmatches(template, matches) <- list(vapply(
    found,
    function(p) values[[substr(p, 3, nchar(p) - 2)]] %||% p,
    character(1),
    USE.NAMES = FALSE
  ))
  template
}

#' Start an httpuv server on a given or free port
#' @noRd
start_local_server <- function(host, port, app) {
  candidates <- if (!is.null(port)) {
    port
  } else {
    unique(c(
      tryCatch(httpuv::randomPort(), error = function(e) integer()),
      sample(3000:9000, 20)
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
  shinymcp_abort(
    c("Couldn't start a local server.", "x" = conditionMessage(last_error %||% simpleError("no free port")))
  )
}
