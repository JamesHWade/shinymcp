# JSON Schema for tool inputs and outputs.
#
# Tools reach MCP clients as JSON Schema. ellmer describes arguments with its
# own type objects, plain-list tools carry a schema already, and apps served
# from Shiny derive one from the rendered inputs. Everything funnels through
# the helpers here so the wire shape is the same whichever way a tool was
# written.

#' An empty JSON object
#'
#' `list()` serializes as `[]`; MCP needs `{}` for empty objects.
#' @noRd
json_object <- function() {
  setNames(list(), character(0))
}

#' Convert an ellmer type to JSON Schema
#'
#' Handles the ellmer type classes that can appear in tool arguments: basic
#' scalars, enums, arrays, objects, and raw JSON Schema. Optional arguments
#' (`required = FALSE`) are left out of the parent object's `required` list.
#'
#' @param type An ellmer type object.
#' @return A named list ready for `jsonlite::toJSON(auto_unbox = TRUE)`.
#' @noRd
ellmer_type_schema <- function(type) {
  cls <- class(type)[[1]]
  description <- ellmer_prop(type, "description")
  description <- if (length(description) && nzchar(description)) description

  schema <- switch(
    cls,
    "ellmer::TypeBasic" = list(type = ellmer_prop(type, "type")),
    "ellmer::TypeEnum" = list(
      type = "string",
      enum = I(as.character(ellmer_prop(type, "values")))
    ),
    "ellmer::TypeArray" = list(
      type = "array",
      items = ellmer_type_schema(ellmer_prop(type, "items"))
    ),
    "ellmer::TypeObject" = ellmer_object_schema(type),
    "ellmer::TypeJsonSchema" = {
      json <- ellmer_prop(type, "json")
      if (is.character(json)) from_json(json) else json
    },
    list(type = "string")
  )

  if (!is.null(description) && is.null(schema$description)) {
    schema$description <- description
  }
  schema
}

#' @noRd
ellmer_object_schema <- function(type) {
  props <- ellmer_prop(type, "properties")
  props <- Filter(function(p) !inherits(p, "ellmer::TypeIgnore"), props)

  schema <- list(
    type = "object",
    properties = if (length(props)) {
      lapply(props, ellmer_type_schema)
    } else {
      json_object()
    }
  )
  required <- names(props)[vapply(
    props,
    function(p) isTRUE(ellmer_prop(p, "required")),
    logical(1)
  )]
  if (length(required)) {
    schema$required <- I(required)
  }
  if (identical(ellmer_prop(type, "additional_properties"), FALSE)) {
    schema$additionalProperties <- FALSE
  }
  schema
}

#' Read a property from an ellmer S7 object without importing S7
#' @noRd
ellmer_prop <- function(x, name) {
  tryCatch(methods::slot(x, name), error = function(e) NULL)
}

#' Input schema for an ellmer tool
#'
#' Only the top-level `properties` and `required` are taken from the
#' arguments object; the schema always has `type: "object"`.
#' @noRd
ellmer_tool_input_schema <- function(tool) {
  arguments <- ellmer_prop(tool, "arguments")
  if (is.null(arguments)) {
    return(list(type = "object", properties = json_object()))
  }
  schema <- ellmer_object_schema(arguments)
  schema$additionalProperties <- NULL
  schema
}

#' Guess an input schema from a function's formals
#'
#' Used for plain-list tools that give a function but no `inputSchema`. A
#' default value suggests the type; arguments without defaults are strings.
#' @noRd
schema_from_formals <- function(fun) {
  frmls <- formals(fun)
  frmls <- frmls[names(frmls) != "..."]
  props <- lapply(names(frmls), function(nm) {
    default <- frmls[[nm]]
    type <- if (rlang::is_missing(default) || is.null(default)) {
      "string"
    } else if (is.logical(default)) {
      "boolean"
    } else if (is.numeric(default)) {
      if (is.integer(default)) "integer" else "number"
    } else {
      "string"
    }
    list(type = type)
  })
  names(props) <- names(frmls)
  required <- names(frmls)[vapply(frmls, rlang::is_missing, logical(1))]
  compact_list(list(
    type = "object",
    properties = if (length(props)) props else json_object(),
    required = if (length(required)) I(required)
  ))
}

#' Make a user-supplied schema safe to serialize
#'
#' Plain-list tools write schemas by hand, often with `list()` for an empty
#' `properties` object or a bare string for a one-element `required`. Fix
#' those so they serialize as JSON objects and arrays.
#' @noRd
normalize_json_schema <- function(schema) {
  if (!is.list(schema)) {
    return(schema)
  }
  # Keys are matched exactly: `$` would read `enumNames` as `enum`. An
  # object's type may be nullable (`type = list("object", "null")`), or left
  # out of a subschema that gives `properties`.
  object <- "object" %in%
    as.character(unlist(schema[["type"]])) ||
    !is.null(schema[["properties"]])
  if (object) {
    if (length(schema[["properties"]]) == 0) {
      schema[["properties"]] <- json_object()
    } else {
      schema[["properties"]] <- lapply(
        schema[["properties"]],
        normalize_json_schema
      )
    }
    if (!is.null(schema[["required"]])) {
      schema[["required"]] <- I(as.character(unlist(schema[["required"]])))
    }
  }
  if (!is.null(schema[["enum"]])) {
    schema[["enum"]] <- I(unlist(schema[["enum"]]))
  }
  # Every other keyword that holds schemas: one, a list, or a map of them.
  for (key in intersect(names(schema), SCHEMA_KEYWORDS)) {
    value <- schema[[key]]
    # `items` could also be a list of schemas before JSON Schema 2020-12.
    tuple <- is.list(value) && length(value) > 0 && is.null(names(value))
    if (!is.null(value)) {
      schema[[key]] <- if (tuple) {
        lapply(value, normalize_json_schema)
      } else {
        normalize_json_schema(value)
      }
    }
  }
  for (key in intersect(names(schema), SCHEMA_LIST_KEYWORDS)) {
    if (!is.null(schema[[key]])) {
      schema[[key]] <- lapply(schema[[key]], normalize_json_schema)
    }
  }
  for (key in intersect(names(schema), SCHEMA_MAP_KEYWORDS)) {
    if (length(schema[[key]]) == 0) {
      schema[[key]] <- json_object()
    } else {
      schema[[key]] <- lapply(schema[[key]], normalize_json_schema)
    }
  }
  schema
}

SCHEMA_KEYWORDS <- c(
  "items",
  "additionalItems",
  "additionalProperties",
  "unevaluatedItems",
  "unevaluatedProperties",
  "propertyNames",
  "contains",
  "not",
  "if",
  "then",
  "else"
)
SCHEMA_LIST_KEYWORDS <- c("allOf", "anyOf", "oneOf", "prefixItems")
SCHEMA_MAP_KEYWORDS <- c(
  "patternProperties",
  "dependentSchemas",
  "$defs",
  "definitions"
)

#' Convert JSON Schema properties to ellmer types
#'
#' The reverse direction, used when a plain-list tool is registered with
#' ellmer (for example by [as_shinychat_tool()]).
#' @noRd
schema_to_ellmer_types <- function(schema) {
  rlang::check_installed("ellmer", reason = "to build ellmer tool arguments")
  props <- schema$properties %||% list()
  required <- as.character(unlist(schema$required))
  types <- lapply(names(props), function(nm) {
    json_schema_to_ellmer_type(props[[nm]], required = nm %in% required)
  })
  names(types) <- names(props)
  types
}

#' @noRd
json_schema_to_ellmer_type <- function(prop, required = TRUE) {
  description <- prop$description %||% ""
  type <- prop$type %||% if (!is.null(prop$enum)) "string" else "string"
  if (length(type) > 1) {
    type <- setdiff(unlist(type), "null")[1] %||% "string"
  }
  if (!is.null(prop$enum)) {
    return(ellmer::type_enum(
      as.character(unlist(prop$enum)),
      description = description,
      required = required
    ))
  }
  switch(
    type,
    number = ellmer::type_number(description, required = required),
    integer = ellmer::type_integer(description, required = required),
    boolean = ellmer::type_boolean(description, required = required),
    array = ellmer::type_array(
      json_schema_to_ellmer_type(prop$items %||% list(type = "string")),
      description = description,
      required = required
    ),
    object = {
      if (length(prop$properties)) {
        inner <- schema_to_ellmer_types(prop)
        rlang::exec(
          ellmer::type_object,
          .description = description,
          !!!inner,
          .required = required
        )
      } else {
        # A free-form object. ellmer's type_object() with no properties
        # describes one, and unlike type_from_schema() it takes `required`.
        ellmer::type_object(.description = description, .required = required)
      }
    },
    ellmer::type_string(description, required = required)
  )
}

# ---- Argument conversion ----

#' Prepare JSON-decoded arguments for an R tool function
#'
#' Arguments arrive as parsed JSON (`simplifyVector = FALSE`), so a JSON array
#' of strings is an R list. This mirrors what ellmer does before invoking a
#' tool: arrays of scalars become atomic vectors, arrays of objects become
#' data frames, integers become integers. `null` arguments are dropped so the
#' function's own defaults apply, and arguments the function cannot accept
#' are dropped rather than raising "unused argument".
#'
#' @param arguments Named list of arguments.
#' @param schema The tool's JSON Schema, used when `types` is NULL.
#' @param types Optional named list of ellmer types (ellmer tools).
#' @param fun The function that will be called, for its formals.
#' @param convert Whether to convert values (ellmer's `convert` flag).
#' @noRd
prepare_tool_arguments <- function(
  arguments,
  schema = NULL,
  types = NULL,
  fun = NULL,
  convert = TRUE,
  check = FALSE,
  check_types = TRUE
) {
  if (is.null(arguments) || length(arguments) == 0) {
    if (isTRUE(check)) {
      check_tool_arguments(list(), schema, fun = fun, types = FALSE)
    }
    return(list())
  }
  if (is.null(names(arguments)) || any(!nzchar(names(arguments)))) {
    shinymcp_abort(
      "Tool arguments must be a JSON object with named fields.",
      class = "shinymcp_error_arguments"
    )
  }
  arguments <- arguments[!vapply(arguments, is.null, logical(1))]
  # Converting loses whether a value was an array (`["a"]` and `"a"` both
  # become "a"), so arrays and objects are checked as they came.
  sent <- arguments

  if (isTRUE(convert)) {
    for (nm in names(arguments)) {
      if (!is.null(types[[nm]])) {
        arguments[[nm]] <- convert_with_ellmer_type(
          arguments[[nm]],
          types[[nm]]
        )
      } else if (!is.null(schema$properties[[nm]])) {
        arguments[[nm]] <- convert_with_schema(
          arguments[[nm]],
          schema$properties[[nm]]
        )
      } else {
        arguments[[nm]] <- simplify_json_value(arguments[[nm]])
      }
    }
  }

  if (isTRUE(check)) {
    check_tool_arguments(
      arguments,
      schema,
      fun = fun,
      types = isTRUE(convert) && isTRUE(check_types),
      sent = sent
    )
  }

  if (is.function(fun) && !is.primitive(fun)) {
    accepted <- names(formals(fun))
    if (!"..." %in% accepted) {
      arguments <- arguments[names(arguments) %in% accepted]
    }
  }
  arguments
}

#' Check a model's arguments against a tool's input schema
#'
#' Required arguments the function has no default for must be present, and
#' top-level values must have the schema's type and, for enums, one of its
#' values. The error goes back to the model as a tool error, so it can
#' correct the call.
#' @param types Whether to check types: not for tools that take raw JSON,
#'   nor for schemas guessed from a function's defaults.
#' @param sent The arguments before conversion, for checking arrays and
#'   objects.
#' @noRd
check_tool_arguments <- function(
  arguments,
  schema,
  fun = NULL,
  types = TRUE,
  sent = arguments
) {
  if (is.null(schema)) {
    return(invisible())
  }
  required <- as.character(unlist(schema$required))
  if (is.function(fun) && !is.primitive(fun)) {
    defaults <- formals(fun)
    has_default <- names(defaults)[
      !vapply(defaults, rlang::is_missing, logical(1))
    ]
    required <- setdiff(required, has_default)
  }
  missing <- setdiff(required, names(arguments))
  if (length(missing)) {
    shinymcp_abort(
      "Missing required argument{?s}: {.arg {missing}}.",
      class = "shinymcp_error_arguments"
    )
  }
  if (!types) {
    return(invisible())
  }
  for (nm in intersect(names(arguments), names(schema$properties))) {
    problem <- argument_problem(
      arguments[[nm]],
      schema$properties[[nm]],
      sent = sent[[nm]]
    )
    if (!is.null(problem)) {
      shinymcp_abort(
        "{.arg {nm}} must be {problem}.",
        class = "shinymcp_error_arguments"
      )
    }
  }
  invisible()
}

#' @noRd
argument_problem <- function(x, prop, sent = x) {
  type <- setdiff(as.character(unlist(prop$type)), "null")
  allowed <- unlist(prop$enum)
  if (length(allowed) && is.atomic(x) && length(x) == 1) {
    if (!as.character(x) %in% as.character(allowed)) {
      shown <- utils::head(allowed, 10)
      return(paste0(
        "one of ",
        paste0("\"", shown, "\"", collapse = ", "),
        if (length(allowed) > 10) ", ..."
      ))
    }
    return(NULL)
  }
  if (length(type) != 1) {
    return(NULL)
  }
  scalar <- is.atomic(x) && length(x) == 1 && !is.na(x)
  switch(
    type,
    string = if (!(is.character(x) && length(x) == 1)) "a string",
    number = if (!(scalar && is.numeric(x))) "a number",
    integer = if (!(scalar && is.numeric(x) && x == round(x))) "a whole number",
    boolean = if (!(scalar && is.logical(x))) "true or false",
    array = if (!is_array_argument(sent)) "an array",
    object = if (!is_object_argument(sent)) "an object",
    NULL
  )
}

#' Is an argument a JSON array, or an object, as it was sent?
#'
#' Parsed JSON has arrays as unnamed lists and objects as named ones. A
#' value from R counts as jsonlite would send it: a vector of other than one
#' value, a data frame, or an `I()` value is an array; one value alone isn't.
#' @noRd
is_array_argument <- function(x) {
  if (is.data.frame(x)) {
    return(TRUE)
  }
  if (is.list(x)) {
    return(is.null(names(x)))
  }
  is.atomic(x) && (length(x) != 1 || inherits(x, "AsIs"))
}

#' @noRd
is_object_argument <- function(x) {
  is_json_object(x) && !is.data.frame(x)
}

#' @noRd
convert_with_ellmer_type <- function(x, type) {
  cls <- class(type)[[1]]
  switch(
    cls,
    "ellmer::TypeBasic" = coerce_json_scalar(x, ellmer_prop(type, "type")),
    "ellmer::TypeEnum" = if (is.list(x)) {
      as.character(unlist(x))
    } else {
      as.character(x)
    },
    "ellmer::TypeArray" = {
      items <- ellmer_prop(type, "items")
      item_cls <- class(items)[[1]]
      if (item_cls == "ellmer::TypeBasic") {
        json_list_to_atomic(x, ellmer_prop(items, "type"))
      } else if (item_cls == "ellmer::TypeEnum") {
        as.character(unlist(x))
      } else if (item_cls == "ellmer::TypeObject") {
        records_to_data_frame(x)
      } else {
        lapply(x, convert_with_ellmer_type, type = items)
      }
    },
    "ellmer::TypeObject" = {
      props <- ellmer_prop(type, "properties")
      if (!is.list(x)) {
        return(x)
      }
      for (nm in intersect(names(x), names(props))) {
        if (!is.null(x[[nm]])) {
          x[[nm]] <- convert_with_ellmer_type(x[[nm]], props[[nm]])
        }
      }
      x
    },
    simplify_json_value(x)
  )
}

#' @noRd
convert_with_schema <- function(x, schema) {
  type <- schema$type
  if (length(type) > 1) {
    type <- setdiff(unlist(type), "null")[1]
  }
  if (is.null(type) && !is.null(schema$enum)) {
    type <- "string"
  }
  if (is.null(type)) {
    return(simplify_json_value(x))
  }
  switch(
    type,
    string = ,
    number = ,
    integer = ,
    boolean = coerce_json_scalar(x, type),
    array = {
      items <- schema$items %||% list()
      item_type <- items$type %||% if (!is.null(items$enum)) "string"
      if (
        is.character(item_type) &&
          item_type %in% c("string", "number", "integer", "boolean")
      ) {
        json_list_to_atomic(x, item_type)
      } else if (identical(item_type, "object")) {
        records_to_data_frame(x)
      } else {
        simplify_json_value(x)
      }
    },
    object = {
      if (!is.list(x) || is.null(schema$properties)) {
        return(x)
      }
      for (nm in intersect(names(x), names(schema$properties))) {
        if (!is.null(x[[nm]])) {
          x[[nm]] <- convert_with_schema(x[[nm]], schema$properties[[nm]])
        }
      }
      x
    },
    simplify_json_value(x)
  )
}

#' @noRd
coerce_json_scalar <- function(x, type) {
  if (is.list(x) && length(x) == 1) {
    x <- x[[1]]
  }
  if (is.list(x)) {
    return(x)
  }
  # Pages send what form controls hold, so numbers and flags may arrive as
  # strings ("0.05", "true"); read them as the schema says.
  if (is.character(x) && length(x) == 1) {
    x <- switch(
      type,
      integer = ,
      number = {
        n <- suppressWarnings(as.numeric(x))
        if (is.na(n)) x else n
      },
      boolean = if (tolower(x) %in% c("true", "false")) {
        tolower(x) == "true"
      } else {
        x
      },
      x
    )
  }
  switch(
    type,
    integer = if (is.numeric(x) && fits_integer(x)) as.integer(x) else x,
    number = if (is.numeric(x)) as.numeric(x) else x,
    x
  )
}

#' @noRd
json_list_to_atomic <- function(x, type) {
  if (!is.list(x)) {
    return(coerce_json_scalar(x, type))
  }
  if (length(x) == 0) {
    return(switch(
      type,
      string = character(),
      number = numeric(),
      integer = integer(),
      boolean = logical(),
      character()
    ))
  }
  if (
    !all(vapply(
      x,
      function(v) is.null(v) || (is.atomic(v) && length(v) <= 1),
      logical(1)
    ))
  ) {
    return(x)
  }
  x <- lapply(x, function(v) if (is.null(v) || length(v) == 0) NA else v)
  out <- unlist(x, use.names = FALSE)
  switch(
    type,
    integer = if (fits_integer(out)) as.integer(out) else as.numeric(out),
    number = as.numeric(out),
    boolean = as.logical(out),
    string = as.character(out),
    out
  )
}

#' Can these numbers be R integers without loss?
#' @noRd
fits_integer <- function(x) {
  n <- suppressWarnings(as.numeric(x))
  ok <- is.na(n) | (abs(n) <= .Machine$integer.max & n == round(n))
  all(ok[!is.na(ok)])
}

#' @noRd
records_to_data_frame <- function(x) {
  if (!is.list(x) || length(x) == 0) {
    return(x)
  }
  if (
    !all(vapply(
      x,
      function(row) is.list(row) && !is.null(names(row)),
      logical(1)
    ))
  ) {
    return(x)
  }
  cols <- unique(unlist(lapply(x, names)))
  out <- lapply(cols, function(col) {
    json_list_to_atomic(
      lapply(x, function(row) row[[col]] %||% NA),
      type = "auto"
    )
  })
  names(out) <- cols
  as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Simplify a JSON value without a schema
#'
#' Arrays of scalars become vectors; everything else is left alone.
#' @noRd
simplify_json_value <- function(x) {
  if (!is.list(x) || !is.null(names(x)) || length(x) == 0) {
    return(x)
  }
  scalar <- vapply(x, function(v) is.atomic(v) && length(v) == 1, logical(1))
  if (!all(scalar)) {
    return(x)
  }
  types <- unique(vapply(x, function(v) class(v)[[1]], character(1)))
  if (length(types) == 1) unlist(x, use.names = FALSE) else x
}

# ---- Output schemas ----

#' Build an outputSchema for a tool from its declared output ids
#'
#' `structuredContent` for a tool with outputs is an object keyed by output
#' id whose values are the model-facing values of each output. The values can
#' be anything an author chooses (`model_value`), so the schema describes the
#' keys and leaves their types open. Keys are not marked required: a tool may
#' leave an output unset.
#'
#' @param output_ids Character vector of output ids.
#' @param ui_output_types Named character vector, output id -> UI type.
#' @noRd
build_output_schema <- function(output_ids, ui_output_types = character(0)) {
  if (length(output_ids) == 0) {
    return(NULL)
  }
  descriptions <- c(
    text = "Text shown in the '%s' output.",
    plot = "Description of the plot shown in the '%s' output.",
    image = "Description of the image shown in the '%s' output.",
    table = "Rows of the table shown in the '%s' output.",
    html = "Text of the '%s' output.",
    ui = "Text of the '%s' output.",
    widget = "Summary of the widget shown in the '%s' output."
  )
  properties <- lapply(output_ids, function(id) {
    type <- if (id %in% names(ui_output_types)) ui_output_types[[id]] else NA
    template <- if (!is.na(type) && type %in% names(descriptions)) {
      descriptions[[type]]
    } else {
      "Value of the '%s' output."
    }
    list(description = sprintf(template, id))
  })
  names(properties) <- output_ids
  list(type = "object", properties = properties)
}
