# Describing a Shiny UI's inputs and outputs for the live runtime, and
# converting JSON values into what a server function expects
# (R/runtime-inputs.R).

describe_one <- function(tag) {
  specs <- describe_ui_inputs(tag)
  expect_length(specs, 1)
  specs[[1]]
}

# ---- describe_ui_inputs(): one spec per Shiny input ----

test_that("selectInput() is a select with its choices and selection", {
  skip_if_not_installed("shiny")
  for (selectize in c(TRUE, FALSE)) {
    spec <- describe_one(shiny::selectInput(
      "sel",
      "Select one",
      c("a", "b", "c"),
      selected = "b",
      selectize = selectize
    ))
    expect_identical(spec$id, "sel")
    expect_identical(spec$kind, "select")
    expect_identical(spec$value, "b")
    expect_identical(spec$choices, c("a", "b", "c"))
    expect_identical(spec$choice_labels, c("a", "b", "c"))
    expect_false(spec$bound)
  }
})

test_that("a select without a selection defaults to its first choice", {
  skip_if_not_installed("shiny")
  spec <- describe_one(shiny::selectInput(
    "sel",
    "Sel",
    c("x", "y"),
    selectize = FALSE
  ))
  expect_identical(spec$value, "x")
  # A hand-written <select> without options has no value.
  empty <- describe_one(htmltools::tags$select(id = "empty"))
  expect_identical(empty$kind, "select")
  expect_null(empty$value)
  expect_length(empty$choices, 0)
})

test_that("named choices keep values and labels apart", {
  skip_if_not_installed("shiny")
  spec <- describe_one(shiny::selectInput(
    "sel",
    "Sel",
    c(Alpha = "a", Beta = "b")
  ))
  expect_identical(spec$choices, c("a", "b"))
  expect_identical(spec$choice_labels, c("Alpha", "Beta"))
})

test_that("options in optgroups are all choices", {
  skip_if_not_installed("shiny")
  spec <- describe_one(shiny::selectInput(
    "state",
    "State",
    list(East = c("NY", "NJ"), West = c("CA", "WA"))
  ))
  expect_identical(spec$choices, c("NY", "NJ", "CA", "WA"))
  expect_identical(spec$value, "NY")
})

test_that("option values written as escaped HTML are unescaped", {
  skip_if_not_installed("shiny")
  choices <- c("a&b", "say \"hi\"", "<tag>", "it's")
  spec <- describe_one(shiny::selectInput(
    "esc",
    "Esc",
    choices,
    selected = "<tag>"
  ))
  expect_identical(spec$choices, choices)
  expect_identical(spec$choice_labels, choices)
  expect_identical(spec$value, "<tag>")
})

test_that("multiple selects are select-multiple with every selected value", {
  skip_if_not_installed("shiny")
  spec <- describe_one(shiny::selectInput(
    "multi",
    "Multi",
    c("a", "b", "c"),
    selected = c("a", "c"),
    multiple = TRUE
  ))
  expect_identical(spec$kind, "select-multiple")
  expect_identical(spec$value, c("a", "c"))
  # Nothing selected means no value, as Shiny sends NULL.
  none <- describe_one(shiny::selectInput(
    "none",
    "None",
    c("a", "b"),
    multiple = TRUE
  ))
  expect_null(none$value)
})

test_that("a selected option whose value contains 'selected' doesn't fool the parser", {
  skip_if_not_installed("shiny")
  spec <- describe_one(shiny::selectInput(
    "filter",
    "Filter",
    c("Show selected items", "All"),
    selected = "All"
  ))
  expect_identical(spec$value, "All")
})

test_that("text, text area and password inputs", {
  skip_if_not_installed("shiny")
  text <- describe_one(shiny::textInput("txt", "Text", value = "hello"))
  expect_identical(text$kind, "text")
  expect_identical(text$value, "hello")
  expect_identical(describe_one(shiny::textInput("blank", "Blank"))$value, "")

  area <- describe_one(shiny::textAreaInput(
    "area",
    "Area",
    value = "multi\nline"
  ))
  expect_identical(area$kind, "textarea")
  expect_identical(area$value, "multi\nline")

  # A password's value never leaves the page.
  password <- describe_one(shiny::passwordInput(
    "pw",
    "Password",
    value = "secret"
  ))
  expect_identical(password$kind, "password")
  expect_identical(password$value, "")
})

test_that("numericInput() carries its bounds; an empty value is NA", {
  skip_if_not_installed("shiny")
  spec <- describe_one(shiny::numericInput(
    "num",
    "Number",
    3,
    min = 0,
    max = 10,
    step = 0.5
  ))
  expect_identical(spec$kind, "number")
  expect_identical(spec$value, 3)
  expect_identical(spec$min, 0)
  expect_identical(spec$max, 10)
  expect_identical(spec$step, 0.5)

  empty <- describe_one(shiny::numericInput("num", "Number", NA))
  expect_identical(empty$value, NA_real_)
  expect_null(empty$min)
  expect_null(empty$max)
})

test_that("checkboxInput() is a checkbox with its checked state", {
  skip_if_not_installed("shiny")
  expect_true(describe_one(shiny::checkboxInput("on", "On", TRUE))$value)
  off <- describe_one(shiny::checkboxInput("off", "Off", FALSE))
  expect_identical(off$kind, "checkbox")
  expect_false(off$value)
})

test_that("checkbox groups and radio buttons are containers of options", {
  skip_if_not_installed("shiny")
  group <- describe_one(shiny::checkboxGroupInput(
    "grp",
    "Group",
    c(One = "1", Two = "2", Three = "3"),
    selected = c("1", "3")
  ))
  expect_identical(group$kind, "checkbox-group")
  expect_identical(group$label, "Group")
  expect_identical(group$value, c("1", "3"))
  expect_identical(group$choices, c("1", "2", "3"))
  expect_identical(group$choice_labels, c("One", "Two", "Three"))
  expect_true(group$container)
  expect_null(
    describe_one(shiny::checkboxGroupInput("g", "G", c("a", "b")))$value
  )

  radio <- describe_one(shiny::radioButtons(
    "rad",
    "Radio",
    c(Left = "l", Right = "r"),
    selected = "r"
  ))
  expect_identical(radio$kind, "radio")
  expect_identical(radio$label, "Radio")
  expect_identical(radio$value, "r")
  expect_identical(radio$choices, c("l", "r"))
  expect_identical(radio$choice_labels, c("Left", "Right"))
  # radioButtons() checks the first choice unless told otherwise.
  expect_identical(
    describe_one(shiny::radioButtons("r2", "R", c("x", "y")))$value,
    "x"
  )
  none <- describe_one(shiny::radioButtons(
    "r3",
    "R",
    c("x", "y"),
    selected = character()
  ))
  expect_null(none$value)
})

test_that("sliderInput() is a number slider or a range", {
  skip_if_not_installed("shiny")
  single <- describe_one(shiny::sliderInput(
    "sld",
    "Slider",
    min = 0,
    max = 100,
    value = 40,
    step = 5
  ))
  expect_identical(single$kind, "slider")
  expect_identical(single$value, 40)
  expect_identical(single$min, 0)
  expect_identical(single$max, 100)
  expect_identical(single$step, 5)
  expect_identical(single$data_type, "number")

  range <- describe_one(shiny::sliderInput(
    "rng",
    "Range",
    min = 0,
    max = 10,
    value = c(2, 7)
  ))
  expect_identical(range$kind, "slider-range")
  expect_identical(range$value, c(2, 7))
})

test_that("date sliders hold Dates, datetime sliders POSIXct", {
  skip_if_not_installed("shiny")
  date <- describe_one(shiny::sliderInput(
    "dsld",
    "Date slider",
    min = as.Date("2024-01-01"),
    max = as.Date("2024-12-31"),
    value = as.Date("2024-06-01")
  ))
  expect_identical(date$kind, "slider")
  expect_identical(date$data_type, "date")
  expect_identical(date$value, as.Date("2024-06-01"))
  expect_identical(date$min, as.Date("2024-01-01"))
  expect_identical(date$max, as.Date("2024-12-31"))

  date_range <- describe_one(shiny::sliderInput(
    "drng",
    "Dates",
    min = as.Date("2024-01-01"),
    max = as.Date("2024-12-31"),
    value = as.Date(c("2024-02-01", "2024-03-01"))
  ))
  expect_identical(date_range$kind, "slider-range")
  expect_identical(date_range$value, as.Date(c("2024-02-01", "2024-03-01")))

  datetime <- describe_one(shiny::sliderInput(
    "dtsld",
    "Datetime",
    min = as.POSIXct("2024-01-01 00:00", tz = "UTC"),
    max = as.POSIXct("2024-01-02 00:00", tz = "UTC"),
    value = as.POSIXct("2024-01-01 12:00", tz = "UTC")
  ))
  expect_identical(datetime$data_type, "datetime")
  expect_s3_class(datetime$value, "POSIXct")
  expect_identical(
    as.numeric(datetime$value),
    as.numeric(as.POSIXct("2024-01-01 12:00", tz = "UTC"))
  )
})

test_that("datetime slider values are in UTC, as Shiny delivers them", {
  skip_if_not_installed("shiny")
  withr::local_timezone("America/New_York")
  spec <- describe_one(shiny::sliderInput(
    "dtsld",
    "Datetime",
    min = as.POSIXct("2024-01-01 00:00", tz = "UTC"),
    max = as.POSIXct("2024-01-02 00:00", tz = "UTC"),
    value = as.POSIXct("2024-01-01 12:00", tz = "UTC")
  ))
  expect_identical(attr(spec$value, "tzone"), "UTC")
  expect_match(
    input_json_schema(spec)$description,
    "Default: 2024-01-01T12:00:00Z.",
    fixed = TRUE
  )
})

test_that("dateInput() and dateRangeInput() are containers with dates", {
  skip_if_not_installed("shiny")
  date <- describe_one(shiny::dateInput(
    "dt",
    "Date",
    value = "2024-03-15",
    min = "2024-01-01",
    max = "2024-12-31"
  ))
  expect_identical(date$kind, "date")
  expect_identical(date$label, "Date")
  expect_identical(date$value, as.Date("2024-03-15"))
  expect_identical(date$min, "2024-01-01")
  expect_identical(date$max, "2024-12-31")
  expect_true(date$container)

  range <- describe_one(shiny::dateRangeInput(
    "drng",
    "Range",
    start = "2024-01-01",
    end = "2024-02-01"
  ))
  expect_identical(range$kind, "date-range")
  expect_identical(range$value, as.Date(c("2024-01-01", "2024-02-01")))
  expect_null(range$min)
})

test_that("missing initial dates are today, as in Shiny", {
  skip_if_not_installed("shiny")
  expect_identical(
    describe_one(shiny::dateInput("dt", "Date"))$value,
    Sys.Date()
  )
  expect_identical(
    describe_one(shiny::dateRangeInput("dr", "Range"))$value,
    rep(Sys.Date(), 2)
  )
  expect_identical(
    parse_initial_dates(c("2024-01-01", NA), 2),
    as.Date(c("2024-01-01", format(Sys.Date())))
  )
  expect_identical(
    parse_initial_dates("2024-01-01", 2),
    as.Date(rep("2024-01-01", 2))
  )
})

test_that("action buttons and links are counters starting at zero", {
  skip_if_not_installed("shiny")
  button <- describe_one(shiny::actionButton("go", "Go now"))
  expect_identical(button$kind, "action")
  expect_identical(button$label, "Go now")
  expect_identical(button$value, action_value(0L))
  expect_s3_class(button$value, "shinyActionButtonValue")

  link <- describe_one(shiny::actionLink("lnk", "Link it"))
  expect_identical(link$kind, "action")
  expect_identical(link$label, "Link it")
})

test_that("fileInput() is a file input with no value", {
  skip_if_not_installed("shiny")
  spec <- describe_one(shiny::fileInput("upload", "Upload"))
  expect_identical(spec$kind, "file")
  expect_null(spec$value)
})

test_that("labels come from each input's <label>", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::selectInput("sel", "Select one", c("a", "b")),
    shiny::textInput("txt", "Your name"),
    shiny::textAreaInput("area", "Notes"),
    shiny::passwordInput("pw", "Password"),
    shiny::numericInput("num", "How many", 1),
    shiny::checkboxInput("chk", "Include all"),
    shiny::sliderInput("sld", "Level", 0, 10, 5),
    shiny::fileInput("upload", "Upload")
  )
  specs <- describe_ui_inputs(ui)
  labels <- vapply(specs, function(s) s$label %||% NA_character_, character(1))
  expect_identical(
    labels,
    c(
      sel = "Select one",
      txt = "Your name",
      area = "Notes",
      pw = "Password",
      num = "How many",
      chk = "Include all",
      sld = "Level",
      upload = "Upload"
    )
  )
})

test_that("shinymcp's own inputs are described and bound", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    mcp_select(
      "species",
      "Species",
      c(Adelie = "adelie", Gentoo = "gentoo"),
      selected = "gentoo"
    ),
    mcp_text_input("name", "Name", value = "Ada"),
    mcp_numeric_input("count", "Count", 5, min = 1, max = 9),
    mcp_checkbox("flag", "Flag", value = TRUE),
    mcp_slider("level", "Level", min = 0, max = 10, value = 3),
    mcp_radio("size", "Size", c("s", "m", "l"), selected = "m")
  )
  specs <- describe_ui_inputs(ui)
  expect_named(specs, c("species", "name", "count", "flag", "level", "size"))
  expect_true(all(vapply(specs, function(s) s$bound, logical(1))))

  expect_identical(specs$species$kind, "select")
  expect_identical(specs$species$value, "gentoo")
  expect_identical(specs$species$choice_labels, c("Adelie", "Gentoo"))
  expect_identical(specs$name$value, "Ada")
  expect_identical(specs$count$kind, "number")
  expect_identical(specs$count$max, 9)
  expect_true(specs$flag$value)
  # mcp_slider() is a native range input.
  expect_identical(specs$level$kind, "slider")
  expect_identical(specs$level$value, 3)
  expect_identical(specs$level$max, 10)
  expect_identical(specs$size$kind, "radio")
  expect_identical(specs$size$value, "m")
  expect_identical(specs$size$choices, c("s", "m", "l"))
  expect_identical(specs$size$label, "Size")
  expect_true(specs$size$container)
})

test_that("mcp_action_button() is an action input, as the bridge treats it", {
  spec <- describe_one(mcp_action_button("run", "Run"))
  expect_identical(spec$kind, "action")
  expect_identical(spec$value, action_value(0L))
  expect_true(spec$bound)
})

test_that("describe_ui_inputs() walks whole pages and keeps the first of a duplicated id", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(
    shiny::sidebarLayout(
      shiny::sidebarPanel(
        shiny::selectInput("x", "X", c("a", "b")),
        list(
          shiny::numericInput("n", "N", 1),
          htmltools::tagList(shiny::textInput("t", "T"))
        )
      ),
      shiny::mainPanel(shiny::textInput("x", "Duplicate", "dup"))
    )
  )
  specs <- describe_ui_inputs(ui)
  expect_named(specs, c("x", "n", "t"))
  expect_identical(specs$x$kind, "select")
  # The <input>s inside groups and date pickers aren't inputs of their own.
  group_ui <- htmltools::tagList(
    shiny::dateRangeInput("span", "Span"),
    shiny::radioButtons("r", "R", c("a", "b"))
  )
  expect_named(describe_ui_inputs(group_ui), c("span", "r"))
  expect_length(describe_ui_inputs(htmltools::div("no inputs")), 0)
})

# ---- Marked inputs (bindMcp()) ----

test_that("tag_is_bound() sees bindMcp() on every kind of input", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::selectInput("sel", "Sel", c("a", "b")) |> bindMcp(),
    shiny::textInput("txt", "Txt") |> bindMcp(),
    shiny::numericInput("num", "Num", 1) |> bindMcp(),
    shiny::checkboxInput("chk", "Chk") |> bindMcp(),
    shiny::sliderInput("sld", "Sld", 0, 10, 5) |> bindMcp(),
    shiny::actionButton("go", "Go") |> bindMcp(),
    shiny::radioButtons("rad", "Rad", c("a", "b")) |> bindMcp(),
    shiny::checkboxGroupInput("grp", "Grp", c("a", "b")) |> bindMcp(),
    shiny::dateInput("dt", "Dt") |> bindMcp(),
    shiny::dateRangeInput("dr", "Dr") |> bindMcp(),
    shiny::textInput("plain", "Plain")
  )
  bound <- vapply(describe_ui_inputs(ui), function(s) s$bound, logical(1))
  expect_identical(
    bound,
    c(
      sel = TRUE,
      txt = TRUE,
      num = TRUE,
      chk = TRUE,
      sld = TRUE,
      go = TRUE,
      rad = TRUE,
      grp = TRUE,
      dt = TRUE,
      dr = TRUE,
      plain = FALSE
    )
  )
})

test_that("tag_is_bound() accepts a marker on the tag or an element inside it", {
  own <- htmltools::tags$select(id = "x", `data-shinymcp-input` = "x")
  expect_true(tag_is_bound(own, "x"))
  inner <- htmltools::div(
    id = "grp",
    htmltools::tags$input(type = "radio", `data-shinymcp-input` = "grp")
  )
  expect_true(tag_is_bound(inner, "grp"))
  other <- htmltools::div(
    id = "grp",
    htmltools::tags$input(
      type = "radio",
      `data-shinymcp-input` = "something-else"
    )
  )
  expect_false(tag_is_bound(other, "grp"))
  expect_false(tag_is_bound(htmltools::tags$select(id = "x"), "x"))
})

# ---- describe_ui_outputs() ----

test_that("describe_ui_outputs() finds every kind of Shiny output", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::plotOutput("p"),
    shiny::plotOutput("p2", width = "500px", height = "250px"),
    shiny::textOutput("t"),
    shiny::verbatimTextOutput("v"),
    shiny::tableOutput("tb"),
    shiny::uiOutput("u"),
    shiny::htmlOutput("h"),
    shiny::imageOutput("i"),
    shiny::downloadButton("db", "DB"),
    shiny::downloadLink("dl", "DL"),
    shiny::textOutput("t")
  )
  specs <- describe_ui_outputs(ui)
  expect_named(specs, c("p", "p2", "t", "v", "tb", "u", "h", "i", "db", "dl"))
  types <- vapply(specs, function(s) s$type, character(1))
  expect_identical(
    unname(types),
    c(
      "plot",
      "plot",
      "text",
      "text",
      "table",
      "html",
      "html",
      "plot",
      "download",
      "download"
    )
  )
  expect_false(any(vapply(specs, function(s) s$bound, logical(1))))
  expect_identical(specs$p$size, list(height = 400))
  expect_identical(specs$p2$size, list(width = 500, height = 250))
  expect_null(specs$t$size)
})

test_that("DT outputs are tables", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("DT")
  specs <- describe_ui_outputs(DT::DTOutput("dt"))
  expect_identical(specs$dt$type, "table")
})

test_that("marked outputs are bound and may be renamed", {
  skip_if_not_installed("shiny")
  ui <- htmltools::tagList(
    shiny::textOutput("summary") |> bindMcp(),
    shiny::textOutput("shown_as") |> bindMcp(id = "alias"),
    shiny::plotOutput("plot")
  )
  specs <- describe_ui_outputs(ui)
  expect_named(specs, c("summary", "alias", "plot"))
  expect_true(specs$summary$bound)
  expect_identical(specs$alias$dom_id, "shown_as")
  expect_true(specs$alias$bound)
  expect_false(specs$plot$bound)
})

test_that("output_size_from_style() reads pixel widths and heights only", {
  expect_null(output_size_from_style(NULL))
  expect_identical(
    output_size_from_style("width:100%;height:300px;"),
    list(height = 300)
  )
  expect_identical(
    output_size_from_style("width: 500px; height: 250.5px"),
    list(width = 500, height = 250.5)
  )
  # min-/max- properties aren't the size.
  expect_identical(
    output_size_from_style("min-width:100px;max-height:50px;height:20px"),
    list(height = 20)
  )
  expect_length(output_size_from_style("height: 50vh"), 0)
})

# ---- JSON Schema for the model's tool ----

test_that("MODEL_INPUT_KINDS leaves out buttons, passwords and files", {
  expect_false(any(c("action", "password", "file") %in% MODEL_INPUT_KINDS))
  expect_true(all(
    c("select", "slider", "date-range", "textarea") %in% MODEL_INPUT_KINDS
  ))
})

test_that("selects and radios become enums", {
  spec <- list(
    id = "x",
    kind = "select",
    label = "Pick",
    value = "b",
    choices = c("a", "b")
  )
  expect_identical(
    input_json_schema(spec),
    list(
      type = "string",
      enum = I(c("a", "b")),
      description = "Pick. Default: b."
    )
  )
  spec$kind <- "radio"
  expect_identical(input_json_schema(spec)$enum, I(c("a", "b")))
})

test_that("long choice lists are described instead of enumerated", {
  choices <- paste0("c", 1:201)
  schema <- input_json_schema(list(
    id = "x",
    kind = "select",
    label = "Pick",
    value = "c1",
    choices = choices
  ))
  expect_null(schema$enum)
  expect_identical(
    schema$description,
    "Pick (one of 201 values, e.g. c1, c2, c3, c4, c5). Default: c1."
  )
})

test_that("multiple selections become arrays", {
  spec <- list(
    id = "x",
    kind = "select-multiple",
    label = "Pick",
    value = c("a", "b"),
    choices = c("a", "b", "c")
  )
  schema <- input_json_schema(spec)
  expect_identical(schema$type, "array")
  expect_identical(
    schema$items,
    list(type = "string", enum = I(c("a", "b", "c")))
  )
  expect_identical(
    schema$description,
    "Pick (any number of values). Default: a, b."
  )
  spec$kind <- "checkbox-group"
  expect_identical(input_json_schema(spec)$type, "array")
})

test_that("checkboxes, numbers and text have plain types", {
  expect_identical(
    input_json_schema(list(
      id = "f",
      kind = "checkbox",
      label = "Flag",
      value = TRUE
    )),
    list(type = "boolean", description = "Flag. Default: true.")
  )

  number <- input_json_schema(list(
    id = "n",
    kind = "number",
    label = "N",
    value = 3,
    min = 0,
    max = 10
  ))
  expect_identical(number$type, "number")
  expect_identical(number$minimum, 0)
  expect_identical(number$maximum, 10)
  expect_identical(number$description, "N (min 0, max 10). Default: 3.")
  # An empty number has no default.
  expect_identical(
    input_json_schema(list(
      id = "n",
      kind = "number",
      label = "N",
      value = NA_real_
    ))$description,
    "N."
  )

  expect_identical(
    input_json_schema(list(
      id = "t",
      kind = "text",
      label = "Name",
      value = "hello"
    )),
    list(type = "string", description = "Name. Default: hello.")
  )
  expect_identical(
    input_json_schema(list(
      id = "t",
      kind = "textarea",
      label = NULL,
      value = ""
    )),
    list(type = "string", description = "t.")
  )
})

test_that("sliders are bounded numbers, dates or two-item arrays", {
  slider <- input_json_schema(list(
    id = "s",
    kind = "slider",
    label = "S",
    value = 40,
    min = 0,
    max = 100,
    data_type = "number"
  ))
  expect_identical(slider$type, "number")
  expect_identical(slider$minimum, 0)
  expect_identical(slider$maximum, 100)

  range <- input_json_schema(list(
    id = "r",
    kind = "slider-range",
    label = "R",
    value = c(2, 7),
    min = 0,
    max = 10,
    data_type = "number"
  ))
  expect_identical(range$type, "array")
  expect_identical(
    range$items,
    list(type = "number", minimum = 0, maximum = 10)
  )
  expect_identical(range$minItems, 2L)
  expect_identical(range$maxItems, 2L)
  expect_identical(
    range$description,
    "R (start and end, min 0, max 10). Default: 2, 7."
  )

  date <- input_json_schema(list(
    id = "d",
    kind = "slider",
    label = "D",
    value = as.Date("2024-06-01"),
    min = as.Date("2024-01-01"),
    max = as.Date("2024-12-31"),
    data_type = "date"
  ))
  expect_identical(date$type, "string")
  expect_identical(date$format, "date")
  expect_identical(
    date$description,
    "D (min 2024-01-01, max 2024-12-31). Default: 2024-06-01."
  )

  datetime <- input_json_schema(list(
    id = "t",
    kind = "slider",
    label = "T",
    value = as.POSIXct("2024-01-01 12:00", tz = "UTC"),
    data_type = "datetime"
  ))
  expect_identical(datetime$format, "date-time")

  date_range <- input_json_schema(list(
    id = "dr",
    kind = "slider-range",
    label = "DR",
    value = as.Date(c("2024-02-01", "2024-03-01")),
    data_type = "date"
  ))
  expect_identical(date_range$items, list(type = "string", format = "date"))
  expect_identical(
    date_range$description,
    "DR (start and end). Default: 2024-02-01, 2024-03-01."
  )
})

test_that("dates and date ranges are ISO strings", {
  date <- input_json_schema(list(
    id = "d",
    kind = "date",
    label = "When",
    value = as.Date("2024-03-15"),
    min = "2024-01-01",
    max = "2024-12-31"
  ))
  expect_identical(
    date,
    list(
      type = "string",
      format = "date",
      description = "When (YYYY-MM-DD, min 2024-01-01, max 2024-12-31). Default: 2024-03-15."
    )
  )
  range <- input_json_schema(list(
    id = "r",
    kind = "date-range",
    label = "Span",
    value = as.Date(c("2024-01-01", "2024-02-01"))
  ))
  expect_identical(range$type, "array")
  expect_identical(range$items, list(type = "string", format = "date"))
  expect_identical(range$minItems, 2L)
  expect_identical(
    range$description,
    "Span (start and end dates, YYYY-MM-DD). Default: 2024-01-01, 2024-02-01."
  )
})

test_that("buttons are booleans that press them", {
  schema <- input_json_schema(list(
    id = "go",
    kind = "action",
    label = "Go now",
    value = action_value(0L)
  ))
  expect_identical(
    schema,
    list(
      type = "boolean",
      description = "Set to true to press the 'Go now' button after the other inputs are set."
    )
  )
})

test_that("format_input_default() and format_input_scalar() write defaults", {
  expect_null(format_input_default(list(
    kind = "action",
    value = action_value(3L)
  )))
  expect_null(format_input_default(list(kind = "text", value = NULL)))
  expect_null(format_input_default(list(kind = "text", value = "")))
  expect_null(format_input_default(list(kind = "number", value = NA_real_)))
  expect_null(format_input_default(list(
    kind = "select-multiple",
    value = character()
  )))
  expect_identical(
    format_input_default(list(kind = "checkbox", value = FALSE)),
    "false"
  )
  expect_identical(
    format_input_default(list(kind = "number", value = 1e6)),
    "1000000"
  )
  expect_identical(
    format_input_default(list(kind = "slider-range", value = c(0.5, 2))),
    "0.5, 2"
  )

  expect_identical(format_input_scalar(as.Date("2024-01-02")), "2024-01-02")
  expect_identical(
    format_input_scalar(as.POSIXct("2024-01-02 03:04:05", tz = "UTC")),
    "2024-01-02T03:04:05Z"
  )
  expect_identical(format_input_scalar(12.5), "12.5")
})

# ---- coerce_input_value(): JSON values to Shiny values ----

test_that("selects and radios take one string; empty values are NULL", {
  spec <- list(id = "x", kind = "select", choices = c("4", "6", "8"))
  expect_identical(coerce_input_value("6", spec), "6")
  expect_identical(coerce_input_value(list("8"), spec), "8")
  expect_identical(coerce_input_value(6, spec), "6")
  expect_identical(coerce_input_value(c("4", "8"), spec), "4")
  expect_null(coerce_input_value(NULL, spec))
  expect_null(coerce_input_value(list(), spec))
  # From the page, values aren't checked against the choices.
  expect_identical(coerce_input_value("12", spec), "12")
  # From the model, they are.
  expect_error(
    coerce_input_value("12", spec, strict = TRUE),
    class = "shinymcp_error_arguments"
  )
  expect_error(
    coerce_input_value("12", spec, strict = TRUE),
    "not a valid value for x"
  )

  spec$kind <- "radio"
  expect_identical(coerce_input_value(list("4"), spec, strict = TRUE), "4")
  expect_null(coerce_input_value(NULL, spec, strict = TRUE))
})

test_that("multiple selects and checkbox groups take character vectors", {
  spec <- list(id = "x", kind = "checkbox-group", choices = c("a", "b", "c"))
  expect_identical(coerce_input_value(list("a", "c"), spec), c("a", "c"))
  expect_identical(coerce_input_value("b", spec), "b")
  expect_null(coerce_input_value(list(), spec))
  expect_null(coerce_input_value(NULL, spec))
  expect_error(
    coerce_input_value(list("a", "z"), spec, strict = TRUE),
    class = "shinymcp_error_arguments"
  )
  spec$kind <- "select-multiple"
  expect_identical(
    coerce_input_value(list("c", "a"), spec, strict = TRUE),
    c("c", "a")
  )
})

test_that("checkboxes are TRUE only for true values", {
  spec <- list(id = "f", kind = "checkbox")
  expect_true(coerce_input_value(TRUE, spec))
  expect_true(coerce_input_value("true", spec))
  expect_true(coerce_input_value(1, spec))
  expect_false(coerce_input_value(FALSE, spec))
  expect_false(coerce_input_value("false", spec))
  expect_false(coerce_input_value("yes", spec))
  expect_false(coerce_input_value(NULL, spec))
  expect_true(coerce_input_value(TRUE, list(id = "s", kind = "switch")))
})

test_that("numbers are doubles; empty values are NA", {
  spec <- list(id = "n", kind = "number")
  expect_identical(coerce_input_value(3L, spec), 3)
  expect_identical(coerce_input_value("3.5", spec), 3.5)
  expect_identical(coerce_input_value(list(2), spec), 2)
  expect_identical(coerce_input_value(NULL, spec), NA_real_)
  expect_identical(coerce_input_value("", spec), NA_real_)
  expect_identical(coerce_input_value("lots", spec), NA_real_)
  expect_error(
    coerce_input_value("lots", spec, strict = TRUE),
    class = "shinymcp_error_arguments"
  )
  expect_identical(coerce_input_value(NULL, spec, strict = TRUE), NA_real_)
})

test_that("slider values are clamped to the slider's bounds", {
  spec <- list(
    id = "s",
    kind = "slider",
    value = 40,
    min = 0,
    max = 100,
    data_type = "number"
  )
  expect_identical(coerce_input_value(55, spec), 55)
  expect_identical(coerce_input_value("42", spec), 42)
  expect_identical(coerce_input_value(150, spec), 100)
  expect_identical(coerce_input_value(-5, spec), 0)
  expect_identical(coerce_input_value(list(3, 9), spec), 3)
  # No value means the slider's default.
  expect_identical(coerce_input_value(NULL, spec), 40)
  expect_error(
    coerce_input_value("high", spec, strict = TRUE),
    class = "shinymcp_error_arguments"
  )

  range <- list(
    id = "r",
    kind = "slider-range",
    value = c(2, 7),
    min = 0,
    max = 10,
    data_type = "number"
  )
  expect_identical(coerce_input_value(list(9, 1), range), c(1, 9))
  expect_identical(coerce_input_value(5, range), c(5, 5))
  expect_identical(coerce_input_value(list(-5, 200), range), c(0, 10))
})

test_that("date slider values may be dates or milliseconds since the epoch", {
  spec <- list(
    id = "d",
    kind = "slider",
    value = as.Date("2024-06-01"),
    min = as.Date("2024-01-01"),
    max = as.Date("2024-12-31"),
    data_type = "date"
  )
  expect_identical(
    coerce_input_value("2024-07-04", spec, strict = TRUE),
    as.Date("2024-07-04")
  )
  expect_identical(
    coerce_input_value("2030-01-01", spec),
    as.Date("2024-12-31")
  )
  ms <- as.numeric(as.POSIXct("2024-03-01", tz = "UTC")) * 1000
  expect_identical(coerce_input_value(ms, spec), as.Date("2024-03-01"))

  range <- spec
  range$kind <- "slider-range"
  expect_identical(
    coerce_input_value(list("2024-05-01", "2024-04-01"), range, strict = TRUE),
    as.Date(c("2024-04-01", "2024-05-01"))
  )

  expect_identical(slider_value_from_number(ms, "date"), as.Date("2024-03-01"))
  expect_identical(slider_value_from_number(5, "number"), 5)
  expect_identical(
    as.numeric(slider_value_from_number(ms, "datetime")),
    as.numeric(as.POSIXct("2024-03-01", tz = "UTC"))
  )
})

test_that("datetime slider values keep their time of day", {
  spec <- list(
    id = "t",
    kind = "slider",
    value = as.POSIXct("2024-01-01 12:00", tz = "UTC"),
    min = as.POSIXct("2024-01-01 00:00", tz = "UTC"),
    max = as.POSIXct("2024-01-02 00:00", tz = "UTC"),
    data_type = "datetime"
  )
  value <- coerce_input_value("2024-01-01T15:30:00.000Z", spec, strict = TRUE)
  expect_identical(
    format(value, "%Y-%m-%d %H:%M", tz = "UTC"),
    "2024-01-01 15:30"
  )
})

test_that("dates and date ranges become Date vectors", {
  date <- list(id = "d", kind = "date")
  expect_identical(
    coerce_input_value("2024-03-01", date, strict = TRUE),
    as.Date("2024-03-01")
  )
  expect_null(coerce_input_value(NULL, date))
  expect_null(coerce_input_value("", date))

  range <- list(id = "r", kind = "date-range")
  expect_identical(
    coerce_input_value(list("2024-01-01", "2024-02-01"), range, strict = TRUE),
    as.Date(c("2024-01-01", "2024-02-01"))
  )
  expect_identical(
    coerce_input_value("2024-01-01", range),
    as.Date(c("2024-01-01", "2024-01-01"))
  )
  expect_null(coerce_input_value(list(), range))
  # A partly unreadable range is an error for the model.
  expect_error(
    coerce_input_value(list("2024-01-01", "soon"), range, strict = TRUE),
    class = "shinymcp_error_arguments"
  )
})

test_that("unreadable dates from the model are argument errors", {
  date <- list(id = "when", kind = "date")
  expect_error(
    coerce_input_value("tomorrow", date, strict = TRUE),
    class = "shinymcp_error_arguments"
  )
  expect_error(
    coerce_input_value("tomorrow", date, strict = TRUE),
    "when"
  )
})

test_that("text inputs are single strings", {
  for (kind in c("text", "textarea", "password")) {
    spec <- list(id = "t", kind = kind)
    expect_identical(coerce_input_value("hi", spec), "hi")
    expect_identical(coerce_input_value(NULL, spec), "")
    expect_identical(coerce_input_value(5, spec), "5")
    expect_identical(coerce_input_value(list("a", "b"), spec), "ab")
  }
})

test_that("action buttons are counters of class shinyActionButtonValue", {
  spec <- list(id = "go", kind = "action")
  pressed <- coerce_input_value(TRUE, spec, previous = action_value(2L))
  expect_identical(pressed, action_value(3L))
  expect_identical(class(pressed), c("shinyActionButtonValue", "integer"))
  expect_identical(
    coerce_input_value(FALSE, spec, previous = action_value(2L)),
    action_value(2L)
  )
  expect_identical(coerce_input_value(TRUE, spec), action_value(1L))
  # The page sends its count.
  expect_identical(
    coerce_input_value(5, spec, previous = action_value(2L)),
    action_value(5L)
  )
  expect_identical(
    coerce_input_value(NULL, spec, previous = action_value(2L)),
    action_value(2L)
  )
})

test_that("files have no value and unknown kinds pass through", {
  expect_null(coerce_input_value("upload.csv", list(id = "f", kind = "file")))
  expect_identical(
    coerce_input_value(list("a", "b"), list(id = "u", kind = "unknown")),
    c("a", "b")
  )
  expect_identical(coerce_input_value(list(a = 1), list(id = "u")), list(a = 1))
  expect_identical(coerce_input_value(7, list()), 7)
})

# ---- Input values for the page ----

test_that("input_value_for_page() turns Shiny values into JSON values", {
  expect_null(input_value_for_page(NULL))
  expect_identical(input_value_for_page(action_value(4L)), 4L)
  expect_identical(input_value_for_page(as.Date("2024-01-02")), "2024-01-02")
  expect_identical(
    input_value_for_page(as.Date(c("2024-01-02", "2024-01-03"))),
    I(c("2024-01-02", "2024-01-03"))
  )
  expect_identical(
    input_value_for_page(as.POSIXct("2024-01-02 03:04:05", tz = "UTC")),
    "2024-01-02T03:04:05Z"
  )
  expect_identical(input_value_for_page(c("a", "b")), I(c("a", "b")))
  expect_identical(input_value_for_page(c(1, 2)), I(c(1, 2)))
  expect_null(input_value_for_page(NA_real_))
  expect_identical(input_value_for_page("a"), "a")
  expect_identical(input_value_for_page(TRUE), TRUE)
  # Single values are scalars in JSON; vectors stay arrays.
  expect_identical(
    as.character(to_json(input_value_for_page(c("a", "b")))),
    '["a","b"]'
  )
  expect_identical(as.character(to_json(input_value_for_page("a"))), '"a"')
})

# ---- html_options() ----

test_that("html_options() reads option values, labels and selections", {
  html <- paste0(
    '<option value="a">Alpha</option>',
    '<option value="b" selected>Beta</option>',
    "<option value='c'>Gamma</option>",
    "<option>Plain</option>",
    '<option value="d&amp;e" selected="selected">D &amp; E</option>',
    '<option value="">None</option>'
  )
  parsed <- html_options(html)
  expect_identical(parsed$values, c("a", "b", "c", "Plain", "d&e", ""))
  expect_identical(
    parsed$labels,
    c("Alpha", "Beta", "Gamma", "Plain", "D & E", "None")
  )
  expect_identical(parsed$selected, c("b", "d&e"))
})

test_that("html_options() handles optgroups and strings without options", {
  html <- paste0(
    '<optgroup label="East"><option value="NY">New York</option></optgroup>',
    '<optgroup label="West"><option value="CA" selected>California</option></optgroup>'
  )
  parsed <- html_options(html)
  expect_identical(parsed$values, c("NY", "CA"))
  expect_identical(parsed$selected, "CA")

  empty <- list(
    values = character(),
    labels = character(),
    selected = character()
  )
  expect_identical(html_options(""), empty)
  expect_identical(html_options("<p>no options</p>"), empty)
})

test_that("small helpers behave", {
  expect_identical(as_number_or_null("3.5"), 3.5)
  expect_null(as_number_or_null(""))
  expect_null(as_number_or_null(NULL))
  expect_null(as_number_or_null("abc"))
  expect_identical(as_number_or_na(NULL), NA_real_)
  expect_identical(
    action_value(2),
    structure(2L, class = c("shinyActionButtonValue", "integer"))
  )
  expect_null(attr_or_null(NULL, "id"))
  expect_identical(attr_or_null(htmltools::div(id = "x"), "id"), "x")
  expect_identical(
    tag_text(htmltools::div(
      "a",
      htmltools::tags$b("b"),
      htmltools::tags$script("ignored")
    )),
    "a b"
  )
})

test_that("date-times are read in UTC, with or without an offset", {
  out <- parse_datetime_utc(c(
    "2024-01-01T15:30:00Z",
    "2024-01-01T15:30:00+02:00",
    "2024-01-01 15:30",
    "2024-01-01",
    "2024-01-01T15:30:00.250-0130",
    "soon",
    NA
  ))
  expect_identical(attr(out, "tzone"), "UTC")
  expect_identical(
    format(out, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    c(
      "2024-01-01 15:30:00",
      "2024-01-01 13:30:00",
      "2024-01-01 15:30:00",
      "2024-01-01 00:00:00",
      "2024-01-01 17:00:00",
      NA,
      NA
    )
  )
})

test_that("slider values written as milliseconds are read for date sliders", {
  spec <- list(id = "d", kind = "slider", data_type = "date")
  ms <- format(
    1000 * as.numeric(as.POSIXct("2024-06-01", tz = "UTC")),
    scientific = FALSE
  )
  expect_identical(coerce_input_value(ms, spec), as.Date("2024-06-01"))
})

test_that("tabsets with an id are inputs whose value is the shown tab", {
  skip_if_not_installed("shiny")
  ui <- shiny::fluidPage(shiny::tabsetPanel(
    id = "tabs",
    selected = "b",
    shiny::tabPanel(
      "First",
      "1",
      value = "a",
      shiny::textInput("inside", "Inside")
    ),
    shiny::tabPanel("Second", "2", value = "b"),
    shiny::navbarMenu("More", shiny::tabPanel("Third", "3", value = "c"))
  ))
  specs <- describe_ui_inputs(ui)
  expect_named(specs, c("tabs", "inside"))
  tabs <- specs$tabs
  expect_identical(tabs$kind, "tabs")
  expect_identical(tabs$choices, c("a", "b", "c"))
  expect_identical(tabs$choice_labels, c("First", "Second", "Third"))
  expect_identical(tabs$value, "b")

  schema <- input_json_schema(tabs)
  expect_identical(schema$type, "string")
  expect_identical(unclass(schema$enum), c("a", "b", "c"))
  expect_match(schema$description, "Default: b.", fixed = TRUE)
  expect_identical(coerce_input_value("c", tabs, strict = TRUE), "c")
  expect_error(
    coerce_input_value("z", tabs, strict = TRUE),
    class = "shinymcp_error_arguments"
  )

  # Tabsets without an id aren't inputs.
  plain <- describe_ui_inputs(shiny::tabsetPanel(shiny::tabPanel("A", "a")))
  expect_length(plain, 0)
})

test_that("bslib navsets and navbar pages are tab inputs too", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  navset <- describe_ui_inputs(bslib::page_fluid(bslib::navset_tab(
    id = "nt",
    selected = "Two",
    bslib::nav_panel("One", "1"),
    bslib::nav_panel("Two", "2")
  )))
  expect_identical(navset$nt$choices, c("One", "Two"))
  expect_identical(navset$nt$value, "Two")

  navbar <- describe_ui_inputs(shiny::navbarPage(
    "App",
    id = "nav",
    shiny::tabPanel("P", "p"),
    shiny::tabPanel("Q", "q")
  ))
  expect_identical(navbar$nav$kind, "tabs")
  expect_identical(navbar$nav$value, "P")
})

test_that("shinyWidgets inputs are described for the model", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinyWidgets")
  ui <- shiny::fluidPage(
    shinyWidgets::radioGroupButtons(
      "gear",
      "Gears",
      c("3", "4", "5"),
      selected = "4"
    ),
    shinyWidgets::checkboxGroupButtons(
      "opts",
      "Options",
      c("a", "b"),
      selected = "b"
    ),
    shinyWidgets::pickerInput(
      "cyl",
      "Cylinders",
      c("4", "6", "8"),
      selected = "6",
      multiple = TRUE
    ),
    shinyWidgets::switchInput("big", "Big cars"),
    shinyWidgets::sliderTextInput(
      "size",
      "Size",
      c("small", "medium", "large"),
      selected = "medium"
    ),
    shinyWidgets::sliderTextInput(
      "span",
      "Span",
      c("lo", "mid", "hi"),
      selected = c("lo", "hi")
    )
  )
  specs <- suppressPackageStartupMessages(describe_ui_inputs(ui))
  kind <- function(id) specs[[id]]$kind
  expect_identical(kind("gear"), "radio")
  expect_identical(specs$gear$choices, c("3", "4", "5"))
  expect_identical(specs$gear$value, "4")
  expect_identical(specs$gear$label, "Gears")
  expect_identical(kind("opts"), "checkbox-group")
  expect_identical(specs$opts$value, "b")
  expect_identical(kind("cyl"), "select-multiple")
  expect_identical(kind("big"), "checkbox")
  expect_identical(specs$big$label, "Big cars")
  expect_identical(kind("size"), "select")
  expect_identical(specs$size$choices, c("small", "medium", "large"))
  expect_identical(specs$size$value, "medium")
  expect_identical(kind("span"), "select-multiple")
  expect_identical(specs$span$value, c("lo", "hi"))
})

test_that("pages with text sliders keep ionRangeSlider", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinyWidgets")
  plain <- mcp_app(shiny::fluidPage(shiny::sliderInput(
    "n",
    "N",
    1,
    10,
    5
  )))$html_resource()
  expect_no_match(
    plain,
    "data-shinymcp-dep=\"ionrangeslider-javascript",
    fixed = TRUE
  )
  text <- mcp_app(shiny::fluidPage(
    shinyWidgets::sliderTextInput("size", "Size", c("s", "m", "l"))
  ))$html_resource()
  expect_match(
    text,
    "data-shinymcp-dep=\"ionrangeslider-javascript",
    fixed = TRUE
  )
})
