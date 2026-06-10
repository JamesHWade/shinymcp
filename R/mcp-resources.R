# Resource protocol handler for MCP ui:// resources
#
# Handles JSON-RPC messages for the resources protocol since mcptools
# doesn't support resources yet. Designed as a cleanly extractable module
# for eventual upstream PR to mcptools.

# ---- ResourceRegistry R6 Class ----

#' Registry for MCP resources
#'
#' Manages resource declarations and content retrieval for MCP ui:// resources.
#'
#' @noRd
ResourceRegistry <- R6::R6Class(
  "ResourceRegistry",
  public = list(
    #' @description Create a new ResourceRegistry
    initialize = function() {
      private$.resources <- list()
      invisible(self)
    },

    #' @description Register a resource
    #' @param uri Resource URI (e.g. "ui://app-name")
    #' @param name Display name for the resource
    #' @param description Description of the resource
    #' @param mime_type MIME type of the resource content
    #' @param content_fn Function that returns the content string
    #' @param meta Optional `_meta` list attached to the resource declaration
    #'   and its contents (e.g. `list(ui = list(csp = ..., prefersBorder = TRUE))`
    #'   per the MCP Apps spec)
    register = function(
      uri,
      name,
      description,
      mime_type,
      content_fn,
      meta = NULL
    ) {
      if (!is.character(uri) || length(uri) != 1) {
        cli::cli_abort("{.arg uri} must be a single string.")
      }
      if (!is.function(content_fn)) {
        cli::cli_abort("{.arg content_fn} must be a function.")
      }
      if (!is.null(meta) && (!is.list(meta) || is.null(names(meta)))) {
        cli::cli_abort("{.arg meta} must be a named list or NULL.")
      }

      private$.resources[[uri]] <- list(
        uri = uri,
        name = name,
        description = description,
        mimeType = mime_type,
        content_fn = content_fn,
        meta = meta
      )

      invisible(self)
    },

    #' @description List all registered resources
    #' @return A list of resource declarations (without content functions)
    list_resources = function() {
      unname(lapply(private$.resources, function(r) {
        compact_list(list(
          uri = r$uri,
          name = r$name,
          description = r$description,
          mimeType = r$mimeType,
          `_meta` = r$meta
        ))
      }))
    },

    #' @description Read a resource by URI
    #' @param uri The resource URI to read
    #' @return A list with uri, mimeType, text content, and optional `_meta`
    read_resource = function(uri) {
      resource <- private$.resources[[uri]]
      if (is.null(resource)) {
        shinymcp_error_resource(
          cli::format_inline("Resource not found: {.val {uri}}"),
          uri = uri
        )
      }

      content <- coerce_resource_text(resource$content_fn())

      compact_list(list(
        uri = resource$uri,
        mimeType = resource$mimeType,
        text = content,
        `_meta` = resource$meta
      ))
    }
  ),
  private = list(
    .resources = list()
  )
)


# ---- JSON-RPC helpers ----

#' Create a JSON-RPC 2.0 response
#' @param id Request ID
#' @param result Result object
#' @noRd
jsonrpc_response <- function(id, result) {
  list(
    jsonrpc = "2.0",
    id = id,
    result = result
  )
}

#' Create a JSON-RPC 2.0 error response
#' @param id Request ID
#' @param code Error code
#' @param message Error message
#' @noRd
jsonrpc_error <- function(id, code, message) {
  list(
    jsonrpc = "2.0",
    id = id,
    error = list(
      code = code,
      message = message
    )
  )
}


# ---- Resource message handlers ----

#' Handle MCP resource protocol messages
#'
#' Routes JSON-RPC resource messages to appropriate handlers.
#' Designed as a cleanly extractable module for eventual upstream PR to mcptools.
#'
#' @param message A parsed JSON-RPC message (list)
#' @param registry A ResourceRegistry object
#' @return A JSON-RPC response list, or NULL if not a resource message
#' @noRd
handle_resource_message <- function(message, registry) {
  method <- message$method
  if (is.null(method) || !grepl("^resources/", method)) {
    return(NULL)
  }

  switch(
    method,
    "resources/list" = handle_resources_list(message, registry),
    "resources/read" = handle_resources_read(message, registry),
    jsonrpc_error(message$id, -32601, paste("Unknown method:", method))
  )
}

#' Handle resources/list request
#' @param message Parsed JSON-RPC message
#' @param registry ResourceRegistry object
#' @noRd
handle_resources_list <- function(message, registry) {
  resources <- registry$list_resources()
  jsonrpc_response(message$id, list(resources = resources))
}

#' Handle resources/read request
#' @param message Parsed JSON-RPC message
#' @param registry ResourceRegistry object
#' @noRd
handle_resources_read <- function(message, registry) {
  uri <- message$params$uri
  if (is.null(uri)) {
    return(jsonrpc_error(message$id, -32602, "Missing required parameter: uri"))
  }

  tryCatch(
    {
      content <- registry$read_resource(uri)
      jsonrpc_response(
        message$id,
        list(
          contents = list(content)
        )
      )
    },
    shinymcp_error_resource = function(e) {
      jsonrpc_error(message$id, -32002, e$message)
    }
  )
}
