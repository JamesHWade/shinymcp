test_that("mcp_host_ui renders a host shell", {
  ui <- mcp_host_ui("card")
  rendered <- as.character(ui)

  expect_match(rendered, 'data-shinymcp-host')
  expect_match(rendered, 'data-shinymcp-host-frame')
  expect_match(rendered, "Apply")
  expect_match(rendered, "Reset")
})

test_that("mcp_embed requires an id outside a live session", {
  app <- mcp_app(htmltools::tags$div("test"), name = "embed-test")

  expect_error(
    mcp_embed(app),
    "Provide .*id.* outside a live Shiny session"
  )
})
