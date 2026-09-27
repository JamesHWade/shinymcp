# Tools: one internal shape for every way a tool can be written.
#
# Authors hand shinymcp ellmer tools (`ellmer::tool()`), plain lists
# (`list(name =, description =, inputSchema =, fun =)`), or, for apps served
# from Shiny, nothing at all: the live runtime makes its own tools. They are
# all normalized to a `shinymcp_tool` record when the app is created, so the
# server, the hosts, and the shinychat wrapper only deal with one shape.

#' @noRd
new_mcp_tool <- function(
  name,
  handler,
  description = "",
  title = NULL,
  input_schema = list(type = "object", properties = json_object()),
  output_schema = NULL,
  annotations = NULL,
  visibility = NULL,
  outputs = NULL,
  meta = NULL,
  source = "internal",
  original = NULL,
  fun = NULL
) {
  structure(
    list(
      name = name,
      description = description %||% "",
      title = title,
      input_schema = input_schema,
      output_schema = output_schema,
      annotations = annotations,
      visibility = visibility,
      outputs = outputs,
      meta = meta,
      handler = handler,
      source = source,
      original = original,
      fun = fun
    ),
    class = "shinymcp_tool"
  )
}

#' @noRd
is_mcp_tool <- function(x) {
  inherits(x, "shinymcp_tool")
}

#' Check if an object is an ellmer tool definition
#' @noRd
is_ellmer_tool <- function(x) {
  inherits(x, "ellmer::ToolDef")
}

#' Normalize a user-supplied tool
#'
#' @param x An ellmer tool, a plain-list tool, or a `shinymcp_tool`.
#' @param index Position in the tools list, for error messages.
#' @noRd
as_mcp_tool <- function(x, index = NULL, call = rlang::caller_env()) {
  if (is_mcp_tool(x)) {
    return(x)
  }
  if (is_ellmer_tool(x)) {
    return(mcp_tool_from_ellmer(x))
  }
  if (is.list(x) && !is.null(x$name)) {
    return(mcp_tool_from_list(x, call = call))
  }

  where <- if (!is.null(index)) paste0(" (tool ", index, ")") else ""
  shinymcp_abort(
    c(
      "Can't use an object of class {.cls {class(x)}} as a tool{where}.",
      "i" = "Use {.fn ellmer::tool} or a list with {.field name}, {.field description}, and {.field fun}."
    ),
    class = "shinymcp_error_validation",
    call = call
  )
}

#' @noRd
mcp_tool_from_ellmer <- function(tool) {
  annotations <- tool_annotations_list(ellmer_prop(tool, "annotations"))
  arguments <- ellmer_prop(tool, "arguments")
  types <- if (!is.null(arguments)) ellmer_prop(arguments, "properties")
  convert <- !identical(ellmer_prop(tool, "convert"), FALSE)
  input_schema <- ellmer_tool_input_schema(tool)

  new_mcp_tool(
    name = ellmer_prop(tool, "name"),
    description = ellmer_prop(tool, "description") %||% "",
    title = annotations$title,
    input_schema = input_schema,
    annotations = normalize_tool_annotations(annotations),
    handler = function(arguments, context) {
      args <- prepare_tool_arguments(
        arguments,
        schema = input_schema,
        types = types,
        fun = tool,
        convert = convert
      )
      do.call(tool, args)
    },
    source = "ellmer",
    original = tool,
    fun = tool
  )
}

#' @noRd
mcp_tool_from_list <- function(tool, call = rlang::caller_env()) {
  name <- tool$name
  if (!is.character(name) || length(name) != 1 || !nzchar(name)) {
    shinymcp_abort(
      "A tool's {.field name} must be a single non-empty string.",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  fun <- tool$fun
  if (!is.null(fun) && !is.function(fun)) {
    shinymcp_abort(
      "Tool {.val {name}}: {.field fun} must be a function.",
      class = "shinymcp_error_validation",
      call = call
    )
  }

  input_schema <- normalize_json_schema(
    tool$inputSchema %||%
      if (is.function(fun)) {
        schema_from_formals(fun)
      } else {
        list(type = "object", properties = json_object())
      }
  )
  annotations <- tool_annotations_list(tool$annotations)
  visibility <- tool$visibility
  if (!is.null(visibility)) {
    visibility <- validate_visibility(visibility, name, call = call)
  }

  handler <- if (is.function(fun)) {
    function(arguments, context) {
      args <- prepare_tool_arguments(
        arguments,
        schema = input_schema,
        fun = fun,
        convert = !identical(tool$convert, FALSE)
      )
      do.call(fun, args)
    }
  } else {
    function(arguments, context) {
      shinymcp_abort(
        "Tool {.val {name}} has no function to call.",
        class = "shinymcp_error_tool_not_callable"
      )
    }
  }

  new_mcp_tool(
    name = name,
    description = tool$description %||% "",
    title = tool$title %||% annotations$title,
    input_schema = input_schema,
    output_schema = tool$outputSchema,
    annotations = normalize_tool_annotations(annotations),
    visibility = visibility,
    outputs = tool$outputs %||% tool[[".output_ids"]],
    meta = tool[["_meta"]],
    handler = handler,
    source = "list",
    original = tool,
    fun = fun
  )
}

#' @noRd
validate_visibility <- function(visibility, name, call = rlang::caller_env()) {
  visibility <- unique(as.character(unlist(visibility)))
  if (length(visibility) == 0 || !all(visibility %in% c("model", "app"))) {
    shinymcp_abort(
      "Visibility for tool {.val {name}} must be drawn from {.val {c('model', 'app')}}.",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  visibility
}

#' @noRd
tool_annotations_list <- function(annotations) {
  if (length(annotations) == 0) {
    return(list())
  }
  as.list(annotations)
}

# MCP tool annotation hints use camelCase; ellmer's tool_annotations() uses
# snake_case. Map the known hints and pass through keys already in camelCase.
SHINYMCP_ANNOTATION_KEYS <- c(
  title = "title",
  read_only_hint = "readOnlyHint",
  destructive_hint = "destructiveHint",
  idempotent_hint = "idempotentHint",
  open_world_hint = "openWorldHint"
)

#' Normalize tool annotations to the MCP camelCase shape
#'
#' @param annotations A named list of hints (snake_case or camelCase).
#' @return A named list with MCP hint keys, or `NULL` if empty.
#' @noRd
normalize_tool_annotations <- function(annotations) {
  if (length(annotations) == 0) {
    return(NULL)
  }
  camel <- unname(SHINYMCP_ANNOTATION_KEYS)
  out <- list()
  for (nm in names(annotations)) {
    value <- annotations[[nm]]
    if (is.null(value)) {
      next
    }
    key <- if (nm %in% names(SHINYMCP_ANNOTATION_KEYS)) {
      SHINYMCP_ANNOTATION_KEYS[[nm]]
    } else if (nm %in% camel) {
      nm
    } else {
      next
    }
    out[[key]] <- value
  }
  if (length(out) == 0) NULL else out
}

#' The argument names a tool accepts, from its input schema
#' @noRd
tool_argument_names <- function(tool) {
  names(tool$input_schema$properties %||% list())
}

#' Is a tool visible to (callable by) a given audience?
#' @noRd
tool_visible_to <- function(tool, audience = c("model", "app")) {
  audience <- match.arg(audience)
  is.null(tool$visibility) || audience %in% tool$visibility
}

#' Serialize a tool for `tools/list`
#'
#' @param tool A `shinymcp_tool`.
#' @param resource_uri The app's `ui://` resource URI.
#' @param include_ui_meta Whether to include the nested `_meta.ui` block.
#' @param output_schema An outputSchema to use when the tool has none.
#' @noRd
tool_wire_definition <- function(
  tool,
  resource_uri,
  include_ui_meta = TRUE,
  output_schema = NULL
) {
  def <- compact_list(list(
    name = tool$name,
    title = tool$title,
    description = tool$description,
    inputSchema = tool$input_schema,
    outputSchema = tool$output_schema %||% output_schema,
    annotations = tool$annotations
  ))

  meta <- tool$meta %||% list()
  # The flat key is deprecated in the MCP Apps spec but still read by hosts
  # that predate capability negotiation; text-only clients ignore it.
  meta[["ui/resourceUri"]] <- resource_uri
  if (include_ui_meta) {
    ui <- list(resourceUri = resource_uri)
    if (!is.null(tool$visibility)) {
      ui$visibility <- I(tool$visibility)
    }
    meta$ui <- ui
  }
  def[["_meta"]] <- meta
  def
}

# ---- Request context ----

# The context of the request being handled, available to tool functions
# through mcp_request(). A stack so nested calls (a tool that calls another
# app's tool in-process) restore the outer context.
the <- new.env(parent = emptyenv())
the$request_stack <- list()

#' @noRd
with_request_context <- function(context, expr) {
  n <- length(the$request_stack)
  the$request_stack[[n + 1]] <- context
  on.exit(the$request_stack <- the$request_stack[seq_len(n)], add = TRUE)
  force(expr)
}

#' Information about the MCP request being handled
#'
#' Call `mcp_request()` inside a tool function, or inside the server function
#' of a Shiny app served with [as_mcp_app()], to learn who is calling and how.
#' Outside a request it returns `NULL`.
#'
#' The fields are:
#'
#' * `caller`: `"model"` when the model called the tool, `"app"` when the
#'   app's own UI did. Hosts don't report this, so the UI marks its own calls;
#'   treat it as a hint, not a security boundary.
#' * `user`, `groups`: the signed-in user and their groups when the server
#'   runs on Posit Connect, otherwise `NULL`.
#' * `client`: the client's name and version, when it reported them.
#' * `protocol_version`: the MCP protocol version of the request.
#' * `transport`: `"stdio"`, `"http"`, or `"in-process"`.
#' * `headers`: HTTP request headers (lowercase names), for the HTTP transport.
#'
#' @return A list, or `NULL` outside a request.
#' @family runtime helpers
#' @export
#' @examples
#' greet <- function(name = "world") {
#'   who <- mcp_request()$user %||% "someone"
#'   paste0("Hello, ", name, "! (asked by ", who, ")")
#' }
mcp_request <- function() {
  n <- length(the$request_stack)
  if (n == 0) NULL else the$request_stack[[n]]
}
