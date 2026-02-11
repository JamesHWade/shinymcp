test_that("mcp_select generates correct HTML", {
  html <- mcp_select("x", "Pick one", c("a", "b", "c"))
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-input="x"')
  expect_match(rendered, 'data-shinymcp-type="select"')
  expect_match(rendered, "<option")
  expect_match(rendered, "Pick one")
})

test_that("mcp_select handles named choices", {
  html <- mcp_select("x", "Pick", c("Alpha" = "a", "Beta" = "b"))
  rendered <- as.character(html)
  expect_match(rendered, "Alpha")
  expect_match(rendered, 'value="a"')
})

test_that("mcp_text_input generates correct HTML", {
  html <- mcp_text_input("name", "Your name", placeholder = "Enter name")
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-input="name"')
  expect_match(rendered, 'data-shinymcp-type="text"')
  expect_match(rendered, 'placeholder="Enter name"')
})

test_that("mcp_numeric_input generates correct HTML", {
  html <- mcp_numeric_input("n", "Count", value = 5, min = 1, max = 10)
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-input="n"')
  expect_match(rendered, 'type="number"')
  expect_match(rendered, 'min="1"')
  expect_match(rendered, 'max="10"')
})

test_that("mcp_checkbox generates correct HTML", {
  html <- mcp_checkbox("flag", "Enable")
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-input="flag"')
  expect_match(rendered, 'type="checkbox"')
})

test_that("mcp_slider generates correct HTML", {
  html <- mcp_slider("val", "Value", min = 0, max = 100, value = 50)
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-input="val"')
  expect_match(rendered, 'type="range"')
})

test_that("mcp_radio generates correct HTML", {
  html <- mcp_radio("choice", "Choose", c("A", "B", "C"))
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-input="choice"')
  expect_match(rendered, 'type="radio"')
})

test_that("mcp_action_button generates correct HTML", {
  html <- mcp_action_button("go", "Go!")
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-input="go"')
  expect_match(rendered, 'data-shinymcp-type="button"')
  expect_match(rendered, "Go!")
})

test_that("mcp_input stamps attribute on a bare select tag", {
  tag <- htmltools::tags$select(id = "species", htmltools::tags$option("A"))
  result <- mcp_input(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="species"')
})

test_that("mcp_input finds nested input inside a div wrapper", {
  tag <- htmltools::tags$div(
    htmltools::tags$label("Name"),
    htmltools::tags$input(type = "text", id = "user_name")
  )
  result <- mcp_input(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="user_name"')
})

test_that("mcp_input with explicit id override", {
  tag <- htmltools::tags$select(
    id = "original_id",
    htmltools::tags$option("A")
  )
  result <- mcp_input(tag, id = "my_custom_id")
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="my_custom_id"')
})

test_that("mcp_input with id = NULL reads from element id", {
  tag <- htmltools::tags$div(
    htmltools::tags$select(id = "auto_id", htmltools::tags$option("A"))
  )
  result <- mcp_input(tag, id = NULL)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-input="auto_id"')
})

test_that("mcp_output stamps both attributes", {
  tag <- htmltools::tags$div(id = "result")
  result <- mcp_output(tag, type = "plot")
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-output="result"')
  expect_match(rendered, 'data-shinymcp-output-type="plot"')
})

test_that("mcp_output with id = NULL reads from element id", {
  tag <- htmltools::tags$pre(id = "my_output")
  result <- mcp_output(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'data-shinymcp-output="my_output"')
  expect_match(rendered, 'data-shinymcp-output-type="text"')
})

test_that("mcp_input errors when no id can be determined", {
  tag <- htmltools::tags$div(htmltools::tags$input(type = "text"))
  expect_error(mcp_input(tag), class = "shinymcp_error_validation")
})

test_that("mcp_input errors for bare tag without id", {
  tag <- htmltools::tags$select(htmltools::tags$option("A"))
  expect_error(mcp_input(tag), class = "shinymcp_error_validation")
})

test_that("mcp_output errors when no id can be determined", {
  tag <- htmltools::tags$div()
  expect_error(mcp_output(tag), class = "shinymcp_error_validation")
})

test_that("mcp_output validates type argument", {
  tag <- htmltools::tags$div(id = "x")
  expect_error(mcp_output(tag, type = "invalid"))
})

test_that("mcp_input stamps only the first of multiple inputs", {
  tag <- htmltools::tags$div(
    htmltools::tags$input(type = "text", id = "first"),
    htmltools::tags$input(type = "text", id = "second")
  )
  result <- mcp_input(tag)
  rendered <- as.character(result)
  expect_match(rendered, 'id="first" data-shinymcp-input="first"')
  # Second input should NOT have the attribute
  expect_no_match(rendered, 'id="second" data-shinymcp-input')
})

test_that("mcp_input stamps only first when first has no id", {
  tag <- htmltools::tags$div(
    htmltools::tags$input(type = "text"),
    htmltools::tags$input(type = "text", id = "second")
  )
  result <- mcp_input(tag, id = "my_id")
  rendered <- as.character(result)
  # First input gets stamped
  expect_match(rendered, 'data-shinymcp-input="my_id"')
  # Second input should NOT have the attribute
  expect_no_match(rendered, 'id="second" data-shinymcp-input')
})

test_that("mcp_plot generates correct HTML", {
  html <- mcp_plot("myplot", width = "600px", height = "400px")
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-output="myplot"')
  expect_match(rendered, 'data-shinymcp-output-type="plot"')
  expect_match(rendered, "600px")
})

test_that("mcp_text generates correct HTML", {
  html <- mcp_text("result")
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-output="result"')
  expect_match(rendered, 'data-shinymcp-output-type="text"')
})

test_that("mcp_table generates correct HTML", {
  html <- mcp_table("data")
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-output="data"')
  expect_match(rendered, 'data-shinymcp-output-type="table"')
})

test_that("mcp_html generates correct HTML", {
  html <- mcp_html("content")
  rendered <- as.character(html)
  expect_match(rendered, 'data-shinymcp-output="content"')
  expect_match(rendered, 'data-shinymcp-output-type="html"')
})
