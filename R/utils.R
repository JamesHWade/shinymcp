# Internal utilities for shinymcp

#' Read a package file from inst/
#' @param ... Path components relative to inst/
#' @noRd
system_file <- function(...) {
  system.file(..., package = "shinymcp", mustWork = TRUE)
}

#' Generate a unique ID
#' @param prefix Optional prefix
#' @noRd
unique_id <- function(prefix = "shinymcp") {
  paste0(
    prefix,
    "-",
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "-",
    sample(1000:9999, 1)
  )
}

#' Convert an R object to JSON
#' @param x Object to convert
#' @param pretty Whether to pretty-print
#' @noRd
to_json <- function(x, pretty = FALSE) {
  jsonlite::toJSON(x, auto_unbox = TRUE, pretty = pretty, null = "null")
}

#' Parse JSON string
#' @param x JSON string
#' @noRd
from_json <- function(x) {
  jsonlite::fromJSON(x, simplifyVector = FALSE)
}

#' Encode content as base64
#' @param raw_content Raw bytes to encode
#' @noRd
base64_encode <- function(raw_content) {
  rlang::check_installed("base64enc", reason = "for base64 encoding")
  base64enc::base64encode(raw_content)
}

#' Check if an object is an ellmer ToolDef (S7)
#' @param x Object to check
#' @noRd
is_ellmer_tool <- function(x) {
  inherits(x, "ellmer::ToolDef")
}

#' Get the name of a tool (ellmer S7 or plain list)
#' @param tool A tool object
#' @noRd
tool_name <- function(tool) {
  if (is_ellmer_tool(tool)) {
    tool@name %||% "unnamed"
  } else if (is.list(tool)) {
    tool$name %||% "unnamed"
  } else {
    "unnamed"
  }
}

#' Build a JSON-ready input schema from an ellmer TypeObject
#' @param arguments An ellmer TypeObject (tool@@arguments)
#' @noRd
type_object_to_schema <- function(arguments) {
  props <- arguments@properties
  schema <- list(
    type = "object",
    properties = lapply(props, function(p) {
      compact_list(list(
        type = p@type,
        description = if (nzchar(p@description %||% "")) p@description
      ))
    })
  )
  required <- names(props)[vapply(
    props,
    function(p) isTRUE(p@required),
    logical(1)
  )]
  if (length(required) > 0) {
    schema$required <- as.list(required)
  }
  schema
}

#' Remove NULL entries from a list
#' @param x A list
#' @noRd
compact_list <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}

#' Core MCP protocol versions supported by the server transport, newest first
#' @noRd
SHINYMCP_SUPPORTED_PROTOCOL_VERSIONS <- c(
  "2025-11-25",
  "2025-06-18",
  "2025-03-26",
  "2024-11-05"
)

#' Latest core MCP protocol version supported by shinymcp
#' @noRd
SHINYMCP_PROTOCOL_VERSION <- SHINYMCP_SUPPORTED_PROTOCOL_VERSIONS[[1]]

#' MCP Apps extension spec version implemented by the JS bridge and hosts
#' @noRd
SHINYMCP_APPS_PROTOCOL_VERSION <- "2026-01-26"

#' Extension identifier clients use to advertise MCP Apps support
#' @noRd
SHINYMCP_UI_EXTENSION_ID <- "io.modelcontextprotocol/ui"

#' Required MIME type for ui:// resources per the MCP Apps spec
#' @noRd
SHINYMCP_UI_MIME_TYPE <- "text/html;profile=mcp-app"

SHINYMCP_SINGLE_RESULT_KEY <- "__shinymcp_result__"

#' Negotiate the core MCP protocol version with a client
#'
#' Per the MCP spec: if the client requests a version the server supports,
#' echo it back; otherwise respond with the server's latest supported version.
#'
#' @param requested The client's requested protocol version (or NULL).
#' @noRd
negotiate_protocol_version <- function(requested) {
  if (
    is.character(requested) &&
      length(requested) == 1 &&
      requested %in% SHINYMCP_SUPPORTED_PROTOCOL_VERSIONS
  ) {
    return(requested)
  }
  SHINYMCP_PROTOCOL_VERSION
}

#' Check whether an initialize request advertises MCP Apps support
#'
#' Per the MCP Apps spec (2026-01-26), clients advertise support via
#' `capabilities.extensions["io.modelcontextprotocol/ui"]` with a `mimeTypes`
#' array. A missing `mimeTypes` field is treated leniently as supporting the
#' default HTML profile.
#'
#' @param params The `params` of an `initialize` request.
#' @return `TRUE` if the client supports MCP Apps UI rendering.
#' @noRd
client_supports_mcp_apps <- function(params) {
  ui_cap <- params$capabilities$extensions[[SHINYMCP_UI_EXTENSION_ID]]
  if (is.null(ui_cap)) {
    return(FALSE)
  }
  mime_types <- unlist(ui_cap$mimeTypes, use.names = FALSE)
  if (is.null(mime_types)) {
    return(TRUE)
  }
  SHINYMCP_UI_MIME_TYPE %in% mime_types
}

#' Convert user-facing CSP declarations to spec _meta.ui.csp keys
#'
#' Accepts snake_case keys (`connect_domains`, `resource_domains`,
#' `frame_domains`, `base_uri_domains`) or the spec's camelCase keys
#' directly. Values are coerced to character vectors and always serialized
#' as JSON arrays.
#'
#' @param csp A named list of CSP domain declarations, or NULL.
#' @noRd
csp_to_meta <- function(csp) {
  if (is.null(csp)) {
    return(NULL)
  }
  if (!is.list(csp) || is.null(names(csp)) || any(!nzchar(names(csp)))) {
    rlang::abort(
      "`csp` must be a fully named list of domain declarations.",
      class = "shinymcp_error_validation"
    )
  }
  key_map <- c(
    connect_domains = "connectDomains",
    resource_domains = "resourceDomains",
    frame_domains = "frameDomains",
    base_uri_domains = "baseUriDomains"
  )
  allowed <- unique(c(names(key_map), unname(key_map)))
  out <- list()
  for (nm in names(csp)) {
    if (!nm %in% allowed) {
      rlang::abort(
        cli::format_inline(
          "Unknown {.arg csp} field {.val {nm}}. Allowed: {.val {allowed}}."
        ),
        class = "shinymcp_error_validation"
      )
    }
    key <- if (nm %in% names(key_map)) key_map[[nm]] else nm
    out[[key]] <- I(as.character(csp[[nm]]))
  }
  out
}

#' Normalize user-supplied extra resources for an McpApp
#'
#' Accepts a named list (URI -> spec) where each spec is a string (static
#' content), a function returning a string, or a list with `content`,
#' `mime_type`, `name`, `description`, and `meta` fields. Returns a named
#' list of normalized specs with `uri`, `name`, `description`, `mime_type`,
#' `content_fn`, and `meta`.
#'
#' @param resources Named list of resource specs, or NULL.
#' @noRd
normalize_extra_resources <- function(resources) {
  if (is.null(resources)) {
    return(list())
  }
  if (
    !is.list(resources) ||
      is.null(names(resources)) ||
      any(!nzchar(names(resources)))
  ) {
    rlang::abort(
      "`resources` must be a fully named list (URI -> content).",
      class = "shinymcp_error_validation"
    )
  }

  out <- list()
  for (uri in names(resources)) {
    spec <- resources[[uri]]

    if (is.function(spec)) {
      spec <- list(content = spec)
    } else if (is.character(spec) && length(spec) == 1) {
      spec <- list(content = spec)
    } else if (!is.list(spec)) {
      rlang::abort(
        cli::format_inline(
          "Resource {.val {uri}} must be a string, a function, or a list with a {.field content} field."
        ),
        class = "shinymcp_error_validation"
      )
    }

    content <- spec$content
    content_fn <- if (is.function(content)) {
      content
    } else if (is.character(content) && length(content) == 1) {
      local({
        static <- content
        function() static
      })
    } else {
      rlang::abort(
        cli::format_inline(
          "Resource {.val {uri}} needs {.field content} as a single string or a function returning one."
        ),
        class = "shinymcp_error_validation"
      )
    }

    out[[uri]] <- list(
      uri = uri,
      name = spec$name %||% uri,
      description = spec$description %||% "",
      mime_type = spec$mime_type %||% "text/plain",
      content_fn = content_fn,
      meta = spec$meta
    )
  }
  out
}

#' Coerce resource content to a plain character scalar
#'
#' Content functions commonly return `jsonlite::toJSON()` output, which is a
#' `json`-classed object that downstream serializers (jsonlite, Shiny's
#' custom messages) inline as raw JSON instead of a string — breaking
#' `JSON.parse(contents[0].text)` in the app. Strip classes and collapse
#' multi-line character vectors so `text` is always a single string.
#'
#' @param content The value returned by a resource content function.
#' @noRd
coerce_resource_text <- function(content) {
  content <- as.character(content)
  if (length(content) != 1) {
    content <- paste(content, collapse = "\n")
  }
  content
}

#' Build an outputSchema from declared output ids and scanned UI types
#'
#' All shinymcp structured outputs travel as strings (text, HTML fragments,
#' base64 PNGs), so every property is `type: "string"` with a description
#' derived from the output's UI type.
#'
#' @param output_ids Character vector of output ids the tool returns.
#' @param ui_output_types Named character vector mapping output id -> UI type
#'   (`"text"`, `"plot"`, `"table"`, `"html"`), as scanned from the UI.
#' @noRd
build_output_schema <- function(output_ids, ui_output_types = character(0)) {
  if (length(output_ids) == 0) {
    return(NULL)
  }
  descriptions <- c(
    text = "Text content for output '%s'",
    plot = "Base64-encoded PNG image for output '%s'",
    table = "HTML table markup for output '%s'",
    html = "HTML markup for output '%s'"
  )
  properties <- list()
  for (id in output_ids) {
    type <- if (id %in% names(ui_output_types)) {
      ui_output_types[[id]]
    } else {
      NA_character_
    }
    template <- if (!is.na(type) && type %in% names(descriptions)) {
      descriptions[[type]]
    } else {
      "Value for output '%s'"
    }
    properties[[id]] <- list(
      type = "string",
      description = sprintf(template, id)
    )
  }
  list(
    type = "object",
    properties = properties,
    required = as.list(output_ids)
  )
}

#' Format an R tool result into the MCP tool-result shape
#'
#' Used by both the MCP server (`serve.R`) and the preview host (`preview.R`)
#' to produce a consistent response structure.
#'
#' @param result The raw result from `McpApp$call_tool()`.
#' @return A list with `content` and optionally `structuredContent`.
#' @noRd
format_tool_result <- function(result) {
  if (is_mcp_result(result)) {
    return(list(
      content = list(list(
        type = "text",
        text = mcp_result_text_fallback(result)
      )),
      structuredContent = setNames(
        list(mcp_result_wire_payload(result)),
        SHINYMCP_SINGLE_RESULT_KEY
      )
    ))
  }

  if (is.list(result) && !is.null(names(result))) {
    text_summary <- mcp_result_text_fallback(result)
    payload <- list(
      content = list(list(type = "text", text = text_summary))
    )
    structured <- mcp_result_structured_content(result)
    if (!is.null(structured)) {
      payload$structuredContent <- structured
    }
    return(payload)
  }

  list(
    content = list(list(type = "text", text = as.character(result)))
  )
}
