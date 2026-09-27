# MCP protocol: versions, JSON-RPC messages, and request dispatch
#
# shinymcp speaks both eras of MCP:
#
# * Legacy (2024-11-05 to 2025-11-25): the client opens with `initialize`,
#   the server negotiates a version and remembers the client's capabilities
#   for the session (keyed by `Mcp-Session-Id` over HTTP).
# * Modern (2026-07-28): no handshake and no sessions. Every request carries
#   its protocol version and the client's capabilities in `params._meta`,
#   so any server process can answer any request. `server/discover`
#   advertises what the server supports.
#
# A request with modern `_meta` is served statelessly; `initialize` selects
# the legacy behaviour. Both can be in use on the same endpoint.

# ---- Constants ----

#' Modern (stateless) protocol versions, newest first
#' @noRd
SHINYMCP_MODERN_VERSIONS <- c("2026-07-28")

#' Legacy (handshake) protocol versions, newest first
#' @noRd
SHINYMCP_LEGACY_VERSIONS <- c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")

#' Every protocol version shinymcp serves
#' @noRd
SHINYMCP_PROTOCOL_VERSIONS <- c(SHINYMCP_MODERN_VERSIONS, SHINYMCP_LEGACY_VERSIONS)

#' Latest legacy version, used when a client asks for one we don't know
#' @noRd
SHINYMCP_PROTOCOL_VERSION <- SHINYMCP_LEGACY_VERSIONS[[1]]

#' MCP Apps extension version implemented by the bridge and hosts
#' @noRd
SHINYMCP_APPS_PROTOCOL_VERSION <- "2026-01-26"

#' Extension id clients use to declare MCP Apps support
#' @noRd
SHINYMCP_UI_EXTENSION_ID <- "io.modelcontextprotocol/ui"

#' MIME type of `ui://` resources
#' @noRd
SHINYMCP_UI_MIME_TYPE <- "text/html;profile=mcp-app"

# `_meta` keys defined by the 2026-07-28 revision.
META_PROTOCOL_VERSION <- "io.modelcontextprotocol/protocolVersion"
META_CLIENT_INFO <- "io.modelcontextprotocol/clientInfo"
META_CLIENT_CAPABILITIES <- "io.modelcontextprotocol/clientCapabilities"
META_SERVER_INFO <- "io.modelcontextprotocol/serverInfo"

# JSON-RPC and MCP error codes.
RPC_PARSE_ERROR <- -32700L
RPC_INVALID_REQUEST <- -32600L
RPC_METHOD_NOT_FOUND <- -32601L
RPC_INVALID_PARAMS <- -32602L
RPC_INTERNAL_ERROR <- -32603L
RPC_RESOURCE_NOT_FOUND_LEGACY <- -32002L
RPC_HEADER_MISMATCH <- -32020L
RPC_MISSING_CAPABILITY <- -32021L
RPC_UNSUPPORTED_VERSION <- -32022L

# ---- JSON-RPC helpers ----

#' @noRd
jsonrpc_response <- function(id, result) {
  list(jsonrpc = "2.0", id = id, result = result)
}

#' A JSON-RPC error response
#'
#' `status` is the HTTP status the Streamable HTTP transport should use.
#' @noRd
jsonrpc_error <- function(id, code, message, data = NULL, status = 200L) {
  error <- list(code = code, message = message)
  if (!is.null(data)) {
    error$data <- data
  }
  structure(
    list(jsonrpc = "2.0", id = id, error = error),
    http_status = status
  )
}

#' Negotiate a legacy protocol version
#'
#' Echo the client's version when supported, otherwise offer the latest.
#' @noRd
negotiate_protocol_version <- function(requested) {
  if (is_string(requested) && requested %in% SHINYMCP_LEGACY_VERSIONS) {
    return(requested)
  }
  SHINYMCP_PROTOCOL_VERSION
}

#' Does a client's capabilities object declare MCP Apps support?
#'
#' Clients declare `capabilities.extensions["io.modelcontextprotocol/ui"]`
#' with the MIME types they render. A missing `mimeTypes` is read as the
#' default HTML profile.
#' @param capabilities The client's capabilities (a list).
#' @noRd
capabilities_support_ui <- function(capabilities) {
  ui <- capabilities$extensions[[SHINYMCP_UI_EXTENSION_ID]]
  if (is.null(ui)) {
    return(FALSE)
  }
  mime_types <- unlist(ui$mimeTypes, use.names = FALSE)
  is.null(mime_types) || SHINYMCP_UI_MIME_TYPE %in% mime_types
}

#' @noRd
client_supports_mcp_apps <- function(params) {
  capabilities_support_ui(params$capabilities)
}

# ---- Server ----

#' An MCP server for one or more apps
#'
#' Holds the apps, routes tool calls and resource reads to the app that owns
#' them, and turns JSON-RPC requests into responses. Transports (stdio,
#' HTTP, Shiny) feed it parsed messages and write out what it returns.
#' @noRd
McpServer <- R6::R6Class(
  "McpServer",
  public = list(
    apps = NULL,
    name = NULL,
    version = NULL,
    instructions = NULL,

    initialize = function(apps, name = NULL, version = NULL, instructions = NULL) {
      apps <- as_app_list(apps)
      self$apps <- apps
      self$name <- name %||%
        if (length(apps) == 1) paste0("shinymcp-", apps[[1]]$name) else "shinymcp"
      self$version <- version %||% as.character(utils::packageVersion("shinymcp"))
      self$instructions <- instructions %||% server_instructions(apps)
      private$index_tools()
      invisible(self)
    },

    # Handle one JSON-RPC message
    #
    # @param message Parsed JSON-RPC message (a list).
    # @param context Transport context: `transport`, `session` (a legacy
    #   session environment, or NULL), `headers`, `user`, `groups`.
    # @return A response list, or NULL for notifications.
    handle = function(message, context = list()) {
      if (!is.list(message) || !identical(message$jsonrpc, "2.0")) {
        return(jsonrpc_error(
          message$id %||% NULL,
          RPC_INVALID_REQUEST,
          "Invalid Request: expected a JSON-RPC 2.0 message.",
          status = 400L
        ))
      }
      method <- message$method
      if (is.null(method)) {
        # A response from the client: nothing to do.
        return(NULL)
      }
      is_notification <- is.null(message$id)
      meta <- message$params[["_meta"]]
      modern_version <- meta[[META_PROTOCOL_VERSION]]

      if (!is.null(modern_version) && !identical(method, "initialize")) {
        request <- private$modern_request(message, modern_version, context)
      } else {
        request <- private$legacy_request(message, context)
      }
      if (inherits(request, "jsonrpc_error_response")) {
        return(if (is_notification) NULL else unclass_error(request))
      }
      if (is_notification) {
        return(NULL)
      }

      result <- tryCatch(
        private$dispatch(method, message$params %||% list(), request),
        shinymcp_rpc_error = function(e) e,
        error = function(e) {
          structure(
            class = c("shinymcp_rpc_error", "error", "condition"),
            list(
              message = paste0("Internal error: ", conditionMessage(e)),
              code = RPC_INTERNAL_ERROR,
              data = NULL,
              status = 200L,
              call = NULL
            )
          )
        }
      )
      if (inherits(result, "shinymcp_rpc_error")) {
        return(jsonrpc_error(
          message$id,
          e_code(result),
          conditionMessage(result),
          data = result$data,
          status = result$status %||% 200L
        ))
      }
      if (request$era == "modern") {
        result$resultType <- result$resultType %||% "complete"
        result_meta <- result[["_meta"]] %||% list()
        result_meta[[META_SERVER_INFO]] <- private$server_info()
        result[["_meta"]] <- result_meta
      }
      jsonrpc_response(message$id, result)
    },

    # The app that owns a tool, or NULL
    tool_app = function(name) {
      private$tools_index[[name %||% ""]]
    },

    # Look up the app serving a resource URI, or NULL
    resource_app = function(uri) {
      for (app in self$apps) {
        if (app$has_resource(uri)) {
          return(app)
        }
      }
      NULL
    },

    # A fresh legacy session environment
    new_session = function() {
      new_mcp_session()
    }
  ),

  private = list(
    tools_index = NULL,

    index_tools = function() {
      index <- list()
      owners <- list()
      for (app in self$apps) {
        for (tool in app$tools()) {
          if (!is.null(index[[tool$name]])) {
            shinymcp_abort(
              c(
                "Tool {.val {tool$name}} is defined by more than one app ({.val {owners[[tool$name]]}} and {.val {app$name}}).",
                "i" = "Tool names must be unique across the apps a server serves."
              ),
              class = "shinymcp_error_validation"
            )
          }
          index[[tool$name]] <- app
          owners[[tool$name]] <- app$name
        }
      }
      uris <- unlist(lapply(self$apps, function(a) {
        vapply(a$resources(), `[[`, character(1), "uri")
      }))
      dupes <- unique(uris[duplicated(uris)])
      if (length(dupes)) {
        shinymcp_abort(
          "Resource URIs must be unique across apps; {.val {dupes}} repeats. Give each app a distinct {.arg name}.",
          class = "shinymcp_error_validation"
        )
      }
      private$tools_index <- index
    },

    server_info = function() {
      list(name = self$name, version = self$version)
    },

    capabilities = function() {
      extensions <- list()
      extensions[[SHINYMCP_UI_EXTENSION_ID]] <- json_object()
      list(
        tools = list(listChanged = FALSE),
        resources = list(subscribe = FALSE, listChanged = FALSE),
        extensions = extensions
      )
    },

    # Validate a request carrying modern per-request metadata.
    modern_request = function(message, version, context) {
      if (!version %in% SHINYMCP_MODERN_VERSIONS) {
        return(error_response(jsonrpc_error(
          message$id,
          RPC_UNSUPPORTED_VERSION,
          "Unsupported protocol version",
          data = list(
            supported = I(SHINYMCP_PROTOCOL_VERSIONS),
            requested = version
          ),
          status = 400L
        )))
      }
      meta <- message$params[["_meta"]]
      capabilities <- meta[[META_CLIENT_CAPABILITIES]] %||% list()
      list(
        era = "modern",
        protocol_version = version,
        supports_ui = capabilities_support_ui(capabilities),
        client = meta[[META_CLIENT_INFO]],
        context = context,
        meta = meta
      )
    },

    legacy_request = function(message, context) {
      session <- context$session %||% new_mcp_session()
      list(
        era = "legacy",
        protocol_version = session$protocol_version,
        supports_ui = isTRUE(session$client_supports_ui),
        client = session$client_info,
        session = session,
        context = context,
        meta = message$params[["_meta"]]
      )
    },

    dispatch = function(method, params, request) {
      switch(
        method,
        "initialize" = private$handle_initialize(params, request),
        "server/discover" = private$handle_discover(),
        "ping" = json_object(),
        "tools/list" = private$handle_tools_list(request),
        "tools/call" = private$handle_tools_call(params, request),
        "resources/list" = private$cacheable(
          list(resources = I(private$all_resources())),
          request
        ),
        "resources/templates/list" = private$cacheable(
          list(resourceTemplates = I(list())),
          request
        ),
        "resources/read" = private$handle_resources_read(params, request),
        "prompts/list" = private$cacheable(list(prompts = I(list())), request),
        rpc_stop(
          paste("Method not found:", method),
          code = RPC_METHOD_NOT_FOUND,
          status = if (request$era == "modern") 404L else 200L
        )
      )
    },

    handle_initialize = function(params, request) {
      session <- request$session
      version <- negotiate_protocol_version(params$protocolVersion)
      if (!is.null(session)) {
        session$protocol_version <- version
        session$client_supports_ui <- client_supports_mcp_apps(params)
        session$client_info <- params$clientInfo
        session$initialized <- TRUE
      }
      compact_list(list(
        protocolVersion = version,
        capabilities = private$capabilities(),
        serverInfo = private$server_info(),
        instructions = self$instructions
      ))
    },

    handle_discover = function() {
      compact_list(list(
        supportedVersions = I(SHINYMCP_PROTOCOL_VERSIONS),
        capabilities = private$capabilities(),
        instructions = self$instructions,
        ttlMs = 60000,
        cacheScope = "public"
      ))
    },

    handle_tools_list = function(request) {
      ui <- request$supports_ui
      tools <- unlist(
        lapply(self$apps, function(app) {
          app$tool_definitions(include_ui_meta = ui, include_app_only = ui)
        }),
        recursive = FALSE
      )
      private$cacheable(list(tools = I(tools %||% list())), request)
    },

    handle_tools_call = function(params, request) {
      name <- params$name
      if (!is_string(name)) {
        rpc_stop("Missing required parameter: name", code = RPC_INVALID_PARAMS)
      }
      app <- self$tool_app(name)
      if (is.null(app)) {
        rpc_stop(paste0("Unknown tool: ", name), code = RPC_INVALID_PARAMS)
      }
      arguments <- params$arguments %||% list()
      if (!is.list(arguments)) {
        rpc_stop("Tool arguments must be an object.", code = RPC_INVALID_PARAMS)
      }
      call_context <- private$call_context(params, request)
      app$run_tool(name, arguments, call_context)
    },

    handle_resources_read = function(params, request) {
      uri <- params$uri
      if (!is_string(uri)) {
        rpc_stop("Missing required parameter: uri", code = RPC_INVALID_PARAMS)
      }
      app <- self$resource_app(uri)
      if (is.null(app)) {
        rpc_stop(
          paste0("Resource not found: ", uri),
          code = if (request$era == "modern") RPC_INVALID_PARAMS else RPC_RESOURCE_NOT_FOUND_LEGACY,
          data = list(uri = uri)
        )
      }
      contents <- with_request_context(
        private$call_context(params, request),
        app$read_resource(uri)
      )
      private$cacheable(list(contents = list(contents)), request, ttl = 0)
    },

    all_resources = function() {
      unlist(lapply(self$apps, function(app) app$resources()), recursive = FALSE)
    },

    # Modern results for list and read calls carry caching hints.
    cacheable = function(result, request, ttl = 60000) {
      if (request$era == "modern") {
        result$ttlMs <- ttl
        result$cacheScope <- "private"
      }
      result
    },

    call_context = function(params, request) {
      meta <- params[["_meta"]] %||% list()
      transport <- request$context
      caller <- meta[["shinymcp/caller"]]
      compact_list(list(
        caller = if (identical(caller, "app")) "app" else "model",
        skip_deps = as.character(unlist(meta[["shinymcp/deps"]])),
        protocol_version = request$protocol_version,
        era = request$era,
        client = request$client,
        supports_ui = request$supports_ui,
        transport = transport$transport %||% "in-process",
        headers = transport$headers,
        user = transport$user,
        groups = transport$groups,
        view = meta[["shinymcp/view"]]
      ))
    }
  )
)

#' @noRd
as_app_list <- function(apps) {
  if (inherits(apps, "McpApp")) {
    return(list(apps))
  }
  if (is.list(apps) && length(apps) > 0) {
    apps <- lapply(apps, as_mcp_app)
    names_ <- vapply(apps, function(a) a$name, character(1))
    dupes <- unique(names_[duplicated(names_)])
    if (length(dupes)) {
      shinymcp_abort(
        "App names must be unique; {.val {dupes}} appears more than once.",
        class = "shinymcp_error_validation"
      )
    }
    return(apps)
  }
  list(as_mcp_app(apps))
}

#' @noRd
server_instructions <- function(apps) {
  described <- Filter(function(a) !is.null(a$description), apps)
  if (length(described) == 0) {
    return(NULL)
  }
  lines <- vapply(
    described,
    function(a) paste0("- ", a$title %||% a$name, ": ", a$description),
    character(1)
  )
  paste(c("This server provides interactive apps:", lines), collapse = "\n")
}

#' Per-connection state for legacy (handshake) clients
#'
#' Clients that skip `initialize` are served leniently, as if they declared
#' MCP Apps support.
#' @noRd
new_mcp_session <- function() {
  session <- new.env(parent = emptyenv())
  session$client_supports_ui <- TRUE
  session$protocol_version <- SHINYMCP_PROTOCOL_VERSION
  session$client_info <- NULL
  session$initialized <- FALSE
  session$created <- as.numeric(Sys.time())
  session
}

#' Signal a JSON-RPC error from inside a handler
#' @noRd
rpc_stop <- function(message, code, data = NULL, status = 200L) {
  cnd <- structure(
    class = c("shinymcp_rpc_error", "error", "condition"),
    list(message = message, code = code, data = data, status = status, call = NULL)
  )
  stop(cnd)
}

#' @noRd
e_code <- function(e) {
  e$code
}

#' @noRd
error_response <- function(response) {
  structure(list(response = response), class = "jsonrpc_error_response")
}

#' @noRd
unclass_error <- function(x) {
  x$response
}
