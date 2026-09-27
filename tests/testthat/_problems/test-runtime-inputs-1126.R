# Extracted from test-runtime-inputs.R:1126

# prequel ----------------------------------------------------------------------
describe_one <- function(tag) {
  specs <- describe_ui_inputs(tag)
  expect_length(specs, 1)
  specs[[1]]
}

# test -------------------------------------------------------------------------
expect_null(input_value_for_page(NULL))
expect_identical(input_value_for_page(action_value(4L)), 4L)
expect_identical(input_value_for_page(as.Date("2024-01-02")), "2024-01-02")
expect_identical(
  input_value_for_page(as.Date(c("2024-01-02", "2024-01-03"))),
  I(c("2024-01-02", "2024-01-03"))
)
expect_identical(
  input_value_for_page(as.POSIXct("2024-01-02 03:04:05", tz = "UTC")),
  "2024-01-02T03:04:05"
)
