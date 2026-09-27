# Extracted from test-runtime-inputs.R:874

# prequel ----------------------------------------------------------------------
describe_one <- function(tag) {
  specs <- describe_ui_inputs(tag)
  expect_length(specs, 1)
  specs[[1]]
}

# test -------------------------------------------------------------------------
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
  "2024-01-02T03:04:05"
)
