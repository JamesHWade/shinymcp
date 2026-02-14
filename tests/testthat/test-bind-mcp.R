# Tests for bindMcp() and detect_mcp_role()

# ---- detect_mcp_role() ----

test_that("detect_mcp_role identifies Shiny plot output", {
  skip_if_not_installed("shiny")
  tag <- shiny::plotOutput("myplot")
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "output")
  expect_equal(result$id, "myplot")
  expect_equal(result$type, "plot")
})

test_that("detect_mcp_role identifies Shiny text output", {
  skip_if_not_installed("shiny")
  tag <- shiny::textOutput("mytxt")
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "output")
  expect_equal(result$id, "mytxt")
  expect_equal(result$type, "text")
})

test_that("detect_mcp_role identifies verbatimTextOutput", {
  skip_if_not_installed("shiny")
  tag <- shiny::verbatimTextOutput("code")
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "output")
  expect_equal(result$id, "code")
  expect_equal(result$type, "text")
})

test_that("detect_mcp_role identifies Shiny select input", {
  skip_if_not_installed("shiny")
  tag <- shiny::selectInput("x", "Choose:", c("a", "b"))
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "input")
  expect_equal(result$id, "x")
  expect_equal(result$type, "select")
})

test_that("detect_mcp_role identifies numeric input", {
  skip_if_not_installed("shiny")
  tag <- shiny::numericInput("n", "Number:", 10, min = 1, max = 50)
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "input")
  expect_equal(result$id, "n")
  expect_equal(result$type, "numeric")
})

test_that("detect_mcp_role identifies text input", {
  skip_if_not_installed("shiny")
  tag <- shiny::textInput("name", "Name:")
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "input")
  expect_equal(result$id, "name")
  expect_equal(result$type, "text")
})

test_that("detect_mcp_role identifies checkbox input", {
  skip_if_not_installed("shiny")
  tag <- shiny::checkboxInput("flag", "Enable")
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "input")
  expect_equal(result$id, "flag")
  expect_equal(result$type, "checkbox")
})

test_that("detect_mcp_role identifies slider input", {
  skip_if_not_installed("shiny")
  tag <- shiny::sliderInput("val", "Value:", min = 0, max = 100, value = 50)
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "input")
  expect_equal(result$id, "val")
  expect_equal(result$type, "slider")
})

test_that("detect_mcp_role identifies radio buttons", {
  skip_if_not_installed("shiny")
  tag <- shiny::radioButtons("choice", "Choose:", c("A", "B"))
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "input")
  expect_equal(result$id, "choice")
  expect_equal(result$type, "radio")
})

test_that("detect_mcp_role returns unknown for plain div", {
  tag <- htmltools::tags$div(id = "foo", "hello")
  result <- detect_mcp_role(tag)
  expect_equal(result$role, "unknown")
})

test_that("detect_mcp_role returns unknown for non-tag", {
  result <- detect_mcp_role("not a tag")
  expect_equal(result$role, "unknown")
})


# ---- bindMcp() on inputs ----

test_that("bindMcp stamps data-shinymcp-input on selectInput", {
  skip_if_not_installed("shiny")
  tag <- shiny::selectInput("x", "X:", c("a", "b"))
  result <- bindMcp(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="x"')
})

test_that("bindMcp stamps data-shinymcp-input on numericInput", {
  skip_if_not_installed("shiny")
  tag <- shiny::numericInput("n", "N:", 10)
  result <- bindMcp(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="n"')
})

test_that("bindMcp stamps data-shinymcp-input on textInput", {
  skip_if_not_installed("shiny")
  tag <- shiny::textInput("name", "Name:")
  result <- bindMcp(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="name"')
})

test_that("bindMcp stamps data-shinymcp-input on sliderInput", {
  skip_if_not_installed("shiny")
  tag <- shiny::sliderInput("val", "V:", min = 0, max = 100, value = 50)
  result <- bindMcp(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="val"')
})


# ---- bindMcp() on outputs ----

test_that("bindMcp stamps data-shinymcp-output on plotOutput", {
  skip_if_not_installed("shiny")
  tag <- shiny::plotOutput("plot")
  result <- bindMcp(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-output="plot"')
  expect_match(rendered, 'data-shinymcp-output-type="plot"')
})

test_that("bindMcp stamps data-shinymcp-output on textOutput", {
  skip_if_not_installed("shiny")
  tag <- shiny::textOutput("txt")
  result <- bindMcp(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-output="txt"')
  expect_match(rendered, 'data-shinymcp-output-type="text"')
})

test_that("bindMcp stamps data-shinymcp-output on verbatimTextOutput", {
  skip_if_not_installed("shiny")
  tag <- shiny::verbatimTextOutput("code")
  result <- bindMcp(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-output="code"')
  expect_match(rendered, 'data-shinymcp-output-type="text"')
})


# ---- bindMcp() idempotency ----

test_that("bindMcp is idempotent on already-annotated tags", {
  skip_if_not_installed("shiny")
  tag <- shiny::selectInput("x", "X:", c("a", "b"))
  annotated <- bindMcp(tag)
  double <- bindMcp(annotated)
  # Should not double-stamp
  rendered <- as.character(double)
  matches <- gregexpr('data-shinymcp-input="x"', rendered)[[1]]
  expect_equal(sum(matches > 0), 1L)
})

test_that("bindMcp is idempotent on mcp_select", {
  tag <- mcp_select("x", "X", c("a", "b"))
  result <- bindMcp(tag)
  # mcp_select already has data-shinymcp-input, so bindMcp should be a no-op
  expect_identical(as.character(result), as.character(tag))
})


# ---- bindMcp() with explicit id/type ----

test_that("bindMcp accepts explicit id override", {
  skip_if_not_installed("shiny")
  tag <- shiny::selectInput("orig", "X:", c("a", "b"))
  result <- bindMcp(tag, id = "custom_id")
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="custom_id"')
})

test_that("bindMcp accepts explicit type override for outputs", {
  skip_if_not_installed("shiny")
  tag <- shiny::plotOutput("myout")
  result <- bindMcp(tag, type = "html")
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-output-type="html"')
})


# ---- bindMcp() error handling ----

test_that("bindMcp errors on plain div without id", {
  tag <- htmltools::tags$div("hello")
  expect_error(bindMcp(tag), class = "shinymcp_error_validation")
})

test_that("bindMcp.default errors on non-tag objects", {
  expect_error(bindMcp(42), class = "shinymcp_error_validation")
  expect_error(bindMcp("string"), class = "shinymcp_error_validation")
})


# ---- extract_inputs_from_tags / extract_outputs_from_tags ----

test_that("extract_inputs_from_tags finds Shiny inputs", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::selectInput("x", "X:", c("a", "b")),
    shiny::numericInput("n", "N:", 10),
    shiny::plotOutput("plot")
  )
  inputs <- extract_inputs_from_tags(ui)
  ids <- vapply(inputs, function(i) i$id, character(1))
  expect_true("x" %in% ids)
  expect_true("n" %in% ids)
  expect_false("plot" %in% ids)
})

test_that("extract_outputs_from_tags finds Shiny outputs", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::selectInput("x", "X:", c("a", "b")),
    shiny::plotOutput("plot"),
    shiny::textOutput("txt")
  )
  outputs <- extract_outputs_from_tags(ui)
  ids <- vapply(outputs, function(o) o$id, character(1))
  expect_true("plot" %in% ids)
  expect_true("txt" %in% ids)
  expect_false("x" %in% ids)
})

test_that("selective mode only finds annotated elements", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::selectInput("x", "X:", c("a", "b")) |> bindMcp(),
    shiny::numericInput("n", "N:", 10),
    shiny::plotOutput("plot") |> bindMcp()
  )
  inputs <- extract_inputs_from_tags(ui, selective = TRUE)
  outputs <- extract_outputs_from_tags(ui, selective = TRUE)
  input_ids <- vapply(inputs, function(i) i$id, character(1))
  output_ids <- vapply(outputs, function(o) o$id, character(1))
  expect_true("x" %in% input_ids)
  expect_false("n" %in% input_ids)
  expect_true("plot" %in% output_ids)
})


# ---- parse_shiny_app_object ----

test_that("parse_shiny_app_object creates ShinyAppIR from tags", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::selectInput("dataset", "Dataset:", c("mtcars", "iris")),
    shiny::plotOutput("plot"),
    shiny::textOutput("summary")
  )
  server_body <- quote({
    output$plot <- renderPlot({
      plot(get(input$dataset))
    })
    output$summary <- renderText({
      paste("Rows:", nrow(get(input$dataset)))
    })
  })
  ir <- parse_shiny_app_object(ui, server_body)
  expect_s3_class(ir, "ShinyAppIR")
  expect_equal(length(ir$inputs), 1)
  expect_equal(ir$inputs[[1]]$id, "dataset")
  expect_equal(length(ir$outputs), 2)
  expect_true("dataset" %in% ir$input_refs)
})

test_that("parse_shiny_app_object works with selective mode", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::selectInput("x", "X:", c("a", "b")) |> bindMcp(),
    shiny::numericInput("n", "N:", 10),
    shiny::plotOutput("plot") |> bindMcp()
  )
  ir <- parse_shiny_app_object(ui, server_body = NULL, selective = TRUE)
  expect_equal(length(ir$inputs), 1)
  expect_equal(ir$inputs[[1]]$id, "x")
  expect_equal(length(ir$outputs), 1)
  expect_equal(ir$outputs[[1]]$id, "plot")
})
