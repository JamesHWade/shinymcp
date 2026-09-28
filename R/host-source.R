# Sources: where a hosted app's tools and page come from
#
# The hosts treat apps in this R process and apps on a remote MCP server the
# same way. A source lists its tools (with their `_meta`), calls them, reads
# the page a tool declares, and passes on the requests an app's page makes.
# Calls from a Shiny session are asynchronous: an in-process call runs from
# later(), outside the reactive flush (an app served live runs reactive
# sessions of its own, which can't flush inside another flush), and a remote
# one is an HTTP request that doesn't block the session.

#' Make a source from an app, a list of apps, or a client
#' @noRd
as_host_source <- function(x) {
  if (inherits(x, "shinymcp_host_source")) {
    return(x)
  }
  if (inherits(x, "McpClient")) {
    return(remote_host_source(x))
  }
  in_process_host_source(x)
}

#' A list of sources, from one source or several
#' @noRd
as_host_sources <- function(x) {
  single <- inherits(
    x,
    c("McpApp", "McpClient", "shinymcp_host_source", "shiny.appobj")
  ) ||
    is.character(x)
  sources <- if (single) list(as_host_source(x)) else lapply(x, as_host_source)
  keys <- vapply(sources, function(s) s$key, character(1))
  dupes <- unique(keys[duplicated(keys)])
  if (length(dupes)) {
    shinymcp_abort(
      c(
        "Each source needs its own name; {.val {dupes}} is used twice.",
        "i" = "Give {.fn mcp_client} a {.arg name}, or the apps different names."
      ),
      class = "shinymcp_error_validation"
    )
  }
  names(sources) <- keys
  sources
}

#' @noRd
new_host_source <- function(kind, key, title) {
  source <- new.env(parent = emptyenv())
  source$kind <- kind
  source$key <- key
  source$title <- title
  class(source) <- c(
    paste0("shinymcp_host_source_", kind),
    "shinymcp_host_source"
  )
  source
}

#' Apps in this R process
#' @noRd
in_process_host_source <- function(apps) {
  server <- McpServer$new(apps)
  apps <- server$apps
  key <- if (length(apps) == 1) apps[[1]]$name else server$name
  title <- if (length(apps) == 1) apps[[1]]$title %||% apps[[1]]$name
  source <- new_host_source("in_process", key, title %||% key)
  source$server <- server
  source$apps <- apps

  source$tools <- function(refresh = FALSE) {
    unlist(
      lapply(apps, function(app) app$tool_definitions()),
      recursive = FALSE
    ) %||%
      list()
  }

  source$tools_async <- function(refresh = FALSE) {
    promises::promise_resolve(source$tools())
  }

  source$app_for_tool <- function(name) {
    server$tool_app(name)
  }

  # A model's call: the MCP result, and the R value the tool function
  # returned (for `value_fn`). Image blocks are left out of the result: the
  # page draws from the view in `_meta`, and the model gets the structured
  # content or the text.
  source$call <- function(name, arguments = NULL, context = list()) {
    app <- server$tool_app(name)
    if (is.null(app)) {
      shinymcp_abort(
        "No app here has a tool called {.val {name}}.",
        class = "shinymcp_error_validation"
      )
    }
    app$run_tool(
      name,
      arguments %||% list(),
      utils::modifyList(
        list(caller = "model", transport = "in-process", images = FALSE),
        context %||% list()
      ),
      raw = TRUE
    )
  }

  source$call_async <- function(name, arguments = NULL, context = list()) {
    deferred(function() source$call(name, arguments, context))
  }

  source$send_async <- function(message, context = list()) {
    deferred(function() {
      tryCatch(
        strip_http_status(server$handle(
          message,
          utils::modifyList(
            list(transport = "in-process", session = new_mcp_session()),
            context %||% list()
          )
        )),
        error = function(e) {
          jsonrpc_error(
            request_id(message),
            RPC_INTERNAL_ERROR,
            conditionMessage(e)
          )
        }
      )
    })
  }

  # The page for a resource URI. `config` is merged into the bridge's
  # configuration (a pane's trigger and debounce).
  source$page <- function(uri, config = NULL) {
    app <- server$resource_app(uri)
    if (is.null(app)) {
      shinymcp_abort(
        "No app here serves {.val {uri}}.",
        class = "shinymcp_error_resource"
      )
    }
    if (identical(uri, app$resource_uri())) {
      return(list(
        html = app$html_resource(config = config),
        meta = app$resource_meta()
      ))
    }
    contents <- app$read_resource(uri)
    list(html = contents$text, meta = contents[["_meta"]])
  }

  source$page_async <- function(uri, config = NULL) {
    deferred(function() source$page(uri, config))
  }

  source$interaction <- function(name, trigger = NULL, debounce_ms = NULL) {
    app <- server$tool_app(name)
    if (is.null(app)) {
      return(NULL)
    }
    resolve_host_interaction(app, trigger, debounce_ms)
  }

  source$close_views <- function(views) {
    for (app in apps) {
      runtime <- app$runtime()
      if (is.null(runtime)) {
        next
      }
      for (id in views) {
        try(runtime$view(list(action = "close", instance = id)), silent = TRUE)
      }
    }
  }

  source
}

#' A remote MCP server, through an McpClient
#' @noRd
remote_host_source <- function(client) {
  source <- new_host_source("remote", client$name, client$name)
  source$client <- client

  source$tools <- function(refresh = FALSE) {
    client$tools(refresh = refresh)
  }

  source$tools_async <- function(refresh = FALSE) {
    client$tools_async(refresh = refresh)
  }

  source$call <- function(name, arguments = NULL, context = list()) {
    list(result = client$call_tool(name, arguments), raw = NULL)
  }

  source$call_async <- function(name, arguments = NULL, context = list()) {
    promises::then(
      client$call_tool_async(name, arguments),
      function(result) list(result = result, raw = NULL)
    )
  }

  source$send_async <- function(message, context = list()) {
    promises::then(
      client$send_async(message),
      onFulfilled = function(response) response,
      onRejected = function(e) {
        jsonrpc_error(
          request_id(message),
          RPC_INTERNAL_ERROR,
          conditionMessage(e)
        )
      }
    )
  }

  source$page <- function(uri, config = NULL) {
    remote_page(client$read_resource(uri), uri)
  }

  source$page_async <- function(uri, config = NULL) {
    promises::then(
      client$read_resource_async(uri),
      function(result) remote_page(result, uri)
    )
  }

  source$interaction <- function(name, trigger = NULL, debounce_ms = NULL) {
    NULL
  }

  source$close_views <- function(views) invisible()

  source
}

#' The page in a `resources/read` result
#' @noRd
remote_page <- function(result, uri) {
  contents <- result$contents
  entry <- NULL
  for (item in contents %||% list()) {
    if (identical(item$uri, uri) || is.null(entry)) {
      entry <- item
    }
  }
  if (is.null(entry)) {
    shinymcp_abort(
      "The server returned nothing for {.val {uri}}.",
      class = "shinymcp_error_resource"
    )
  }
  html <- entry$text
  if (is.null(html) && is_string(entry$blob)) {
    html <- rawToChar(jsonlite::base64_dec(entry$blob))
    Encoding(html) <- "UTF-8"
  }
  if (!is_string(html)) {
    shinymcp_abort(
      "{.val {uri}} isn't an HTML page.",
      class = "shinymcp_error_resource"
    )
  }
  list(html = html, meta = entry[["_meta"]])
}

# ---- Tool metadata ----

#' A tool's definition in a source, or NULL
#' @noRd
source_tool <- function(source, name) {
  for (tool in source$tools()) {
    if (identical(tool$name, name)) {
      return(tool)
    }
  }
  NULL
}

#' The page a tool declares (`_meta.ui.resourceUri`), or NULL
#' @noRd
tool_resource_uri <- function(tool) {
  meta <- tool[["_meta"]] %||% list()
  uri <- meta$ui$resourceUri %||% meta[["ui/resourceUri"]]
  if (is_string(uri)) uri else NULL
}

#' Who may call a tool, from `_meta.ui.visibility` (both, by default)
#' @noRd
tool_wire_visible_to <- function(tool, audience = c("model", "app")) {
  audience <- match.arg(audience)
  visibility <- tool[["_meta"]]$ui$visibility
  is.null(visibility) || audience %in% unlist(visibility)
}

#' The names of a source's tools that an audience may call
#' @noRd
source_tool_names <- function(source, audience) {
  tools <- Filter(function(t) tool_wire_visible_to(t, audience), source$tools())
  vapply(tools, function(t) t$name, character(1))
}

# ---- Helpers ----

#' Run `fn` from later() and return a promise of its value
#' @noRd
deferred <- function(fn) {
  rlang::check_installed(
    c("later", "promises"),
    reason = "to host MCP Apps in Shiny."
  )
  promises::promise(function(resolve, reject) {
    later::later(function() {
      value <- tryCatch(fn(), error = function(e) e)
      if (inherits(value, "error")) reject(value) else resolve(value)
    })
  })
}
