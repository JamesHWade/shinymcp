# mcp_client(): a client for remote MCP servers, for the hosts
#
# The hosts (mcp_host_server(), mcp_chat_host()) show apps from any MCP
# server. For servers in another process they need a client that keeps
# `_meta` on every result (mcptools drops it), declares the MCP Apps
# extension, and can make requests without blocking a Shiny session.
#
# Both protocol generations: the stateless 2026-07-28 revision, where every
# request carries its version and capabilities in `params._meta`, and the
# `initialize` handshake of 2025-11-25 and earlier, where the server may
# keep a session (`Mcp-Session-Id`). The client asks `server/discover`
# first and falls back to the handshake.

#' Protocol version the client asks for in the handshake era
#' @noRd
CLIENT_LEGACY_VERSION <- "2025-11-25"

#' Connect to a remote MCP server
#'
#' @description
#' `mcp_client()` connects to an MCP server over Streamable HTTP, so a Shiny
#' app can host the server's apps with [mcp_host_server()] and
#' [mcp_chat_host()]. Any server works: an app deployed with
#' [mcp_endpoint()], a Shiny app served by Shiny's own MCP support, or a
#' server written in another language.
#'
#' The client speaks both generations of the protocol: the stateless
#' 2026-07-28 revision, and the `initialize` handshake of 2025-11-25 and
#' earlier. It tells the server it can show MCP Apps, and it keeps the
#' `_meta` of every result, which is where an app's page is declared.
#'
#' Nothing is sent until the client is first used.
#'
#' @section Credentials:
#' `headers` can be a function, called before each request. To send each
#' visitor's own credentials, create the client in the Shiny server
#' function, where the function can read the visitor's session. A client
#' created outside it is shared by every session, along with its
#' connection and the tool list it has read.
#'
#' Headers go wherever `url` points, so use `https://` for anything
#' secret.
#'
#' @param url The server's MCP endpoint, such as
#'   `"https://connect.example.com/sales/mcp"`.
#' @param headers Headers to send with every request, such as
#'   `Authorization`: a named list, or a function that returns one.
#' @param name A name for the server, unique among the sources a Shiny app
#'   hosts. Saved conversations refer to the server's apps by this name, so
#'   keep it stable. Defaults to the URL's host and path.
#' @param timeout Seconds to wait for each response. Apps that poll their
#'   server, as Shiny apps can, need this to be longer than their polls.
#' @return An [McpClient].
#' @family hosting
#' @export
#' @examples
#' \dontrun{
#' client <- mcp_client(
#'   "https://connect.example.com/sales/mcp",
#'   headers = list(Authorization = paste("Key", Sys.getenv("CONNECT_API_KEY")))
#' )
#' client$tools()
#' client$call_tool("open_sales_app", list(region = "West"))
#' }
mcp_client <- function(url, headers = NULL, name = NULL, timeout = 60) {
  McpClient$new(url = url, headers = headers, name = name, timeout = timeout)
}

#' A client for a remote MCP server
#'
#' @description
#' Made by [mcp_client()]. The methods below block until the server
#' answers and raise an error of class `shinymcp_error_client` when it
#' reports one. Each has an `_async` variant that returns a promise
#' instead, for use in Shiny.
#'
#' @export
McpClient <- R6::R6Class(
  "McpClient",
  cloneable = FALSE,
  public = list(
    #' @field url The server's endpoint.
    url = NULL,
    #' @field name The name hosts know the server by.
    name = NULL,
    #' @field timeout Seconds to wait for each response.
    timeout = NULL,

    #' @description Create a client. Use [mcp_client()].
    #' @param url,headers,name,timeout See [mcp_client()].
    #' @param transport For tests: a function taking a request (a list with
    #'   `method`, `url`, `headers`, `body`) and `async`, and returning a
    #'   response (`status`, `headers`, `body`) or a promise of one.
    initialize = function(
      url,
      headers = NULL,
      name = NULL,
      timeout = 60,
      transport = NULL
    ) {
      if (!is_string(url) || !grepl("^https?://", url, ignore.case = TRUE)) {
        shinymcp_abort(
          "{.arg url} must be an {.code http://} or {.code https://} URL.",
          class = "shinymcp_error_validation"
        )
      }
      if (
        !is.null(headers) &&
          !is.function(headers) &&
          !(is.list(headers) || is.character(headers))
      ) {
        shinymcp_abort(
          "{.arg headers} must be a named list, or a function returning one.",
          class = "shinymcp_error_validation"
        )
      }
      if (!is.numeric(timeout) || length(timeout) != 1 || timeout <= 0) {
        shinymcp_abort(
          "{.arg timeout} must be a positive number of seconds.",
          class = "shinymcp_error_validation"
        )
      }
      if (is.null(transport)) {
        rlang::check_installed(
          "httr2",
          reason = "to connect to MCP servers over HTTP."
        )
      }
      self$url <- url
      self$name <- name %||% client_default_name(url)
      self$timeout <- timeout
      private$headers <- headers
      private$transport <- transport %||% httr2_transport
      invisible(self)
    },

    #' @description The server's tools, from `tools/list`, with their
    #'   `_meta`. The list is kept for as long as the server says it may be,
    #'   or a minute.
    #' @param refresh Read the list again even if it is kept.
    #' @param wait `FALSE` to return the last list the client got, however
    #'   old, without asking the server: `NULL` if it has none.
    tools = function(refresh = FALSE, wait = TRUE) {
      if (!isTRUE(wait)) {
        return(private$tools_cache)
      }
      if (!refresh && private$tools_fresh()) {
        return(private$tools_cache)
      }
      private$store_tools(private$list_all_sync())
    },

    #' @description Call a tool.
    #' @param name Tool name.
    #' @param arguments Named list of arguments, sent as JSON. A vector of
    #'   one value goes as one value; write an array of one as `list(x)`.
    #' @return The `tools/call` result: a list with `content`, and possibly
    #'   `structuredContent`, `_meta`, and `isError`.
    call_tool = function(name, arguments = NULL) {
      self$request("tools/call", tool_call_params(name, arguments))
    },

    #' @description Read a resource, such as an app's `ui://` page.
    #' @param uri Resource URI.
    #' @return The `resources/read` result, a list with `contents`.
    read_resource = function(uri) {
      self$request("resources/read", list(uri = uri))
    },

    #' @description Send any request and return its result.
    #' @param method JSON-RPC method.
    #' @param params Named list of parameters.
    request = function(method, params = NULL) {
      client_result(self$send(client_message(method, params)), method)
    },

    #' @description Send a JSON-RPC request and return the whole response,
    #'   errors included, with the request's own id. Hosts use this to pass
    #'   an app's requests on.
    #' @param message A JSON-RPC request (a list).
    send = function(message) {
      private$connect_sync()
      private$exchange(message, async = FALSE)
    },

    #' @description `tools()`, returning a promise.
    #' @param refresh Read the list again even if it is kept.
    tools_async = function(refresh = FALSE) {
      check_promises()
      if (!refresh && private$tools_fresh()) {
        return(promises::promise_resolve(private$tools_cache))
      }
      promises::then(
        private$list_all_async(),
        function(tools) private$store_tools(tools)
      )
    },

    #' @description `call_tool()`, returning a promise.
    #' @param name Tool name.
    #' @param arguments Named list of arguments.
    call_tool_async = function(name, arguments = NULL) {
      self$request_async("tools/call", tool_call_params(name, arguments))
    },

    #' @description `read_resource()`, returning a promise.
    #' @param uri Resource URI.
    read_resource_async = function(uri) {
      self$request_async("resources/read", list(uri = uri))
    },

    #' @description `request()`, returning a promise.
    #' @param method JSON-RPC method.
    #' @param params Named list of parameters.
    request_async = function(method, params = NULL) {
      check_promises()
      promises::then(
        self$send_async(client_message(method, params)),
        function(response) client_result(response, method)
      )
    },

    #' @description `send()`, returning a promise.
    #' @param message A JSON-RPC request (a list).
    send_async = function(message) {
      check_promises()
      promises::then(
        private$connect_async(),
        function(...) private$exchange(message, async = TRUE)
      )
    },

    #' @description The protocol version in use, or `NULL` before the
    #'   first request.
    protocol_version = function() {
      private$version
    },

    #' @description What the server said about itself (`name`, `version`),
    #'   or `NULL` before the first request.
    server_info = function() {
      private$server
    },

    #' @description End the session, for servers that keep one. The next
    #'   request starts a new one.
    close = function() {
      session <- private$session_id
      private$reset()
      if (!is.null(session)) {
        try(
          private$perform(
            list(
              method = "DELETE",
              url = self$url,
              headers = c(
                private$user_headers(),
                list(`Mcp-Session-Id` = session)
              ),
              body = NULL
            ),
            async = FALSE
          ),
          silent = TRUE
        )
      }
      invisible(self)
    },

    #' @description Print a summary.
    #' @param ... Ignored.
    print = function(...) {
      cli::cat_line("<McpClient> ", self$name)
      cli::cat_line("  ", self$url)
      if (!is.null(private$version)) {
        cli::cat_line("  Protocol ", private$version)
      }
      invisible(self)
    }
  ),

  private = list(
    headers = NULL,
    transport = NULL,
    era = NULL,
    version = NULL,
    session_id = NULL,
    server = NULL,
    connecting = NULL,
    next_id = 0L,
    tools_cache = NULL,
    tools_expire = 0,

    reset = function() {
      private$era <- NULL
      private$version <- NULL
      private$session_id <- NULL
      private$connecting <- NULL
    },

    user_headers = function() {
      headers <- private$headers
      if (is.function(headers)) {
        headers <- headers()
      }
      headers <- as.list(headers %||% list())
      if (length(headers) && is.null(names(headers))) {
        shinymcp_abort(
          "{.arg headers} must be named.",
          class = "shinymcp_error_validation"
        )
      }
      lapply(headers, function(value) {
        paste(as.character(value), collapse = ", ")
      })
    },

    new_id = function() {
      private$next_id <- private$next_id + 1L
      paste0("shinymcp-", private$next_id)
    },

    perform = function(request, async) {
      private$transport(request, async = async, timeout = self$timeout)
    },

    # ---- Connecting ----

    connect_sync = function() {
      if (!is.null(private$era)) {
        return(invisible())
      }
      discovered <- tryCatch(
        private$exchange(private$discover_message(), async = FALSE, raw = TRUE),
        error = function(e) NULL
      )
      if (private$accept_discovery(discovered)) {
        return(invisible())
      }
      response <- private$exchange(
        private$initialize_message(),
        async = FALSE,
        raw = TRUE
      )
      private$accept_initialize(response)
      private$exchange(
        client_message("notifications/initialized", NULL, id = NULL),
        async = FALSE
      )
      invisible()
    },

    connect_async = function() {
      if (!is.null(private$era)) {
        return(promises::promise_resolve(TRUE))
      }
      if (!is.null(private$connecting)) {
        return(private$connecting)
      }
      handshake <- function(...) {
        promises::then(
          private$exchange(
            private$initialize_message(),
            async = TRUE,
            raw = TRUE
          ),
          function(response) {
            private$accept_initialize(response)
            private$exchange(
              client_message("notifications/initialized", NULL, id = NULL),
              async = TRUE
            )
          }
        )
      }
      discover <- promises::then(
        private$exchange(private$discover_message(), async = TRUE, raw = TRUE),
        onFulfilled = function(response) response,
        onRejected = function(e) NULL
      )
      connecting <- promises::then(discover, function(discovered) {
        if (private$accept_discovery(discovered)) TRUE else handshake()
      })
      connecting <- promises::then(
        connecting,
        onFulfilled = function(...) {
          private$connecting <- NULL
          TRUE
        },
        onRejected = function(e) {
          private$connecting <- NULL
          stop(e)
        }
      )
      private$connecting <- connecting
      connecting
    },

    discover_message = function() {
      client_message("server/discover", list(), id = private$new_id())
    },

    initialize_message = function() {
      client_message(
        "initialize",
        list(
          protocolVersion = CLIENT_LEGACY_VERSION,
          capabilities = client_capabilities(),
          clientInfo = client_info()
        ),
        id = private$new_id()
      )
    },

    # A server of the 2026-07-28 revision lists it in `server/discover`.
    accept_discovery = function(response) {
      result <- response$message$result
      versions <- as.character(unlist(result$supportedVersions))
      modern <- intersect(SHINYMCP_MODERN_VERSIONS, versions)
      if (length(modern) == 0) {
        return(FALSE)
      }
      private$era <- "modern"
      private$version <- modern[[1]]
      private$server <- result[["_meta"]][[META_SERVER_INFO]] %||%
        result$serverInfo
      TRUE
    },

    accept_initialize = function(response) {
      message <- response$message
      if (!is.null(message$error) || is.null(message$result)) {
        client_abort(
          message$error$message %||%
            "The server didn't answer {.code initialize}.",
          method = "initialize",
          error = message$error
        )
      }
      private$era <- "legacy"
      private$version <- message$result$protocolVersion %||%
        CLIENT_LEGACY_VERSION
      private$server <- message$result$serverInfo
      private$session_id <- response$headers[["mcp-session-id"]]
      invisible()
    },

    # ---- Requests ----

    # Send one message and read the response to it. Returns the JSON-RPC
    # response (with the message's own id), NULL for a notification, or,
    # with `raw = TRUE`, a list with the `message` and the HTTP `headers`.
    # A request whose session the server has forgotten is sent again in a
    # new session, once.
    exchange = function(message, async, raw = FALSE, retried = FALSE) {
      original_id <- message$id
      wire <- message
      if (!is.null(original_id)) {
        wire$id <- private$new_id()
      }
      if (identical(private$era, "modern")) {
        wire$params <- with_client_meta(wire$params, private$version)
      } else if (identical(message$method, "server/discover")) {
        wire$params <- with_client_meta(
          wire$params,
          SHINYMCP_MODERN_VERSIONS[[1]]
        )
      }
      request <- list(
        method = "POST",
        url = self$url,
        headers = private$request_headers(wire),
        body = charToRaw(enc2utf8(as.character(to_json(wire))))
      )
      finish <- function(response) {
        expired <- identical(as.integer(response$status), 404L) &&
          identical(private$era, "legacy") &&
          !is.null(private$session_id) &&
          !identical(message$method, "initialize")
        if (expired && !retried) {
          private$reset()
          if (async) {
            return(promises::then(private$connect_async(), function(...) {
              private$exchange(message, async = TRUE, raw = raw, retried = TRUE)
            }))
          }
          private$connect_sync()
          return(private$exchange(
            message,
            async = FALSE,
            raw = raw,
            retried = TRUE
          ))
        }
        if (is.null(original_id)) {
          return(NULL)
        }
        reply <- read_client_response(response, wire$id)
        reply$id <- original_id
        if (raw) {
          list(message = reply, headers = response$headers)
        } else {
          reply
        }
      }
      unreachable <- function(e) {
        if (inherits(e, "shinymcp_error_client")) {
          stop(e)
        }
        shinymcp_abort(
          c(
            "Couldn't reach the MCP server at {.url {self$url}}.",
            "x" = "{conditionMessage(e)}"
          ),
          class = "shinymcp_error_client",
          call = NULL
        )
      }
      if (async) {
        response <- tryCatch(
          private$perform(request, async = TRUE),
          error = function(e) promises::promise_reject(e)
        )
        return(promises::then(response, finish, onRejected = unreachable))
      }
      response <- tryCatch(
        private$perform(request, async = FALSE),
        error = unreachable
      )
      finish(response)
    },

    request_headers = function(message) {
      headers <- private$user_headers()
      headers$Accept <- "application/json, text/event-stream"
      headers$`Content-Type` <- "application/json"
      if (identical(private$era, "modern")) {
        headers$`MCP-Protocol-Version` <- private$version
        headers$`Mcp-Method` <- message$method
        target <- switch(
          message$method %||% "",
          "tools/call" = ,
          "prompts/get" = message$params$name,
          "resources/read" = message$params$uri,
          NULL
        )
        if (is_string(target)) {
          headers$`Mcp-Name` <- encode_header_value(target)
        }
      } else if (identical(private$era, "legacy")) {
        headers$`MCP-Protocol-Version` <- private$version
        if (!is.null(private$session_id)) {
          headers$`Mcp-Session-Id` <- private$session_id
        }
      } else if (identical(message$method, "server/discover")) {
        headers$`MCP-Protocol-Version` <- SHINYMCP_MODERN_VERSIONS[[1]]
        headers$`Mcp-Method` <- "server/discover"
      }
      headers
    },

    # ---- Tool lists ----

    tools_fresh = function() {
      !is.null(private$tools_cache) &&
        as.numeric(Sys.time()) < private$tools_expire
    },

    store_tools = function(listed) {
      private$tools_cache <- listed$tools
      ttl <- listed$ttl_ms %||% 60000
      private$tools_expire <- as.numeric(Sys.time()) + ttl / 1000
      private$tools_cache
    },

    list_all_sync = function() {
      tools <- list()
      cursor <- NULL
      ttl <- NULL
      repeat {
        result <- self$request(
          "tools/list",
          if (!is.null(cursor)) list(cursor = cursor)
        )
        tools <- c(tools, result$tools %||% list())
        ttl <- result$ttlMs %||% ttl
        cursor <- result$nextCursor
        if (!is_string(cursor)) break
      }
      list(tools = tools, ttl_ms = ttl)
    },

    list_all_async = function(cursor = NULL, tools = list(), ttl = NULL) {
      promises::then(
        self$request_async(
          "tools/list",
          if (!is.null(cursor)) list(cursor = cursor)
        ),
        function(result) {
          tools <- c(tools, result$tools %||% list())
          ttl <- result$ttlMs %||% ttl
          if (is_string(result$nextCursor)) {
            private$list_all_async(result$nextCursor, tools, ttl)
          } else {
            list(tools = tools, ttl_ms = ttl)
          }
        }
      )
    }
  )
)

#' The async methods return promises; check the package is there first
#' @noRd
check_promises <- function() {
  rlang::check_installed(
    "promises",
    reason = "to call MCP servers from Shiny."
  )
}

# ---- Messages ----

#' @noRd
client_message <- function(method, params = NULL, id = "shinymcp") {
  message <- list(jsonrpc = "2.0", id = id, method = method)
  if (is.null(id)) {
    message$id <- NULL
  }
  if (!is.null(params)) {
    message$params <- params
  }
  message
}

#' @noRd
tool_call_params <- function(name, arguments) {
  if (!is_string(name)) {
    shinymcp_abort(
      "{.arg name} must be a tool name.",
      class = "shinymcp_error_validation"
    )
  }
  list(name = name, arguments = arguments %||% json_object())
}

#' What the client tells servers it can do: show MCP Apps
#' @noRd
client_capabilities <- function() {
  extensions <- list()
  extensions[[SHINYMCP_UI_EXTENSION_ID]] <- list(
    mimeTypes = I(SHINYMCP_UI_MIME_TYPE)
  )
  list(extensions = extensions)
}

#' @noRd
client_info <- function() {
  list(
    name = "shinymcp",
    version = as.character(utils::packageVersion("shinymcp"))
  )
}

#' Add the 2026-07-28 `_meta` keys to a request's params
#'
#' Keys the request already has (an app's own `_meta`) are kept.
#' @noRd
with_client_meta <- function(params, version) {
  params <- params %||% list()
  meta <- params[["_meta"]] %||% list()
  meta[[META_PROTOCOL_VERSION]] <- version
  meta[[META_CLIENT_CAPABILITIES]] <- client_capabilities()
  meta[[META_CLIENT_INFO]] <- client_info()
  params[["_meta"]] <- meta
  params
}

#' Header values carry non-ASCII text as `=?base64?...?=`
#' @noRd
encode_header_value <- function(value) {
  if (!grepl("[^ -~]", value)) {
    return(value)
  }
  paste0("=?base64?", base64_raw(charToRaw(enc2utf8(value))), "?=")
}

#' @noRd
client_default_name <- function(url) {
  name <- sub("^[a-zA-Z]+://", "", url)
  name <- sub("[?#].*$", "", name)
  sub("/+$", "", name)
}

# ---- Responses ----

#' The JSON-RPC response to a request, from an HTTP response
#'
#' Servers answer with a JSON body, or an SSE stream whose events carry
#' JSON-RPC messages (notifications may come before the response). An HTTP
#' error without a JSON-RPC body becomes an internal error.
#' @noRd
read_client_response <- function(response, id) {
  status <- as.integer(response$status %||% 0L)
  body <- response$body %||% ""
  if (is.raw(body)) {
    body <- rawToChar(body)
  }
  Encoding(body) <- "UTF-8"
  type <- tolower(response$headers[["content-type"]] %||% "")
  messages <- if (startsWith(type, "text/event-stream")) {
    sse_messages(body)
  } else if (nzchar(trimws(body))) {
    parsed <- tryCatch(from_json(body), error = function(e) NULL)
    if (is.list(parsed) && is.null(names(parsed))) parsed else list(parsed)
  } else {
    list()
  }
  for (message in messages) {
    # A result can be null, so look for the field, not its value.
    if (
      is.list(message) &&
        identical(as.character(message$id), as.character(id)) &&
        any(c("result", "error") %in% names(message))
    ) {
      return(message)
    }
  }
  # An error the server sent without an id (it couldn't read ours).
  for (message in messages) {
    if (is.list(message) && !is.null(message$error)) {
      message$id <- id
      return(message)
    }
  }
  text <- if (status >= 400) {
    paste0("The server answered with HTTP status ", status, ".")
  } else {
    "The server's answer had no response to the request."
  }
  list(
    jsonrpc = "2.0",
    id = id,
    error = list(code = RPC_INTERNAL_ERROR, message = text)
  )
}

#' Parse the JSON-RPC messages in a server-sent event stream
#' @noRd
sse_messages <- function(text) {
  text <- gsub("\r\n?", "\n", text)
  events <- strsplit(text, "\n\n", fixed = TRUE)[[1]]
  out <- list()
  for (event in events) {
    lines <- strsplit(event, "\n", fixed = TRUE)[[1]]
    data <- lines[startsWith(lines, "data:")]
    if (length(data) == 0) {
      next
    }
    payload <- paste(sub("^data: ?", "", data), collapse = "\n")
    parsed <- tryCatch(from_json(payload), error = function(e) NULL)
    if (is.list(parsed)) {
      out[[length(out) + 1]] <- parsed
    }
  }
  out
}

#' The result of a response, or an error
#' @noRd
client_result <- function(response, method) {
  if (!is.null(response$error)) {
    client_abort(
      response$error$message %||% "The server reported an error.",
      method = method,
      error = response$error
    )
  }
  response$result
}

#' @noRd
client_abort <- function(message, method = NULL, error = NULL) {
  shinymcp_abort(
    c(
      "{.code {method}} failed.",
      "x" = "{message}"
    ),
    class = "shinymcp_error_client",
    rpc_error = error,
    call = NULL
  )
}

# ---- HTTP ----

#' Perform a request: with httr2, or, returning a promise, with curl
#'
#' Responses of every status are returned, not raised: an MCP error comes
#' with a JSON-RPC body the caller reads. Only failing to reach the server
#' is an error.
#' @noRd
httr2_transport <- function(request, async = FALSE, timeout = 60) {
  if (async) {
    return(curl_request_async(request, timeout))
  }
  req <- httr2::request(request$url)
  req <- httr2::req_method(req, request$method)
  req <- httr2::req_headers(req, !!!request$headers)
  if (!is.null(request$body)) {
    req <- httr2::req_body_raw(req, request$body, type = "application/json")
  }
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_user_agent(
    req,
    paste0("shinymcp/", utils::packageVersion("shinymcp"))
  )
  httr2_response(httr2::req_perform(req))
}

#' Perform a request with curl and return a promise of the response
#'
#' Each request has a pool of its own, driven from later: in a shared pool,
#' a request added while another waits (an app's long poll) isn't watched
#' until that one has news. httr2's req_perform_promise() isn't used
#' because it waits on its pool for curl's timeout read as seconds, though
#' curl gives milliseconds: a server that never answered was waited on for
#' hours, and the wait stayed on the event loop after the request ended.
#' @noRd
curl_request_async <- function(request, timeout = 60) {
  rlang::check_installed(
    c("promises", "later", "curl"),
    reason = "to call MCP servers from Shiny."
  )
  handle <- curl::new_handle(
    url = request$url,
    customrequest = request$method,
    timeout_ms = round(timeout * 1000),
    connecttimeout_ms = round(timeout * 1000),
    useragent = paste0("shinymcp/", utils::packageVersion("shinymcp"))
  )
  if (!is.null(request$body)) {
    curl::handle_setopt(handle, postfields = request$body)
  }
  if (length(request$headers)) {
    curl::handle_setheaders(
      handle,
      .list = lapply(request$headers, as.character)
    )
  }
  pool <- curl::new_pool()
  promises::promise(function(resolve, reject) {
    curl::multi_add(
      handle,
      done = function(res) resolve(curl_response(res)),
      fail = function(message) reject(simpleError(message)),
      pool = pool
    )
    poll <- function(...) {
      pending <- tryCatch(
        curl::multi_run(timeout = 0, pool = pool)$pending,
        error = function(e) {
          reject(e)
          0
        }
      )
      if (pending > 0) {
        fds <- curl::multi_fdset(pool = pool)
        # curl's wait is in milliseconds (-1 for none); look again at
        # least each second.
        ms <- fds$timeout %||% -1
        wait <- if (ms >= 0) min(ms / 1000, 1) else 1
        later::later_fd(
          poll,
          fds$reads,
          fds$writes,
          fds$exceptions,
          timeout = wait
        )
      }
    }
    poll()
  })
}

#' @noRd
curl_response <- function(res) {
  headers <- curl::parse_headers_list(res$headers)
  names(headers) <- tolower(names(headers))
  body <- rawToChar(res$content)
  Encoding(body) <- "UTF-8"
  list(status = res$status_code, headers = headers, body = body)
}

#' @noRd
httr2_response <- function(resp) {
  headers <- as.list(httr2::resp_headers(resp))
  names(headers) <- tolower(names(headers))
  list(
    status = httr2::resp_status(resp),
    headers = headers,
    body = if (httr2::resp_has_body(resp)) httr2::resp_body_string(resp) else ""
  )
}
