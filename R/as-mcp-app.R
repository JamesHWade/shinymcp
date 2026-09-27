# as_mcp_app(): serve a Shiny app as an MCP App

#' Serve a Shiny app as an MCP App
#'
#' @description
#' `as_mcp_app()` turns an existing Shiny app into an MCP App without
#' rewriting it. The app's UI becomes the page the chat client shows, and
#' its server function keeps running in R: each time the app opens in the
#' conversation, shinymcp starts a session for it, and the user's changes
#' flow to that session the way they would from a browser. Reactive
#' expressions, observers, `updateSelectInput()` and friends,
#' `validate()`/`req()`, notifications, modals, and downloads all work.
#'
#' The model gets one tool, named after the app. Its arguments are the app's
#' inputs, so the model can open the app already set up ("show the penguins
#' explorer for Gentoo"). The result tells the model what the app shows:
#' text outputs as text, tables as text, plots as images.
#'
#' Choose what the model sees with [bindMcp()]. Once any input or output is
#' marked, only marked inputs become tool arguments and only marked outputs
#' are reported; the user still sees the whole app. Buttons are never
#' pressed by the model unless you mark them, and password and file inputs
#' are never exposed.
#'
#' @section What runs where:
#' The page is the app's UI rendered once to HTML, with shinymcp's bridge in
#' place of Shiny's JavaScript. The bridge provides native versions of
#' Shiny's inputs (select, slider, date, checkbox group, and so on) and
#' draws outputs sent back from R: text, HTML, tables, plots, `renderUI()`,
#' and htmlwidgets such as plotly and DT. Custom JavaScript input and output
#' bindings written against Shiny's client API won't work.
#'
#' Sessions live in the R process that serves the app, up to 50 at a time,
#' closing after an hour of inactivity. If a request reaches a process that
#' doesn't have the view's session (after a restart, or on a server running
#' several processes), a new session starts from the inputs on the page.
#' Anything the server function remembers outside its inputs (a
#' `reactiveVal()` that counts clicks, say) starts over.
#'
#' @param x A Shiny app (from [shiny::shinyApp()] or [shiny::shinyAppDir()]),
#'   a path to an app directory (with `app.R`, or `ui.R` and `server.R`), or
#'   an [McpApp] (returned unchanged).
#' @param name App name, used for the `ui://<name>` resource and the tool
#'   name. Defaults to the directory name for a path, otherwise
#'   `"shiny-app"`.
#' @param title Human-readable title.
#' @param description What the app does, for the model. By default shinymcp
#'   writes one from the inputs and outputs; a sentence about what the app
#'   is *for* helps the model decide when to open it.
#' @param tools Extra tools for the model, such as [ellmer::tool()] objects.
#'   Passing `tools` without `live = TRUE` gives the older behavior: the
#'   app's server function doesn't run, and your tools fill the outputs.
#' @param live Whether to run the app's server function. `TRUE` unless
#'   `tools` is given.
#' @param tool_name Name of the tool that opens the app. Defaults to `name`
#'   with anything other than letters, digits, `-` and `_` replaced.
#' @param selective Whether only inputs and outputs marked with [bindMcp()]
#'   are exposed to the model. Defaults to `TRUE` if anything is marked.
#' @param version App version string.
#' @param ... Passed on to [mcp_app()], for example `csp`,
#'   `prefers_border`, or `images`.
#' @return An [McpApp].
#' @family apps
#' @export
#' @examples
#' \dontrun{
#' library(shiny)
#'
#' ui <- fluidPage(
#'   selectInput("cyl", "Cylinders", c(4, 6, 8)),
#'   plotOutput("scatter"),
#'   textOutput("count")
#' )
#' server <- function(input, output, session) {
#'   cars <- reactive(mtcars[mtcars$cyl == input$cyl, ])
#'   output$scatter <- renderPlot(plot(cars()$wt, cars()$mpg))
#'   output$count <- renderText(paste(nrow(cars()), "cars"))
#' }
#'
#' app <- as_mcp_app(
#'   shinyApp(ui, server),
#'   name = "cars",
#'   description = "Explore fuel economy in mtcars by number of cylinders."
#' )
#' preview_app(app)
#' serve(app)
#'
#' # Or straight from a directory:
#' serve("path/to/my-app")
#' }
as_mcp_app <- function(x, ...) {
  UseMethod("as_mcp_app")
}

#' @rdname as_mcp_app
#' @export
as_mcp_app.shiny.appobj <- function(
  x,
  name = NULL,
  title = NULL,
  description = NULL,
  tools = NULL,
  live = is.null(tools),
  tool_name = NULL,
  selective = NULL,
  version = "0.1.0",
  ...
) {
  rlang::check_installed(
    "shiny",
    reason = "to serve a Shiny app as an MCP App."
  )
  # A Shiny app from mcp_endpoint() already carries its MCP App.
  if (inherits(x$mcpServer, "McpServer") && length(x$mcpServer$apps) == 1) {
    return(x$mcpServer$apps[[1]])
  }
  name <- name %||% "shiny-app"
  # Start the app as runApp() would before building its UI: a shinyAppDir()
  # app's ui.R may use what its global.R defines.
  lifecycle <- app_lifecycle(on_start = x$onStart, on_stop = x$onStop)
  ui <- lifecycle$within(function() extract_shiny_ui(x))

  if (!isTRUE(live)) {
    return(explicit_tools_app(
      ui,
      tools,
      name,
      title,
      description,
      selective,
      version,
      ...
    ))
  }

  runtime <- ShinyRuntime$new(
    server = x$serverFuncSource,
    ui = ui,
    app_name = name,
    tool_name = tool_name,
    title = title,
    description = description,
    lifecycle = lifecycle,
    selective = selective
  )
  warn_unsupported_inputs(runtime)

  mcp_app(
    ui = ui,
    tools = c(runtime$tools(), tools %||% list()),
    name = name,
    title = title,
    description = description,
    version = version,
    runtime = runtime,
    ...
  )
}

#' @rdname as_mcp_app
#' @export
as_mcp_app.McpApp <- function(x, ...) {
  x
}

#' @rdname as_mcp_app
#' @export
as_mcp_app.character <- function(x, name = NULL, ...) {
  if (length(x) != 1) {
    shinymcp_abort(
      "{.arg x} must be a single path.",
      class = "shinymcp_error_validation"
    )
  }
  path <- x
  if (!file.exists(path)) {
    shinymcp_abort(
      "App not found: {.file {path}}.",
      class = "shinymcp_error_validation"
    )
  }
  dir <- if (dir.exists(path)) path else dirname(path)
  name <- name %||% sanitize_name(basename(normalizePath(dir)))
  app_file <- if (dir.exists(path)) file.path(path, "app.R") else path

  if (file.exists(app_file)) {
    found <- source_app_file(app_file)
    if (inherits(found, "McpApp")) {
      return(found)
    }
    return(as_mcp_app(found, name = name, ...))
  }
  if (file.exists(file.path(dir, "server.R"))) {
    rlang::check_installed(
      "shiny",
      reason = "to serve a Shiny app as an MCP App."
    )
    return(as_mcp_app(shiny::shinyAppDir(dir), name = name, ...))
  }
  shinymcp_abort(
    "No {.file app.R} or {.file server.R} in {.file {dir}}.",
    class = "shinymcp_error_validation"
  )
}

#' @rdname as_mcp_app
#' @export
as_mcp_app.default <- function(x, ...) {
  shinymcp_abort(
    c(
      "Can't make an MCP App from an object of class {.cls {class(x)}}.",
      "i" = "Use a Shiny app, a path to one, or an {.cls McpApp}."
    ),
    class = "shinymcp_error_validation"
  )
}

#' Source an app.R and find the app it defines
#'
#' `serve()` is stubbed out so a script that ends in `serve(app)` doesn't
#' start a server while being loaded.
#' @noRd
source_app_file <- function(app_file) {
  env <- new.env(parent = globalenv())
  env$serve <- function(...) invisible(NULL)
  env$preview_app <- function(...) invisible(NULL)
  sourced <- tryCatch(
    source(app_file, local = env, chdir = TRUE),
    error = function(e) {
      shinymcp_abort(
        c("Failed to load {.file {app_file}}.", "x" = "{conditionMessage(e)}"),
        class = "shinymcp_error_validation",
        parent = e
      )
    }
  )
  candidates <- c(
    list(sourced$value),
    mget(ls(env), envir = env, inherits = FALSE)
  )
  for (obj in candidates) {
    if (inherits(obj, "McpApp")) {
      return(obj)
    }
  }
  for (obj in candidates) {
    if (inherits(obj, "shiny.appobj")) {
      return(obj)
    }
  }
  shinymcp_abort(
    "{.file {app_file}} doesn't define an {.cls McpApp} or a Shiny app.",
    class = "shinymcp_error_validation"
  )
}

#' The pre-runtime behaviour: explicit tools fill the Shiny UI's outputs
#' @noRd
explicit_tools_app <- function(
  ui,
  tools,
  name,
  title,
  description,
  selective,
  version,
  ...
) {
  if (length(tools) == 0) {
    shinymcp_abort(
      c(
        "An app with {.code live = FALSE} needs {.arg tools}.",
        "i" = "Pass the tools its UI calls, or leave {.arg live} as {.code TRUE} to run the Shiny server function."
      ),
      class = "shinymcp_error_validation"
    )
  }
  if (is.null(selective)) {
    selective <- has_any_mcp_annotations(ui)
  }
  inputs <- extract_inputs_from_tags(ui, selective = selective)
  # Explicit tools define the interaction contract, but every output still
  # needs its annotation so returned values can render.
  outputs <- extract_outputs_from_tags(ui, selective = FALSE)
  ui <- annotate_module_ui(ui, inputs, outputs)
  mcp_app(
    ui = ui,
    tools = tools,
    name = name,
    title = title,
    description = description,
    version = version,
    ...
  )
}

#' @noRd
warn_unsupported_inputs <- function(runtime) {
  files <- names(Filter(function(i) identical(i$kind, "file"), runtime$inputs))
  if (length(files)) {
    cli::cli_warn(c(
      "File inputs ({.val {files}}) can't be used in an MCP App.",
      "i" = "Chat clients don't pass uploads to apps. Read files from a known location, or take a path as a text input."
    ))
  }
}

# ---- Shiny app object helpers ----

#' Extract the UI from a shiny.appobj
#' @noRd
extract_shiny_ui <- function(app) {
  ui <- app$ui
  if (is.null(ui) && is.function(app$httpHandler)) {
    ui <- ui_from_http_handler(app)
  }
  if (is.function(ui)) {
    req <- fake_ui_request()
    ui <- tryCatch(
      if (length(formals(ui)) == 0) ui() else ui(req),
      error = function(e) {
        shinymcp_abort(
          c("Couldn't build the app's UI.", "x" = "{conditionMessage(e)}"),
          class = "shinymcp_error_validation",
          parent = e
        )
      }
    )
  }
  if (is.null(ui)) {
    shinymcp_abort(
      "Couldn't find the UI of this Shiny app.",
      class = "shinymcp_error_validation"
    )
  }
  if (inherits(ui, "html") || is.character(ui)) {
    ui <- htmltools::HTML(paste(ui, collapse = "\n"))
  }
  ui
}

#' A minimal request for UI functions that take `req`
#' @noRd
fake_ui_request <- function() {
  req <- new.env(parent = emptyenv())
  req$PATH_INFO <- "/"
  req$REQUEST_METHOD <- "GET"
  req$QUERY_STRING <- ""
  req$HTTP_HOST <- "shinymcp"
  req$HTTP_MCP_APP <- "1"
  req
}

#' Find the UI behind an app object's HTTP handler
#'
#' shinyApp() keeps `ui` in its handler's closure. shinyAppDir() hides it
#' deeper: behind a list of joined handlers and a function that (re)sources
#' ui.R. Follow those closures a few levels down.
#' @noRd
ui_from_http_handler <- function(app) {
  search <- function(fn, depth) {
    if (!is.function(fn) || depth > 4) {
      return(NULL)
    }
    env <- environment(fn)
    if (is.null(env)) {
      return(NULL)
    }
    if (exists("uiHandlerSource", envir = env, inherits = FALSE)) {
      handler <- tryCatch(
        get("uiHandlerSource", envir = env)(),
        error = function(e) NULL
      )
      found <- search(handler, depth + 1)
      if (!is.null(found)) return(found)
    }
    if (exists("appObj", envir = env, inherits = FALSE)) {
      inner <- tryCatch(get("appObj", envir = env)(), error = function(e) NULL)
      if (inherits(inner, "shiny.appobj")) {
        return(inner$ui %||% search(inner$httpHandler, depth + 1))
      }
    }
    if (exists("ui", envir = env, inherits = FALSE)) {
      return(get("ui", envir = env, inherits = FALSE))
    }
    if (exists("handlers", envir = env, inherits = FALSE)) {
      for (h in get("handlers", envir = env, inherits = FALSE)) {
        found <- search(h, depth + 1)
        if (!is.null(found)) return(found)
      }
    }
    NULL
  }
  search(app$httpHandler, 0)
}

#' Check if any tag in the tree has MCP annotations
#' @noRd
has_any_mcp_annotations <- function(ui) {
  found <- FALSE
  walk_tag_tree(ui, function(tag) {
    if (found) {
      return()
    }
    if (
      !is.null(htmltools::tagGetAttribute(tag, "data-shinymcp-input")) ||
        !is.null(htmltools::tagGetAttribute(tag, "data-shinymcp-output"))
    ) {
      found <<- TRUE
    }
  })
  found
}
