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

# ---- Output placeholders ----

test_that("mcp_plot() keeps the plot's aspect ratio without a height", {
  tag <- mcp_plot("chart")
  rendered <- as.character(tag)

  expect_equal(htmltools::tagGetAttribute(tag, "id"), "chart")
  expect_equal(
    htmltools::tagGetAttribute(tag, "class"),
    "shinymcp-output shinymcp-plot"
  )
  expect_match(rendered, 'style="width:100%;"', fixed = TRUE)
  expect_false(grepl("height", rendered, fixed = TRUE))
  expect_false(grepl("shinymcp-plot-fixed", rendered, fixed = TRUE))
})

test_that("mcp_plot() with a height scales the plot to fit", {
  tag <- mcp_plot("chart", width = "600px", height = "400px")

  expect_equal(
    htmltools::tagGetAttribute(tag, "class"),
    "shinymcp-output shinymcp-plot shinymcp-plot-fixed"
  )
  expect_equal(
    htmltools::tagGetAttribute(tag, "style"),
    "width:600px;height:400px;"
  )
})

test_that("mcp_plot() accepts sizes in pixels as numbers", {
  tag <- mcp_plot("chart", width = 500, height = 300)
  expect_equal(
    htmltools::tagGetAttribute(tag, "style"),
    "width:500px;height:300px;"
  )
})

test_that("mcp_text() is a preformatted block", {
  tag <- mcp_text("summary")

  expect_equal(tag$name, "pre")
  expect_equal(htmltools::tagGetAttribute(tag, "id"), "summary")
  expect_equal(
    htmltools::tagGetAttribute(tag, "class"),
    "shinymcp-output shinymcp-text"
  )
})

test_that("mcp_table() and mcp_html() are output containers", {
  table <- mcp_table("rows")
  html <- mcp_html("note")

  expect_equal(table$name, "div")
  expect_equal(htmltools::tagGetAttribute(table, "id"), "rows")
  expect_equal(htmltools::tagGetAttribute(table, "class"), "shinymcp-output")
  expect_equal(html$name, "div")
  expect_equal(htmltools::tagGetAttribute(html, "class"), "shinymcp-output")
})

test_that("output placeholders are found by id and type", {
  ui <- htmltools::tagList(
    mcp_text("summary"),
    mcp_plot("chart", height = "300px"),
    mcp_table("rows"),
    mcp_html("note"),
    mcp_output(htmltools::tags$section(id = "custom"), type = "html")
  )
  outputs <- extract_outputs_from_tags(ui)

  expect_equal(
    vapply(outputs, `[[`, character(1), "id"),
    c("summary", "chart", "rows", "note", "custom")
  )
  expect_equal(
    vapply(outputs, `[[`, character(1), "type"),
    c("text", "plot", "table", "html", "html")
  )
})

test_that("mcp_output() with an explicit id overrides the element's id", {
  tag <- mcp_output(htmltools::tags$div(id = "x"), id = "y", type = "table")
  expect_equal(htmltools::tagGetAttribute(tag, "id"), "x")
  expect_equal(htmltools::tagGetAttribute(tag, "data-shinymcp-output"), "y")
  expect_equal(
    htmltools::tagGetAttribute(tag, "data-shinymcp-output-type"),
    "table"
  )
})

# ---- Input components ----

test_that("mcp_select() marks the selected choice", {
  rendered <- as.character(mcp_select(
    "x",
    "Pick",
    c(Alpha = "a", Beta = "b"),
    selected = "b"
  ))

  expect_match(rendered, '<option value="a">Alpha</option>', fixed = TRUE)
  expect_match(
    rendered,
    '<option value="b" selected>Beta</option>',
    fixed = TRUE
  )
  expect_match(rendered, '<label for="x">Pick</label>', fixed = TRUE)

  first <- as.character(mcp_select("x", "Pick", c("a", "b")))
  expect_match(first, '<option value="a" selected>a</option>', fixed = TRUE)
})

test_that("mcp_numeric_input() only writes the limits it is given", {
  bare <- as.character(mcp_numeric_input("n", "Count", value = 5))
  expect_match(bare, 'value="5"', fixed = TRUE)
  expect_match(bare, 'data-shinymcp-type="numeric"', fixed = TRUE)
  expect_false(grepl("min=|max=|step=", bare))

  full <- as.character(mcp_numeric_input(
    "n",
    "Count",
    value = 5,
    min = 0,
    max = 10,
    step = 0.5
  ))
  expect_match(full, 'min="0" max="10" step="0.5"', fixed = TRUE)
})

test_that("mcp_checkbox() is checked only when value is TRUE", {
  expect_false(grepl("checked", as.character(mcp_checkbox("flag", "Enable"))))
  expect_match(
    as.character(mcp_checkbox("flag", "Enable", value = TRUE)),
    "checked",
    fixed = TRUE
  )
  expect_match(
    as.character(mcp_checkbox("flag", "Enable")),
    'data-shinymcp-type="checkbox"',
    fixed = TRUE
  )
})

test_that("mcp_slider() starts at its minimum by default", {
  rendered <- as.character(mcp_slider("val", "Value", min = 2, max = 10))
  expect_match(rendered, 'min="2" max="10" value="2" step="1"', fixed = TRUE)
  expect_match(rendered, 'data-shinymcp-type="slider"', fixed = TRUE)
})

test_that("mcp_radio() marks the group and the selected choice", {
  tag <- mcp_radio(
    "choice",
    "Choose",
    c(First = "a", Second = "b"),
    selected = "b"
  )
  rendered <- as.character(tag)

  expect_equal(htmltools::tagGetAttribute(tag, "data-shinymcp-input"), "choice")
  expect_equal(htmltools::tagGetAttribute(tag, "data-shinymcp-type"), "radio")
  expect_match(
    rendered,
    '<input type="radio" name="choice" value="a"/>',
    fixed = TRUE
  )
  expect_match(
    rendered,
    '<input type="radio" name="choice" value="b" checked/>',
    fixed = TRUE
  )
  expect_match(rendered, "Second", fixed = TRUE)
})

test_that("mcp_text_input() takes an initial value", {
  rendered <- as.character(mcp_text_input("name", "Name", value = "Ada"))
  expect_match(rendered, 'value="Ada"', fixed = TRUE)
  expect_false(grepl("placeholder", rendered, fixed = TRUE))
})

test_that("input components are found as inputs", {
  ui <- htmltools::tagList(
    mcp_select("species", "Species", c("a", "b")),
    mcp_numeric_input("n", "N", 1),
    mcp_radio("mode", "Mode", c("x", "y")),
    mcp_checkbox("flag", "Flag")
  )
  inputs <- extract_inputs_from_tags(ui)

  expect_equal(
    vapply(inputs, `[[`, character(1), "id"),
    c("species", "n", "mode", "flag")
  )
  expect_equal(
    vapply(inputs, `[[`, character(1), "type"),
    c("select", "numeric", "radio", "checkbox")
  )
})

# ---- mcp_input() on Shiny inputs ----

test_that("mcp_input() marks Shiny input groups as a whole", {
  skip_if_not_installed("shiny")
  groups <- list(
    radio = shiny::radioButtons("r", "R", c("a", "b")),
    checkboxes = shiny::checkboxGroupInput("cg", "CG", c("a", "b")),
    date = shiny::dateInput("d", "D"),
    range = shiny::dateRangeInput("dr", "DR")
  )

  for (tag in groups) {
    marked <- mcp_input(tag)
    id <- htmltools::tagGetAttribute(tag, "id")
    expect_equal(htmltools::tagGetAttribute(marked, "data-shinymcp-input"), id)
    # Only the group is marked, not the <input>s inside it.
    expect_equal(helper_count(as.character(marked), "data-shinymcp-input"), 1)
  }
})

test_that("mcp_input() marks the form element inside a Shiny input", {
  skip_if_not_installed("shiny")
  select <- as.character(mcp_input(shiny::selectInput("s", "S", c("a", "b"))))
  expect_match(
    select,
    '<select id="s" class="shiny-input-select" data-shinymcp-input="s">',
    fixed = TRUE
  )

  area <- as.character(mcp_input(shiny::textAreaInput("ta", "TA")))
  expect_match(area, '<textarea id="ta"[^>]*data-shinymcp-input="ta"')

  checkbox <- as.character(mcp_input(shiny::checkboxInput("cb", "CB")))
  expect_match(
    checkbox,
    '<input id="cb" type="checkbox"[^>]*data-shinymcp-input="cb"'
  )
  expect_equal(helper_count(checkbox, "data-shinymcp-input"), 1)
})

test_that("mcp_input() marks a form element itself", {
  skip_if_not_installed("shiny")
  button <- mcp_input(shiny::actionButton("go", "Go"))
  expect_equal(button$name, "button")
  expect_equal(htmltools::tagGetAttribute(button, "data-shinymcp-input"), "go")

  input <- mcp_input(htmltools::tags$input(type = "text", id = "a"), id = "b")
  expect_equal(htmltools::tagGetAttribute(input, "id"), "a")
  expect_equal(htmltools::tagGetAttribute(input, "data-shinymcp-input"), "b")
})

test_that("mcp_input() prefers an input group inside a wrapper", {
  skip_if_not_installed("shiny")
  wrapped <- htmltools::div(
    shiny::textInput("t", "T"),
    shiny::radioButtons("r", "R", c("a", "b"))
  )
  rendered <- as.character(mcp_input(wrapped))

  expect_equal(helper_count(rendered, "data-shinymcp-input"), 1)
  expect_match(
    rendered,
    '<div id="r" class="[^"]*shiny-input-radiogroup[^"]*"[^>]*data-shinymcp-input="r"'
  )
})

test_that("mcp_input() finds the first element in document order", {
  tag <- htmltools::div(
    htmltools::div(htmltools::tags$input(id = "deep1")),
    htmltools::tags$input(id = "deep2")
  )
  rendered <- as.character(mcp_input(tag))

  expect_match(
    rendered,
    '<input id="deep1" data-shinymcp-input="deep1"/>',
    fixed = TRUE
  )
  expect_match(rendered, '<input id="deep2"/>', fixed = TRUE)
})

test_that("mcp_input() marks a custom widget container", {
  custom <- mcp_input(htmltools::div(
    id = "picker",
    class = "my-widget",
    htmltools::span("x")
  ))
  expect_equal(
    htmltools::tagGetAttribute(custom, "data-shinymcp-input"),
    "picker"
  )

  renamed <- mcp_input(htmltools::div(class = "my-widget"), id = "w")
  expect_equal(htmltools::tagGetAttribute(renamed, "data-shinymcp-input"), "w")

  expect_error(
    mcp_input(htmltools::div(class = "x")),
    class = "shinymcp_error_validation"
  )
  expect_error(
    mcp_input(htmltools::tags$input(type = "text")),
    class = "shinymcp_error_validation"
  )
})
