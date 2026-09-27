# Tool normalization: ellmer tools, list tools, and shinymcp tool records all
# become one `shinymcp_tool` shape.

explore_tool <- function() {
  ellmer::tool(
    function(
      species,
      n = 5L,
      tags = NULL,
      opts = NULL,
      flag = FALSE,
      rows = NULL,
      mode = "a"
    ) {
      list(
        species = species,
        n = n,
        tags = tags,
        opts = opts,
        flag = flag,
        rows = rows,
        mode = mode
      )
    },
    name = "explore",
    description = "Explore the data.",
    arguments = list(
      species = ellmer::type_string("Species name"),
      n = ellmer::type_integer("How many", required = FALSE),
      tags = ellmer::type_array(
        ellmer::type_string(),
        "Tags",
        required = FALSE
      ),
      opts = ellmer::type_object(
        "Options",
        a = ellmer::type_number(),
        b = ellmer::type_boolean(required = FALSE),
        .required = FALSE
      ),
      flag = ellmer::type_boolean("A flag", required = FALSE),
      rows = ellmer::type_array(
        ellmer::type_object(
          x = ellmer::type_number(),
          y = ellmer::type_string()
        ),
        required = FALSE
      ),
      mode = ellmer::type_enum(c("a", "b"), "Mode", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title = "Explorer",
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      idempotent_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

# ---- ellmer tools ----

test_that("ellmer tools keep their name, description, and title", {
  skip_if_not_installed("ellmer")
  tool <- as_mcp_tool(explore_tool())

  expect_s3_class(tool, "shinymcp_tool")
  expect_equal(tool$name, "explore")
  expect_equal(tool$description, "Explore the data.")
  expect_equal(tool$title, "Explorer")
  expect_equal(tool$source, "ellmer")
  expect_true(is.function(tool$handler))
  expect_s3_class(tool$original, "ellmer::ToolDef")
})

test_that("ellmer argument types become a JSON Schema object", {
  skip_if_not_installed("ellmer")
  schema <- as_mcp_tool(explore_tool())$input_schema
  props <- schema$properties

  expect_equal(schema$type, "object")
  expect_null(schema$additionalProperties)
  expect_equal(
    names(props),
    c("species", "n", "tags", "opts", "flag", "rows", "mode")
  )
  # Only required arguments are listed as required.
  expect_equal(as.character(schema$required), "species")

  expect_equal(
    props$species,
    list(type = "string", description = "Species name")
  )
  expect_equal(props$n$type, "integer")
  expect_equal(props$flag$type, "boolean")
  expect_equal(props$tags$type, "array")
  expect_equal(props$tags$items, list(type = "string"))
  expect_equal(props$mode$type, "string")
  expect_equal(as.character(props$mode$enum), c("a", "b"))
  expect_equal(props$mode$description, "Mode")

  # Nested objects keep their own required list and are closed.
  expect_equal(props$opts$type, "object")
  expect_equal(names(props$opts$properties), c("a", "b"))
  expect_equal(as.character(props$opts$required), "a")
  expect_false(props$opts$additionalProperties)
  expect_equal(props$opts$description, "Options")

  expect_equal(props$rows$items$type, "object")
  expect_equal(as.character(props$rows$items$required), c("x", "y"))
})

test_that("ellmer schemas serialize with JSON arrays for enums and required", {
  skip_if_not_installed("ellmer")
  json <- jsonlite::parse_json(to_json(
    as_mcp_tool(explore_tool())$input_schema
  ))

  expect_equal(json$required, list("species"))
  expect_equal(json$properties$mode$enum, list("a", "b"))
  expect_equal(json$properties$opts$required, list("a"))
})

test_that("ellmer annotations become camelCase MCP hints", {
  skip_if_not_installed("ellmer")
  tool <- as_mcp_tool(explore_tool())

  expect_equal(
    tool$annotations[order(names(tool$annotations))],
    list(
      destructiveHint = FALSE,
      idempotentHint = TRUE,
      openWorldHint = FALSE,
      readOnlyHint = TRUE,
      title = "Explorer"
    )
  )
})

test_that("an ellmer tool without arguments or annotations has an empty schema", {
  skip_if_not_installed("ellmer")
  tool <- as_mcp_tool(
    ellmer::tool(function() "done", name = "noargs", description = "No args")
  )

  expect_null(tool$annotations)
  expect_null(tool$title)
  expect_equal(
    as.character(to_json(tool$input_schema)),
    '{"type":"object","properties":{}}'
  )
  expect_equal(tool$handler(list(), list()), "done")
  expect_equal(tool$handler(NULL, list()), "done")
})

test_that("ignored ellmer arguments are left out of the schema", {
  skip_if_not_installed("ellmer")
  tool <- as_mcp_tool(ellmer::tool(
    function(x, ctx = NULL) x,
    name = "ignoring",
    description = "",
    arguments = list(x = ellmer::type_string(), ctx = ellmer::type_ignore())
  ))

  expect_equal(names(tool$input_schema$properties), "x")
})

test_that("ellmer tool handlers convert JSON arguments to R values", {
  skip_if_not_installed("ellmer")
  tool <- as_mcp_tool(explore_tool())

  # Arguments as they arrive from JSON (arrays are lists).
  out <- tool$handler(
    list(
      species = "Adelie",
      n = 3,
      tags = list("x", "y"),
      opts = list(a = 1, b = TRUE),
      rows = list(list(x = 1, y = "a"), list(x = 2, y = "b")),
      mode = NULL,
      unknown = "dropped"
    ),
    list()
  )

  expect_identical(out$species, "Adelie")
  expect_identical(out$n, 3L)
  expect_identical(out$tags, c("x", "y"))
  expect_equal(out$opts, list(a = 1, b = TRUE))
  expect_s3_class(out$rows, "data.frame")
  expect_equal(out$rows$x, c(1, 2))
  expect_equal(out$rows$y, c("a", "b"))
  # A null argument falls back to the function's default.
  expect_identical(out$mode, "a")
  expect_false(out$flag)
})

test_that("ellmer tools with convert = FALSE get arguments as parsed JSON", {
  skip_if_not_installed("ellmer")
  tool <- as_mcp_tool(ellmer::tool(
    function(tags = NULL) tags,
    name = "raw_tags",
    description = "",
    arguments = list(
      tags = ellmer::type_array(ellmer::type_string(), required = FALSE)
    ),
    convert = FALSE
  ))

  expect_identical(
    tool$handler(list(tags = list("x", "y")), list()),
    list("x", "y")
  )
})

test_that("ellmer arrays of enums become character vectors", {
  skip_if_not_installed("ellmer")
  tool <- as_mcp_tool(ellmer::tool(
    function(tags = NULL) tags,
    name = "enum_tags",
    description = "",
    arguments = list(
      tags = ellmer::type_array(
        ellmer::type_enum(c("x", "y")),
        required = FALSE
      )
    )
  ))

  expect_identical(
    tool$handler(list(tags = list("x", "y")), list()),
    c("x", "y")
  )
  expect_equal(
    as.character(tool$input_schema$properties$tags$items$enum),
    c("x", "y")
  )
})

# ---- List tools ----

test_that("list tools are normalized with defaults", {
  tool <- as_mcp_tool(list(
    name = "compute",
    fun = function(x = 1) x * 2,
    inputSchema = list(
      type = "object",
      properties = list(x = list(type = "number"))
    )
  ))

  expect_s3_class(tool, "shinymcp_tool")
  expect_equal(tool$name, "compute")
  expect_equal(tool$description, "")
  expect_null(tool$title)
  expect_null(tool$annotations)
  expect_null(tool$visibility)
  expect_equal(tool$source, "list")
  expect_equal(tool$handler(list(x = 4), list()), 8)
})

test_that("list tools take title, annotations, outputs, and _meta", {
  tool <- as_mcp_tool(list(
    name = "l",
    title = "Top title",
    annotations = list(title = "Annotation title", read_only_hint = TRUE),
    outputs = c("a", "b"),
    outputSchema = list(type = "object"),
    `_meta` = list(custom = "x"),
    fun = function() NULL
  ))

  expect_equal(tool$title, "Top title")
  expect_equal(
    tool$annotations,
    list(title = "Annotation title", readOnlyHint = TRUE)
  )
  expect_equal(tool$outputs, c("a", "b"))
  expect_equal(tool$output_schema, list(type = "object"))
  expect_equal(tool$meta, list(custom = "x"))

  titled <- as_mcp_tool(list(
    name = "t",
    annotations = list(title = "From hint")
  ))
  expect_equal(titled$title, "From hint")
})

test_that("list tools accept the legacy .output_ids field", {
  tool <- as_mcp_tool(list(
    name = "l",
    .output_ids = c("a", "b"),
    fun = function() NULL
  ))
  expect_equal(tool$outputs, c("a", "b"))
})

test_that("list tools without a schema get one from the function's formals", {
  tool <- as_mcp_tool(list(
    name = "f",
    fun = function(a, b = 1L, c = 2.5, d = TRUE, e = "x", f = NULL, ...) NULL
  ))
  props <- tool$input_schema$properties

  expect_equal(names(props), c("a", "b", "c", "d", "e", "f"))
  expect_equal(
    vapply(props, `[[`, character(1), "type"),
    c(
      a = "string",
      b = "integer",
      c = "number",
      d = "boolean",
      e = "string",
      f = "string"
    )
  )

  none <- as_mcp_tool(list(name = "g", fun = function() NULL))
  expect_equal(
    as.character(to_json(none$input_schema)),
    '{"type":"object","properties":{}}'
  )
})

test_that("hand-written schemas are fixed up to serialize as JSON", {
  tool <- as_mcp_tool(list(
    name = "h",
    inputSchema = list(
      type = "object",
      properties = list(
        x = list(type = "string", enum = list("a", "b")),
        nested = list(type = "object", properties = list())
      ),
      required = "x"
    ),
    fun = function(x, nested = NULL) x
  ))
  json <- jsonlite::parse_json(to_json(tool$input_schema))

  expect_equal(json$required, list("x"))
  expect_equal(json$properties$x$enum, list("a", "b"))
  expect_equal(
    as.character(to_json(tool$input_schema$properties$nested)),
    '{"type":"object","properties":{}}'
  )
})

test_that("list tool handlers convert arguments with the schema", {
  tool <- as_mcp_tool(list(
    name = "typed",
    inputSchema = list(
      type = "object",
      properties = list(
        ids = list(type = "array", items = list(type = "integer")),
        level = list(type = "number")
      )
    ),
    fun = function(ids, level = 0.5) list(ids = ids, level = level)
  ))

  out <- tool$handler(list(ids = list(1, 2), level = "0.9"), list())
  expect_identical(out$ids, c(1L, 2L))
  expect_identical(out$level, 0.9)
})

test_that("list tools with convert = FALSE get arguments as parsed JSON", {
  tool <- as_mcp_tool(list(
    name = "raw",
    inputSchema = list(
      type = "object",
      properties = list(
        ids = list(type = "array", items = list(type = "integer"))
      )
    ),
    fun = function(ids) ids,
    convert = FALSE
  ))

  expect_identical(tool$handler(list(ids = list(1, 2)), list()), list(1, 2))
})

test_that("list tools drop arguments their function doesn't take", {
  tool <- as_mcp_tool(list(name = "one", fun = function(a) a))
  expect_equal(tool$handler(list(a = 1, b = 2), list()), 1)

  dots <- as_mcp_tool(list(name = "dots", fun = function(...) names(list(...))))
  expect_equal(dots$handler(list(a = 1, b = 2), list()), c("a", "b"))
})

test_that("list tools without a function can't be called", {
  tool <- as_mcp_tool(list(name = "empty", description = "Nothing to run"))

  expect_error(
    tool$handler(list(), list()),
    class = "shinymcp_error_tool_not_callable"
  )
})

test_that("invalid tools are rejected", {
  expect_error(
    as_mcp_tool(list(name = "", fun = function() 1)),
    class = "shinymcp_error_validation"
  )
  expect_error(
    as_mcp_tool(list(name = c("a", "b"))),
    class = "shinymcp_error_validation"
  )
  expect_error(
    as_mcp_tool(list(name = "x", fun = "not a function")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    as_mcp_tool(42, index = 3),
    "tool 3",
    class = "shinymcp_error_validation"
  )
  expect_error(
    as_mcp_tool(list(description = "no name")),
    class = "shinymcp_error_validation"
  )
})

test_that("shinymcp tool records pass through unchanged", {
  tool <- new_mcp_tool("raw", handler = function(arguments, context) "raw")

  expect_identical(as_mcp_tool(tool), tool)
  expect_equal(tool$description, "")
  expect_equal(
    as.character(to_json(tool$input_schema)),
    '{"type":"object","properties":{}}'
  )
})

test_that("tool_argument_names lists the schema's properties", {
  expect_equal(
    tool_argument_names(as_mcp_tool(list(name = "a", fun = function(x, y) {
      NULL
    }))),
    c("x", "y")
  )
  expect_length(tool_argument_names(new_mcp_tool("b", handler = identity)), 0)
})

# ---- Annotations ----

test_that("normalize_tool_annotations maps snake_case and drops unknown keys", {
  out <- normalize_tool_annotations(list(
    read_only_hint = TRUE,
    open_world_hint = FALSE,
    idempotent_hint = TRUE,
    destructive_hint = FALSE,
    title = "Demo",
    bogus = "ignored",
    destructiveHint = NULL
  ))

  expect_equal(out$readOnlyHint, TRUE)
  expect_equal(out$openWorldHint, FALSE)
  expect_equal(out$idempotentHint, TRUE)
  expect_equal(out$destructiveHint, FALSE)
  expect_equal(out$title, "Demo")
  expect_null(out$bogus)
  expect_null(normalize_tool_annotations(list()))
  expect_null(normalize_tool_annotations(NULL))
  expect_null(normalize_tool_annotations(list(bogus = 1)))
})

test_that("normalize_tool_annotations keeps keys already in camelCase", {
  expect_equal(
    normalize_tool_annotations(list(readOnlyHint = TRUE, openWorldHint = TRUE)),
    list(readOnlyHint = TRUE, openWorldHint = TRUE)
  )
})

# ---- Visibility ----

test_that("visibility must be drawn from model and app", {
  expect_equal(validate_visibility("app", "t"), "app")
  expect_equal(
    validate_visibility(list("model", "app", "app"), "t"),
    c("model", "app")
  )
  expect_error(
    validate_visibility("robot", "t"),
    class = "shinymcp_error_validation"
  )
  expect_error(
    validate_visibility(character(), "t"),
    class = "shinymcp_error_validation"
  )

  expect_equal(
    as_mcp_tool(list(name = "a", visibility = "app"))$visibility,
    "app"
  )
  expect_error(
    as_mcp_tool(list(name = "a", visibility = "everyone")),
    class = "shinymcp_error_validation"
  )
})

test_that("tools without a visibility are visible to everyone", {
  open <- as_mcp_tool(list(name = "open"))
  app_only <- as_mcp_tool(list(name = "app_only", visibility = "app"))
  model_only <- as_mcp_tool(list(name = "model_only", visibility = "model"))

  expect_true(tool_visible_to(open, "model"))
  expect_true(tool_visible_to(open, "app"))
  expect_false(tool_visible_to(app_only, "model"))
  expect_true(tool_visible_to(app_only, "app"))
  expect_true(tool_visible_to(model_only, "model"))
  expect_false(tool_visible_to(model_only, "app"))
  expect_error(tool_visible_to(open, "robot"))
})

# ---- Wire definitions ----

test_that("wire definitions carry the flat and nested UI resource keys", {
  tool <- as_mcp_tool(list(
    name = "approve",
    description = "Approve a proposal.",
    visibility = "app",
    `_meta` = list(custom = "x"),
    fun = function() NULL
  ))

  def <- tool_wire_definition(tool, resource_uri = "ui://demo")
  expect_equal(def$name, "approve")
  expect_equal(def$description, "Approve a proposal.")
  expect_null(def$title)
  expect_null(def$annotations)
  expect_null(def$outputSchema)
  expect_equal(def[["_meta"]]$custom, "x")
  expect_equal(def[["_meta"]][["ui/resourceUri"]], "ui://demo")
  expect_equal(def[["_meta"]][["ui"]]$resourceUri, "ui://demo")
  expect_equal(as.character(def[["_meta"]][["ui"]]$visibility), "app")

  json <- jsonlite::parse_json(to_json(def))
  expect_equal(json[["_meta"]]$ui$visibility, list("app"))

  flat <- tool_wire_definition(
    tool,
    resource_uri = "ui://demo",
    include_ui_meta = FALSE
  )
  expect_null(flat[["_meta"]][["ui"]])
  expect_equal(flat[["_meta"]][["ui/resourceUri"]], "ui://demo")
})

test_that("wire definitions use a fallback outputSchema only when the tool has none", {
  fallback <- list(type = "object", properties = list(a = list()))
  plain <- as_mcp_tool(list(name = "p", fun = function() NULL))
  own <- as_mcp_tool(list(
    name = "o",
    outputSchema = list(
      type = "object",
      properties = list(z = list(type = "number"))
    ),
    fun = function() NULL
  ))

  expect_equal(
    tool_wire_definition(
      plain,
      "ui://x",
      output_schema = fallback
    )$outputSchema,
    fallback
  )
  expect_equal(
    names(
      tool_wire_definition(
        own,
        "ui://x",
        output_schema = fallback
      )$outputSchema$properties
    ),
    "z"
  )
})

test_that("tool_definitions surfaces annotation hints in camelCase", {
  app <- mcp_app(
    ui = htmltools::tags$div(
      `data-shinymcp-output` = "result",
      `data-shinymcp-output-type` = "text"
    ),
    tools = list(list(
      name = "compute",
      description = "Compute a value",
      inputSchema = list(type = "object", properties = list()),
      annotations = list(read_only_hint = TRUE, destructive_hint = FALSE),
      fun = function(...) list(result = "ok")
    )),
    name = "demo"
  )

  d <- app$tool_definitions()[[1]]
  expect_equal(d$annotations$readOnlyHint, TRUE)
  expect_equal(d$annotations$destructiveHint, FALSE)
})

test_that("tool_definitions derives an outputSchema from declared output ids", {
  app <- mcp_app(
    ui = htmltools::tagList(
      mcp_text("result"),
      mcp_plot("chart"),
      mcp_table("rows"),
      mcp_html("note")
    ),
    tools = list(list(
      name = "compute",
      description = "Compute a value",
      inputSchema = list(type = "object", properties = list()),
      .output_ids = c("result", "chart", "rows", "note", "elsewhere"),
      fun = function(...) list(result = "ok")
    )),
    name = "demo"
  )

  schema <- app$tool_definitions()[[1]]$outputSchema
  expect_equal(schema$type, "object")
  expect_equal(
    names(schema$properties),
    c("result", "chart", "rows", "note", "elsewhere")
  )
  # Values are whatever each output's model value is, so no type is imposed
  # and no key is required.
  expect_null(schema$properties$result$type)
  expect_null(schema$required)
  expect_match(
    schema$properties$result$description,
    "Text shown in the 'result' output"
  )
  expect_match(schema$properties$chart$description, "plot")
  expect_match(schema$properties$rows$description, "Rows of the table")
  expect_match(
    schema$properties$elsewhere$description,
    "Value of the 'elsewhere' output"
  )
})

test_that("tools without declared outputs have no outputSchema", {
  app <- helper_greeter_app()
  expect_null(app$tool_definitions()[[1]]$outputSchema)
})

# ---- Request context ----

test_that("mcp_request() is NULL outside a request", {
  expect_null(mcp_request())
})

test_that("mcp_request() describes the call inside a tool", {
  seen <- NULL
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(
      name = "who",
      fun = function() {
        seen <<- mcp_request()
        "ok"
      }
    )),
    name = "who"
  )

  app$call_tool("who")
  expect_equal(seen$caller, "model")
  expect_equal(seen$transport, "in-process")

  app$call_tool(
    "who",
    context = list(caller = "app", user = "ada", groups = "staff")
  )
  expect_equal(seen$caller, "app")
  expect_equal(seen$user, "ada")
  expect_equal(seen$groups, "staff")

  app$run_tool("who", context = list(transport = "http"))
  expect_equal(seen$transport, "http")

  expect_null(mcp_request())
})

test_that("mcp_request() works in ellmer tools too", {
  skip_if_not_installed("ellmer")
  app <- mcp_app(
    htmltools::div(),
    tools = list(ellmer::tool(
      function() mcp_request()$caller,
      name = "caller",
      description = "Who called?"
    )),
    name = "ellmer-request"
  )

  expect_equal(app$call_tool("caller"), "model")
  expect_equal(app$call_tool("caller", context = list(caller = "app")), "app")
})

test_that("nested tool calls restore the outer request", {
  inner <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "inner", fun = function() mcp_request()$caller)),
    name = "inner"
  )
  outer <- mcp_app(
    htmltools::div(),
    tools = list(list(
      name = "outer",
      fun = function() {
        before <- mcp_request()$caller
        nested <- inner$call_tool("inner", context = list(caller = "app"))
        after <- mcp_request()$caller
        c(before, nested, after)
      }
    )),
    name = "outer"
  )

  expect_equal(outer$call_tool("outer"), c("model", "app", "model"))
  expect_null(mcp_request())
})

test_that("the request context is cleared when a tool fails", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "boom", fun = function() stop("boom"))),
    name = "failing"
  )

  expect_error(app$call_tool("boom"), "boom")
  expect_null(mcp_request())

  app$run_tool("boom")
  expect_null(mcp_request())
})

test_that("the model's arguments are checked against the schema", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(
      list(
        name = "greet",
        description = "Greet",
        fun = function(name, times = 1) paste(rep(name, times), collapse = " ")
      ),
      list(
        name = "pick",
        description = "Pick",
        fun = function(size, times = 1) paste(rep(size, times), collapse = ""),
        inputSchema = list(
          type = "object",
          properties = list(
            size = list(type = "string", enum = c("s", "m")),
            times = list(type = "integer")
          ),
          required = "size"
        )
      )
    )
  )
  text <- function(res) res$content[[1]]$text

  missing <- app$run_tool("greet", list())
  expect_true(missing$isError)
  expect_identical(text(missing), "Error: Missing required argument: `name`.")

  wrong_type <- app$run_tool("pick", list(size = "s", times = "x"))
  expect_identical(text(wrong_type), "Error: `times` must be a whole number.")
  fraction <- app$run_tool("pick", list(size = "s", times = 1.5))
  expect_identical(text(fraction), "Error: `times` must be a whole number.")

  not_listed <- app$run_tool("pick", list(size = "xl"))
  expect_identical(
    text(not_listed),
    "Error: `size` must be one of \"s\", \"m\"."
  )

  expect_identical(
    text(app$run_tool("pick", list(size = "m", times = "2"))),
    "mm"
  )

  # Schemas guessed from a function's defaults aren't used to check types.
  expect_identical(text(app$run_tool("greet", list(name = 5))), "5")

  # The app's own calls reach the function as they are.
  from_app <- app$run_tool("greet", list(), context = list(caller = "app"))
  expect_true(from_app$isError)
  expect_match(text(from_app), "is missing", fixed = TRUE)
})
