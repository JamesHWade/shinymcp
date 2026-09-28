# JSON Schema conversion and argument preparation (R/schema.R)

test_that("json_object() serializes as an empty JSON object", {
  expect_equal(as.character(to_json(json_object())), "{}")
  expect_equal(as.character(to_json(list())), "[]")
})

# ---- ellmer types to JSON Schema ----

test_that("ellmer scalar types map to JSON Schema types", {
  skip_if_not_installed("ellmer")

  expect_equal(ellmer_type_schema(ellmer::type_string()), list(type = "string"))
  expect_equal(ellmer_type_schema(ellmer::type_number()), list(type = "number"))
  expect_equal(
    ellmer_type_schema(ellmer::type_integer()),
    list(type = "integer")
  )
  expect_equal(
    ellmer_type_schema(ellmer::type_boolean()),
    list(type = "boolean")
  )
  expect_equal(
    ellmer_type_schema(ellmer::type_string("A name")),
    list(type = "string", description = "A name")
  )
})

test_that("ellmer enums, arrays, and objects map to JSON Schema", {
  skip_if_not_installed("ellmer")

  enum <- ellmer_type_schema(ellmer::type_enum(c("a", "b"), "Pick"))
  expect_equal(enum$type, "string")
  expect_s3_class(enum$enum, "AsIs")
  expect_equal(as.character(enum$enum), c("a", "b"))
  expect_equal(enum$description, "Pick")

  array <- ellmer_type_schema(ellmer::type_array(ellmer::type_integer("n")))
  expect_equal(
    array,
    list(type = "array", items = list(type = "integer", description = "n"))
  )

  object <- ellmer_type_schema(ellmer::type_object(
    "A point",
    x = ellmer::type_number(),
    y = ellmer::type_number(required = FALSE)
  ))
  expect_equal(object$type, "object")
  expect_equal(names(object$properties), c("x", "y"))
  expect_equal(as.character(object$required), "x")
  expect_false(object$additionalProperties)
  expect_equal(object$description, "A point")
})

test_that("an ellmer object with no properties has an empty properties object", {
  skip_if_not_installed("ellmer")
  schema <- ellmer_type_schema(ellmer::type_object())

  expect_equal(as.character(to_json(schema$properties)), "{}")
  expect_null(schema$required)
})

test_that("raw JSON Schema ellmer types pass through", {
  skip_if_not_installed("ellmer")
  type <- ellmer::type_from_schema(
    text = '{"type":"object","properties":{"a":{"type":"string"}},"description":"raw"}'
  )
  schema <- ellmer_type_schema(type)

  expect_equal(schema$type, "object")
  expect_equal(schema$properties$a, list(type = "string"))
  expect_equal(schema$description, "raw")
})

test_that("unknown types fall back to strings", {
  expect_equal(
    ellmer_type_schema(structure(list(), class = "mystery")),
    list(type = "string")
  )
})

test_that("tool input schemas are open objects of the tool's arguments", {
  skip_if_not_installed("ellmer")
  tool <- ellmer::tool(
    function(x, y = 1) x,
    name = "t",
    description = "",
    arguments = list(
      x = ellmer::type_string(),
      y = ellmer::type_number(required = FALSE)
    )
  )
  schema <- ellmer_tool_input_schema(tool)

  expect_equal(schema$type, "object")
  expect_equal(names(schema$properties), c("x", "y"))
  expect_equal(as.character(schema$required), "x")
  expect_null(schema$additionalProperties)
})

# ---- Schemas from formals and hand-written schemas ----

test_that("schema_from_formals guesses types from defaults", {
  schema <- schema_from_formals(function(
    a,
    b = 1L,
    c = 2.5,
    d = TRUE,
    e = "x",
    f = NULL,
    ...
  ) {
    NULL
  })

  expect_equal(schema$type, "object")
  expect_equal(
    lapply(schema$properties, `[[`, "type"),
    list(
      a = "string",
      b = "integer",
      c = "number",
      d = "boolean",
      e = "string",
      f = "string"
    )
  )
  expect_equal(
    as.character(to_json(schema_from_formals(function() NULL)$properties)),
    "{}"
  )
})

test_that("normalize_json_schema fixes empty objects, required, items, and enums", {
  schema <- normalize_json_schema(list(
    type = "object",
    properties = list(
      tags = list(
        type = "array",
        items = list(type = "object", properties = list())
      ),
      mode = list(type = "string", enum = list("a", "b"))
    ),
    required = list("tags")
  ))
  json <- jsonlite::parse_json(to_json(schema))

  expect_equal(json$required, list("tags"))
  expect_equal(json$properties$mode$enum, list("a", "b"))
  expect_equal(
    as.character(to_json(schema$properties$tags$items$properties)),
    "{}"
  )
  expect_equal(normalize_json_schema("not a list"), "not a list")
  expect_equal(
    as.character(to_json(
      normalize_json_schema(list(type = "object"))$properties
    )),
    "{}"
  )
})

test_that("normalize_json_schema treats a nullable object as an object", {
  schema <- normalize_json_schema(list(
    type = "object",
    properties = list(
      filters = list(
        type = list("object", "null"),
        properties = list(),
        required = "field"
      ),
      point = list(
        type = c("null", "object"),
        properties = list(
          at = list(type = list("object", "null"), properties = list())
        )
      )
    )
  ))
  json <- as.character(to_json(schema))
  parsed <- jsonlite::parse_json(json)

  expect_match(
    json,
    '"filters":{"type":["object","null"],"properties":{}',
    fixed = TRUE
  )
  expect_equal(parsed$properties$filters$required, list("field"))
  expect_match(
    json,
    '"at":{"type":["object","null"],"properties":{}}',
    fixed = TRUE
  )
})

test_that("normalize_json_schema treats a schema with properties as an object", {
  schema <- normalize_json_schema(list(
    type = "object",
    properties = list(
      filter = list(properties = list(), required = "field"),
      options = list(
        description = "No type, and properties of its own.",
        properties = list(inner = list(properties = list()))
      ),
      label = list(type = "string", enumNames = list("A", "B"))
    )
  ))
  json <- as.character(to_json(schema))

  expect_match(
    json,
    '"filter":{"properties":{},"required":["field"]}',
    fixed = TRUE
  )
  expect_match(json, '"inner":{"properties":{}}', fixed = TRUE)
  # Keys are matched exactly: enumNames isn't an enum.
  expect_null(jsonlite::parse_json(json)$properties$label[["enum"]])
})

test_that("normalize_json_schema reaches every keyword that holds schemas", {
  empty <- list(properties = list())
  schema <- normalize_json_schema(list(
    type = "object",
    properties = list(
      choice = list(anyOf = list(empty, list(type = "string"))),
      both = list(allOf = list(empty), oneOf = list(empty)),
      extra = list(type = "object", additionalProperties = empty),
      not_this = list(not = empty),
      pair = list(type = "array", prefixItems = list(empty), items = FALSE),
      tuple = list(type = "array", items = list(empty, empty)),
      conditional = list(`if` = empty, then = empty, `else` = empty),
      patterned = list(patternProperties = list(`^x` = empty))
    ),
    `$defs` = list(point = empty),
    definitions = list()
  ))
  json <- as.character(to_json(schema))

  expect_false(grepl('"properties":[]', json, fixed = TRUE))
  expect_match(
    json,
    '"anyOf":[{"properties":{}},{"type":"string"}]',
    fixed = TRUE
  )
  expect_match(json, '"additionalProperties":{"properties":{}}', fixed = TRUE)
  expect_match(json, '"items":false', fixed = TRUE)
  expect_match(
    json,
    '"items":[{"properties":{}},{"properties":{}}]',
    fixed = TRUE
  )
  expect_match(json, '"$defs":{"point":{"properties":{}}}', fixed = TRUE)
  expect_match(json, '"definitions":{}', fixed = TRUE)
})

# ---- JSON Schema back to ellmer types ----

test_that("schema_to_ellmer_types builds ellmer types from JSON Schema", {
  skip_if_not_installed("ellmer")
  types <- schema_to_ellmer_types(list(
    type = "object",
    properties = list(
      name = list(type = "string", description = "Name"),
      n = list(type = "integer"),
      level = list(type = "number"),
      flag = list(type = "boolean"),
      mode = list(enum = list("a", "b")),
      ids = list(type = "array", items = list(type = "integer")),
      point = list(
        type = "object",
        properties = list(x = list(type = "number"), y = list(type = "number")),
        required = list("x")
      ),
      maybe = list(type = list("number", "null"))
    ),
    required = list("name", "point")
  ))

  expect_equal(
    names(types),
    c("name", "n", "level", "flag", "mode", "ids", "point", "maybe")
  )
  expect_s3_class(types$name, "ellmer::TypeBasic")
  expect_equal(types$name@type, "string")
  expect_equal(types$name@description, "Name")
  expect_true(types$name@required)
  expect_false(types$n@required)
  expect_equal(types$n@type, "integer")
  expect_equal(types$level@type, "number")
  expect_equal(types$flag@type, "boolean")
  expect_s3_class(types$mode, "ellmer::TypeEnum")
  expect_equal(types$mode@values, c("a", "b"))
  expect_s3_class(types$ids, "ellmer::TypeArray")
  expect_equal(types$ids@items@type, "integer")
  expect_s3_class(types$point, "ellmer::TypeObject")
  expect_true(types$point@required)
  expect_true(types$point@properties$x@required)
  expect_false(types$point@properties$y@required)
  # A nullable union takes its non-null type.
  expect_equal(types$maybe@type, "number")
})

test_that("schema_to_ellmer_types handles free-form object arguments", {
  skip_if_not_installed("ellmer")

  types <- schema_to_ellmer_types(list(
    type = "object",
    properties = list(
      filters = list(type = "object", description = "Free-form")
    )
  ))
  expect_s3_class(types$filters, "ellmer::Type")
  expect_false(types$filters@required)
})

# ---- Argument preparation ----

test_that("empty arguments give an empty list", {
  expect_equal(prepare_tool_arguments(NULL), list())
  expect_equal(prepare_tool_arguments(list()), list())
})

test_that("arguments must be named", {
  expect_error(
    prepare_tool_arguments(list(1, 2)),
    class = "shinymcp_error_arguments"
  )
  expect_error(
    prepare_tool_arguments(stats::setNames(list(1, 2), c("a", ""))),
    class = "shinymcp_error_arguments"
  )
})

test_that("null arguments are dropped so defaults apply", {
  out <- prepare_tool_arguments(list(a = 1, b = NULL))
  expect_equal(out, list(a = 1))
})

test_that("arguments the function can't take are dropped", {
  expect_equal(
    prepare_tool_arguments(list(a = 1, b = 2), fun = function(a) a),
    list(a = 1)
  )
  expect_equal(
    prepare_tool_arguments(list(a = 1, b = 2), fun = function(a, ...) a),
    list(a = 1, b = 2)
  )
})

test_that("functions without arguments get no arguments", {
  expect_length(prepare_tool_arguments(list(a = 1), fun = function() 1), 0)

  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "noargs", fun = function() "ok")),
    name = "noargs"
  )
  expect_equal(app$call_tool("noargs", list(extra = 1)), "ok")
})

test_that("convert = FALSE leaves argument values alone", {
  schema <- list(
    type = "object",
    properties = list(
      ids = list(type = "array", items = list(type = "integer"))
    )
  )
  expect_equal(
    prepare_tool_arguments(
      list(ids = list(1, 2)),
      schema = schema,
      convert = FALSE
    ),
    list(ids = list(1, 2))
  )
})

test_that("arguments are converted with the schema", {
  schema <- list(
    type = "object",
    properties = list(
      n = list(type = "number"),
      i = list(type = "integer"),
      b = list(type = "boolean"),
      s = list(type = "string"),
      e = list(enum = list("a", "b")),
      ints = list(type = "array", items = list(type = "integer")),
      picks = list(type = "array", items = list(enum = list("x", "y"))),
      rows = list(type = "array", items = list(type = "object")),
      point = list(
        type = "object",
        properties = list(k = list(type = "integer"))
      ),
      maybe = list(type = list("integer", "null")),
      free = list()
    )
  )
  out <- prepare_tool_arguments(
    list(
      n = "1.5",
      i = 2,
      b = "true",
      s = "x",
      e = "a",
      ints = list(1, 2),
      picks = list("x"),
      rows = list(list(a = 1, b = "u"), list(a = 2)),
      point = list(k = 3, other = "kept"),
      maybe = 4,
      free = list(1, 2),
      unknown = list("p", "q")
    ),
    schema = schema
  )

  expect_identical(out$n, 1.5)
  expect_identical(out$i, 2L)
  expect_identical(out$b, TRUE)
  expect_identical(out$s, "x")
  expect_identical(out$e, "a")
  expect_identical(out$ints, c(1L, 2L))
  expect_identical(out$picks, "x")
  expect_s3_class(out$rows, "data.frame")
  expect_equal(out$rows$a, c(1, 2))
  expect_equal(out$rows$b, c("u", NA))
  expect_identical(out$point, list(k = 3L, other = "kept"))
  expect_identical(out$maybe, 4L)
  # Without a type, arrays of scalars become vectors.
  expect_identical(out$free, c(1, 2))
  expect_identical(out$unknown, c("p", "q"))
})

test_that("empty arrays become typed empty vectors", {
  schema <- function(type) {
    list(
      type = "object",
      properties = list(x = list(type = "array", items = list(type = type)))
    )
  }
  expect_identical(
    prepare_tool_arguments(list(x = list()), schema("string"))$x,
    character()
  )
  expect_identical(
    prepare_tool_arguments(list(x = list()), schema("number"))$x,
    numeric()
  )
  expect_identical(
    prepare_tool_arguments(list(x = list()), schema("integer"))$x,
    integer()
  )
  expect_identical(
    prepare_tool_arguments(list(x = list()), schema("boolean"))$x,
    logical()
  )
})

test_that("arguments are converted with ellmer types when given", {
  skip_if_not_installed("ellmer")
  types <- list(
    n = ellmer::type_integer(),
    mode = ellmer::type_enum(c("a", "b")),
    picks = ellmer::type_array(ellmer::type_enum(c("x", "y"))),
    rows = ellmer::type_array(ellmer::type_object(x = ellmer::type_number())),
    point = ellmer::type_object(k = ellmer::type_integer()),
    nested = ellmer::type_array(ellmer::type_array(ellmer::type_integer()))
  )
  out <- prepare_tool_arguments(
    list(
      n = 2,
      mode = "b",
      picks = list("x", "y"),
      rows = list(list(x = 1), list(x = 2)),
      point = list(k = 5),
      nested = list(list(1, 2), list(3))
    ),
    types = types
  )

  expect_identical(out$n, 2L)
  expect_identical(out$mode, "b")
  expect_identical(out$picks, c("x", "y"))
  expect_equal(out$rows, data.frame(x = c(1, 2)))
  expect_identical(out$point, list(k = 5L))
  expect_identical(out$nested, list(c(1L, 2L), 3L))
})

# ---- Scalar coercion ----

test_that("numbers arrive as numbers and whole numbers as integers", {
  expect_identical(coerce_json_scalar(2, "integer"), 2L)
  expect_identical(coerce_json_scalar(2.5, "integer"), 2.5)
  expect_identical(coerce_json_scalar(2L, "number"), 2)
  expect_identical(coerce_json_scalar(list(4), "integer"), 4L)
  expect_identical(coerce_json_scalar(list(1, 2), "integer"), list(1, 2))
  expect_identical(coerce_json_scalar(TRUE, "boolean"), TRUE)
})

test_that("strings holding numbers are read as numbers", {
  # Form controls send strings; the schema says what they mean.
  expect_identical(coerce_json_scalar("0.05", "number"), 0.05)
  expect_identical(coerce_json_scalar("3", "number"), 3)
  expect_identical(coerce_json_scalar("3", "integer"), 3L)
  expect_identical(coerce_json_scalar("-12", "integer"), -12L)
  expect_identical(coerce_json_scalar("1e3", "integer"), 1000L)
  # A fraction stays a number rather than being truncated.
  expect_identical(coerce_json_scalar("3.5", "integer"), 3.5)
})

test_that("strings that aren't numbers are left as they are", {
  expect_identical(coerce_json_scalar("abc", "number"), "abc")
  expect_identical(coerce_json_scalar("", "integer"), "")
  expect_identical(coerce_json_scalar("NaN", "number"), "NaN")
})

test_that("true and false strings are read as flags in any case", {
  expect_identical(coerce_json_scalar("true", "boolean"), TRUE)
  expect_identical(coerce_json_scalar("false", "boolean"), FALSE)
  expect_identical(coerce_json_scalar("TRUE", "boolean"), TRUE)
  expect_identical(coerce_json_scalar("False", "boolean"), FALSE)
  expect_identical(coerce_json_scalar("yes", "boolean"), "yes")
  expect_identical(coerce_json_scalar("1", "boolean"), "1")
})

test_that("strings for string arguments stay strings", {
  expect_identical(coerce_json_scalar("5", "string"), "5")
  expect_identical(coerce_json_scalar("true", "string"), "true")
})

test_that("tools receive typed values from string arguments", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(
      name = "typed",
      inputSchema = list(
        type = "object",
        properties = list(
          alpha = list(type = "number"),
          n = list(type = "integer"),
          paired = list(type = "boolean")
        )
      ),
      fun = function(alpha, n, paired) {
        list(alpha = alpha, n = n, paired = paired)
      }
    )),
    name = "typed"
  )

  out <- app$call_tool("typed", list(alpha = "0.05", n = "3", paired = "true"))
  expect_identical(out, list(alpha = 0.05, n = 3L, paired = TRUE))
})

test_that("integers beyond R's integer range stay numbers", {
  expect_identical(coerce_json_scalar(3e9, "integer"), 3e9)
  expect_identical(coerce_json_scalar("3000000000", "integer"), 3e9)
})

# ---- Arrays and records ----

test_that("arrays of scalars become typed vectors", {
  expect_identical(json_list_to_atomic(list(1, 2), "integer"), c(1L, 2L))
  expect_identical(json_list_to_atomic(list(1, 2.5), "number"), c(1, 2.5))
  expect_identical(
    json_list_to_atomic(list(TRUE, FALSE), "boolean"),
    c(TRUE, FALSE)
  )
  expect_identical(json_list_to_atomic(list("a", 1), "string"), c("a", "1"))
  expect_identical(json_list_to_atomic(list(), "boolean"), logical())
  # A scalar is coerced as a scalar.
  expect_identical(json_list_to_atomic(3, "integer"), 3L)
  # Arrays of arrays are left alone.
  expect_identical(json_list_to_atomic(list(list(1)), "number"), list(list(1)))
})

test_that("arrays with nulls become vectors with NA", {
  expect_identical(
    json_list_to_atomic(list(1, NULL, 3), "integer"),
    c(1L, NA, 3L)
  )
  schema <- list(
    type = "object",
    properties = list(x = list(type = "array", items = list(type = "number")))
  )
  expect_identical(
    prepare_tool_arguments(list(x = list(1, NULL)), schema = schema)$x,
    c(1, NA)
  )
})

test_that("arrays of records become data frames", {
  df <- records_to_data_frame(list(list(a = 1, b = "x"), list(a = 2)))
  expect_equal(df, data.frame(a = c(1, 2), b = c("x", NA)))

  # Anything else is left alone.
  expect_identical(records_to_data_frame(list(1, 2)), list(1, 2))
  expect_identical(records_to_data_frame(list()), list())
  expect_identical(records_to_data_frame("x"), "x")
})

test_that("values without a schema are simplified only when uniform", {
  expect_identical(simplify_json_value(list(1, 2)), c(1, 2))
  expect_identical(simplify_json_value(list("a", "b")), c("a", "b"))
  expect_identical(simplify_json_value(list(1, "a")), list(1, "a"))
  expect_identical(simplify_json_value(list(a = 1)), list(a = 1))
  expect_identical(simplify_json_value(list(list(1))), list(list(1)))
  expect_identical(simplify_json_value(list()), list())
  expect_identical(simplify_json_value("x"), "x")
})

test_that("convert_with_schema handles union types and enum-only schemas", {
  expect_identical(
    convert_with_schema("2", list(type = list("integer", "null"))),
    2L
  )
  expect_identical(convert_with_schema("a", list(enum = list("a", "b"))), "a")
  expect_identical(convert_with_schema(list(1, 2), list()), c(1, 2))
  expect_identical(convert_with_schema("x", list(type = "object")), "x")
})

# ---- Output schemas ----

test_that("build_output_schema describes each output by its UI type", {
  expect_null(build_output_schema(character()))

  schema <- build_output_schema(
    c("summary", "chart", "rows", "note", "widget", "other"),
    c(
      summary = "text",
      chart = "plot",
      rows = "table",
      note = "html",
      widget = "widget"
    )
  )
  expect_equal(schema$type, "object")
  expect_equal(
    schema$properties$summary$description,
    "Text shown in the 'summary' output."
  )
  expect_equal(
    schema$properties$chart$description,
    "Description of the plot shown in the 'chart' output."
  )
  expect_equal(
    schema$properties$rows$description,
    "Rows of the table shown in the 'rows' output."
  )
  expect_equal(schema$properties$note$description, "Text of the 'note' output.")
  expect_equal(
    schema$properties$widget$description,
    "Summary of the widget shown in the 'widget' output."
  )
  expect_equal(
    schema$properties$other$description,
    "Value of the 'other' output."
  )
  expect_null(schema$required)
})
