# Extracted from test-tools.R:768

# prequel ----------------------------------------------------------------------
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

# test -------------------------------------------------------------------------
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
      fun = function(size) size,
      inputSchema = list(
        type = "object",
        properties = list(size = list(type = "string", enum = c("s", "m"))),
        required = "size"
      )
    )
  )
)
text <- function(res) res$content[[1]]$text
missing <- app$run_tool("greet", list())
expect_true(missing$isError)
expect_identical(text(missing), "Error: Missing required argument: `name`.")
wrong_type <- app$run_tool("greet", list(name = "Bo", times = "x"))
expect_identical(text(wrong_type), "Error: `times` must be a number.")
