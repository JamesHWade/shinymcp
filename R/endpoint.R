# mcp_endpoint(): an MCP endpoint inside a Shiny app, for Posit Connect

#' Add an MCP endpoint to a Shiny app
#'
#' @description
#' `mcp_endpoint()` returns a Shiny app that answers MCP requests at `path`
#' (default `/mcp`), so an MCP App can be deployed anywhere Shiny apps run:
#' Posit Connect, Shiny Server, or `shiny::runApp()` on your own machine.
#' Deploy it like any Shiny app, then point MCP clients at
#' `https://<server>/<app-path>/mcp`.
#'
#' * Given an [McpApp] (or a list of them), browsers visiting the app get
#'   the same preview page as [preview_app()].
#' * Given a Shiny app and `apps`, browsers get the Shiny app and MCP
#'   clients get the apps. One deployment serves people and models; the
#'   apps can share the Shiny app's UI and functions.
#' * Given a Shiny app alone, browsers still get the Shiny app, and the
#'   endpoint serves it, live, to MCP clients through [as_mcp_app()].
#'
#' Clients that speak the stateless MCP revision (2026-07-28) can reach
#' any of several R processes behind a load balancer. Live Shiny apps keep
#' each view's session in the process that opened it; see [as_mcp_app()]
#' for what happens when a request lands elsewhere.
#'
#' On Posit Connect the endpoint sits behind the content's access controls,
#' and [mcp_request()] reports the signed-in user.
#'
#' @inheritSection as_mcp_app Shiny's own MCP support
#' @param x An [McpApp], a list of apps, or a Shiny app.
#' @param apps When `x` is a Shiny app, the apps to serve to MCP clients
#'   next to it: an [McpApp] or a list of them. Without `apps`, the Shiny
#'   app itself is served, live.
#' @param path Endpoint path.
#' @param allowed_origins Browser origins, besides the app's own, allowed to
#'   call the endpoint. See [serve()].
#' @param allowed_hosts Host names the app is reached at, when it runs
#'   somewhere other than Posit Connect, shinyapps.io, or Shiny Server (for
#'   example in a container behind your own proxy). Elsewhere, requests for
#'   host names other than `localhost` or an IP address are refused; see
#'   [serve()].
#' @param preview For apps, whether browsers get a preview page at `/`.
#' @param ... Passed to [as_mcp_app()] when `x` is a Shiny app served live.
#' @return A Shiny app object.
#' @family serving
#' @export
#' @examples
#' \dontrun{
#' # app.R, deployed to Posit Connect with rsconnect::deployApp()
#' library(shinymcp)
#'
#' app <- mcp_app(ui, tools = list(summarize_dataset), name = "datasets")
#' mcp_endpoint(app)
#'
#' # A Shiny app for people, and an app built from tools for chat clients
#' library(shiny)
#' shinyApp(ui, server) |> mcp_endpoint(apps = app)
#'
#' # A Shiny app, served live to chat clients and as usual to browsers
#' shinyApp(ui, server) |> mcp_endpoint(name = "explorer")
#' }
mcp_endpoint <- function(
  x,
  apps = NULL,
  path = "/mcp",
  allowed_origins = NULL,
  allowed_hosts = NULL,
  preview = TRUE,
  ...
) {
  rlang::check_installed("shiny", reason = "to serve MCP from a Shiny app.")
  if (!is.null(apps) && !inherits(x, "shiny.appobj")) {
    shinymcp_abort(
      "{.arg apps} goes with a Shiny app in {.arg x}; to serve apps alone, pass them as {.arg x}.",
      class = "shinymcp_error_validation"
    )
  }
  if (inherits(x, "shiny.appobj") && !is.null(apps)) {
    if (...length() > 0) {
      shinymcp_abort(
        "{.arg ...} is for serving a Shiny app live; with {.arg apps}, set names and descriptions in {.fn mcp_app}.",
        class = "shinymcp_error_validation"
      )
    }
    apps <- as_app_list(apps)
    base <- x
  } else if (inherits(x, "shiny.appobj")) {
    # Start the app now, once, as runApp() would, so its UI can be built (a
    # shinyAppDir() app's ui.R may use what global.R defines), then change
    # back: other code shares the process. After that, starting it only
    # changes into its directory: the live app does for each call, and
    # runApp() does for browsers, then stops the app as usual.
    lifecycle <- app_lifecycle(on_start = x$onStart)
    lifecycle$start()
    dir <- lifecycle$dir()
    enter <- if (!is.null(dir)) function() setwd(dir)
    started <- x
    started$onStart <- enter
    started$onStop <- NULL
    apps <- list(as_mcp_app(started, ...))
    base <- x
    base$onStart <- enter
  } else {
    apps <- as_app_list(x)
    base <- NULL
  }
  server <- McpServer$new(apps)
  if (is.null(base)) {
    page <- if (isTRUE(preview)) {
      preview_page(server, unlist(lapply(server$apps, default_entry_tool))[1])
    }
    base <- shiny::shinyApp(
      ui = function(req) {
        if (is.null(page)) {
          shiny::httpResponse(
            404L,
            "text/plain",
            paste0("This app serves MCP at ", path, ".")
          )
        } else {
          shiny::httpResponse(200L, "text/html; charset=utf-8", page)
        }
      },
      server = function(input, output, session) NULL
    )
  }

  handler <- mcp_http_handler(
    server,
    path = path,
    allowed_origins = allowed_origins,
    local = !on_hosted_platform(),
    allowed_hosts = allowed_hosts
  )
  wrapped <- base$httpHandler
  base$httpHandler <- function(req) {
    response <- tryCatch(
      handler(req),
      error = function(e) {
        http_json(
          500L,
          jsonrpc_error(NULL, RPC_INTERNAL_ERROR, conditionMessage(e))
        )
      }
    )
    if (is.null(response)) {
      return(wrapped(req))
    }
    rook_to_shiny_response(response)
  }
  stop_app <- base$onStop
  base$onStop <- function() {
    for (app in server$apps) {
      app$close()
    }
    if (is.function(stop_app)) {
      stop_app()
    }
  }
  base$mcpServer <- server
  base
}

#' @noRd
rook_to_shiny_response <- function(response) {
  headers <- response$headers %||% list()
  content_type <- headers[["Content-Type"]] %||% "text/plain"
  headers[["Content-Type"]] <- NULL
  shiny::httpResponse(
    status = response$status,
    content_type = content_type,
    content = response$body %||% "",
    headers = headers
  )
}

#' Is this process running on a hosting platform?
#'
#' On Posit Connect and shinyapps.io the server isn't a developer's local
#' process, so loopback hosts and origins get no special treatment.
#' (`CONNECT_SERVER` doesn't count: people set it on their own machines to
#' deploy.)
#' @noRd
on_hosted_platform <- function() {
  on_posit_connect() ||
    identical(Sys.getenv("R_CONFIG_ACTIVE"), "shinyapps") ||
    nzchar(Sys.getenv("SHINY_SERVER_VERSION"))
}

#' @noRd
on_posit_connect <- function() {
  identical(Sys.getenv("RSTUDIO_PRODUCT"), "CONNECT")
}

#' Run an MCP App with shiny::runApp()
#'
#' `shiny::runApp(app)` serves an [McpApp] through [mcp_endpoint()].
#' @param x An [McpApp].
#' @noRd
#' @exportS3Method shiny::as.shiny.appobj
as.shiny.appobj.McpApp <- function(x) {
  mcp_endpoint(x)
}
