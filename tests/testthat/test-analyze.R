test_that("analyze_reactive_graph produces tool groups", {
  app_dir <- fixture_medium_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)

  expect_s3_class(analysis, "ReactiveAnalysis")
  expect_true(length(analysis$tool_groups) > 0)
})

test_that("tool groups have required fields", {
  app_dir <- fixture_simple_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)

  group <- analysis$tool_groups[[1]]
  expect_true("name" %in% names(group))
  expect_true("input_args" %in% names(group))
  expect_true("output_targets" %in% names(group))
})

test_that("analyze errors on non-IR input", {
  expect_error(
    analyze_reactive_graph(list()),
    class = "shinymcp_error_analysis"
  )
})

test_that("complex app generates warnings", {
  app_dir <- fixture_complex_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)

  # Complex apps may have warnings about patterns
  expect_type(analysis$warnings, "character")
})

test_that("chained reactives produce correct transitive input deps", {
  app_dir <- fixture_chained_reactive_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)

  # Parser should detect reactive-to-reactive deps
  # filtered_data calls base_data()
  filtered <- Filter(function(r) r$name == "filtered_data", ir$reactives)
  expect_length(filtered, 1)

  expect_true("base_data" %in% filtered[[1]]$reactive_deps)

  analysis <- analyze_reactive_graph(ir)

  # The graph should have reactive-to-reactive edges
  edge_names <- names(analysis$graph$edges)
  r2r_edge_names <- edge_names[grepl("^reactive:.*->reactive:", edge_names)]
  expect_true(length(r2r_edge_names) > 0)

  # Find the tool group that includes the summary output
  summary_group <- NULL
  for (group in analysis$tool_groups) {
    output_ids <- vapply(
      group$output_targets,
      function(o) o$id,
      character(1)
    )
    if ("summary" %in% output_ids) {
      summary_group <- group
      break
    }
  }
  expect_false(is.null(summary_group))

  # summary and plot should be in the same tool group
  output_ids <- vapply(
    summary_group$output_targets,
    function(o) o$id,
    character(1)
  )
  expect_true("plot" %in% output_ids)

  # The summary tool group should include dataset as an input
  # (transitively through base_data -> filtered_data -> output$summary)
  input_ids <- vapply(
    summary_group$input_args,
    function(a) a$id,
    character(1)
  )
  expect_true("dataset" %in% input_ids)
  expect_true("n_rows" %in% input_ids)
})

test_that("independent groups produce separate tool groups", {
  app_dir <- fixture_chained_reactive_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  ir <- parse_shiny_app(app_dir)
  analysis <- analyze_reactive_graph(ir)

  # Should have at least 2 tool groups: data exploration and greeting
  expect_true(length(analysis$tool_groups) >= 2)

  # Find the greeting group
  greeting_group <- NULL
  for (group in analysis$tool_groups) {
    output_ids <- vapply(
      group$output_targets,
      function(o) o$id,
      character(1)
    )
    if ("greeting" %in% output_ids) {
      greeting_group <- group
      break
    }
  }
  expect_false(is.null(greeting_group))

  # Greeting group should only have user_name as input
  input_ids <- vapply(
    greeting_group$input_args,
    function(a) a$id,
    character(1)
  )
  expect_equal(input_ids, "user_name")
  expect_false("dataset" %in% input_ids)
})

test_that("expand_reactive_deps follows transitive chains", {
  # Simulate a chain: a -> b -> c
  reactives <- list(
    list(name = "a", input_deps = "x", reactive_deps = character()),
    list(name = "b", input_deps = "y", reactive_deps = "a"),
    list(name = "c", input_deps = character(), reactive_deps = "b")
  )

  # Starting from "c", should reach "b" and "a"
  result <- shinymcp:::expand_reactive_deps("c", reactives)
  expect_true("c" %in% result)
  expect_true("b" %in% result)
  expect_true("a" %in% result)
})

test_that("expand_reactive_deps handles cycles without infinite loop", {
  # Cycle: a -> b -> a (shouldn't happen in practice but shouldn't hang)
  reactives <- list(
    list(name = "a", input_deps = "x", reactive_deps = "b"),
    list(name = "b", input_deps = "y", reactive_deps = "a")
  )

  result <- shinymcp:::expand_reactive_deps("a", reactives)
  expect_true("a" %in% result)
  expect_true("b" %in% result)
})

test_that("expand_reactive_deps handles empty initial vector", {
  reactives <- list(
    list(name = "a", input_deps = "x", reactive_deps = character())
  )
  result <- shinymcp:::expand_reactive_deps(character(), reactives)
  expect_equal(result, character())
})

test_that("expand_reactive_deps handles unknown reactive names", {
  reactives <- list(
    list(name = "a", input_deps = "x", reactive_deps = character())
  )
  expect_warning(
    result <- shinymcp:::expand_reactive_deps(c("a", "nonexistent"), reactives),
    "nonexistent"
  )
  expect_true("a" %in% result)
  expect_true("nonexistent" %in% result)
  expect_length(result, 2)
})

test_that("expand_reactive_deps handles diamond dependency pattern", {
  # Diamond: d depends on b and c, both depend on a
  reactives <- list(
    list(name = "a", input_deps = "x", reactive_deps = character()),
    list(name = "b", input_deps = character(), reactive_deps = "a"),
    list(name = "c", input_deps = character(), reactive_deps = "a"),
    list(name = "d", input_deps = character(), reactive_deps = c("b", "c"))
  )
  result <- shinymcp:::expand_reactive_deps("d", reactives)
  expect_setequal(result, c("d", "b", "c", "a"))
  # No duplicates
  expect_length(result, 4)
})
