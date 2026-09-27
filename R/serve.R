# serve(): run an MCP server for one or more apps.

#' Serve MCP Apps to an MCP client
#'
#' @description
#' `serve()` starts an MCP server for an app and blocks until the client
#' disconnects (stdio) or you interrupt it (HTTP).
#'
#' * `type = "stdio"`, the default, is for desktop clients such as Claude
#'   Desktop, VS Code, and Goose, which start the R process themselves and
#'   talk to it over standard input and output. Put `serve(app)` at the end
#'   of a script and register `Rscript /path/to/script.R` with the client.
#' * `type = "http"` runs a long-lived Streamable HTTP server at
#'   `http://host:port/mcp`, for clients that connect to a URL. To deploy
#'   to Posit Connect, use [mcp_endpoint()] instead.
#'
#' The server speaks MCP protocol versions 2024-11-05 through 2025-11-25
#' (with an `initialize` handshake) and 2026-07-28 (stateless, no
#' handshake), and the MCP Apps extension (2026-01-26). Clients that don't
#' support MCP Apps still get every tool; they see text results instead of
#' the app.
#'
#' @param app An [McpApp], a list of apps to serve from one server, a Shiny
#'   app object, or a path to a directory containing an `app.R` (or `ui.R`
#'   and `server.R`). Shiny apps run live; see [as_mcp_app()].
#' @param type `"stdio"` or `"http"`.
#' @param port,host Where the HTTP server listens. The default host only
#'   accepts connections from this machine; use `"0.0.0.0"` to listen on
#'   all interfaces, and put the server behind authentication.
#' @param path The HTTP endpoint path.
#' @param allowed_origins Browser origins, besides the server's own and
#'   loopback ones for a local server, allowed to call the HTTP endpoint,
#'   for example `"https://chat.example.com"`. Use `"*"` to allow any.
#' @param allowed_hosts For a server listening on this machine only, the
#'   host names it may be reached at besides `localhost` and `127.0.0.1`,
#'   such as the public name of a reverse proxy in front of it. Requests for
#'   any other host are refused, which protects a local server from web
#'   pages that point their own host name at it (DNS rebinding).
#' @param ... Unused; for future extensions.
#' @return Nothing; `serve()` runs until the connection closes.
#' @family serving
#' @export
#' @examples
#' \dontrun{
#' # app.R, registered with Claude Desktop as `Rscript /path/to/app.R`
#' library(shinymcp)
#' app <- mcp_app(ui, tools, name = "explorer")
#' serve(app)
#'
#' # An existing Shiny app, served live
#' serve("path/to/shiny-app")
#'
#' # Over HTTP
#' serve(app, type = "http", port = 8080)
#' }
serve <- function(
  app,
  type = c("stdio", "http"),
  port = 8080,
  host = "127.0.0.1",
  path = "/mcp",
  allowed_origins = NULL,
  allowed_hosts = NULL,
  ...
) {
  type <- match.arg(type)
  server <- McpServer$new(app)
  for (a in server$apps) {
    warn_host_only_trigger(a, "serve()")
  }
  switch(
    type,
    stdio = serve_stdio(server),
    http = serve_http(
      server,
      host = host,
      port = port,
      path = path,
      allowed_origins = allowed_origins,
      allowed_hosts = allowed_hosts
    )
  )
}

#' Warn when an app's trigger needs shinymcp's Shiny host
#'
#' `trigger = "manual"` means the embedding page runs tools itself; in a
#' chat client nothing would.
#' @noRd
warn_host_only_trigger <- function(app, where) {
  trigger <- app$interaction_defaults()$trigger
  if (identical(trigger, "manual")) {
    cli::cli_warn(c(
      "App {.val {app$name}} uses {.code trigger = \"manual\"}, which only works when a Shiny app embeds it with {.fn mcp_host_server} and runs its tools.",
      "i" = "In {where}, its outputs will fill in once and never update. Use {.val submit} for an apply button."
    ))
  }
}
