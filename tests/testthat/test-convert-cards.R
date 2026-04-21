test_that("as_mcp_apps splits connected components into multiple cards", {
  app_dir <- fixture_chained_reactive_app()
  withr::defer(unlink(app_dir, recursive = TRUE))

  apps <- as_mcp_apps(app_dir)

  expect_true(length(apps) >= 2)
  expect_true(all(vapply(apps, inherits, logical(1), "McpApp")))
})

test_that("convert_app cards mode writes card scaffold directories", {
  app_dir <- fixture_chained_reactive_app()
  out_dir <- tempfile("mcp-cards")
  withr::defer({
    unlink(app_dir, recursive = TRUE)
    unlink(out_dir, recursive = TRUE)
  })

  apps <- convert_app(app_dir, output_dir = out_dir, mode = "cards")

  expect_true(length(apps) >= 2)
  expect_true(file.exists(file.path(out_dir, "CONVERSION_NOTES.md")))

  card_dirs <- list.dirs(out_dir, recursive = FALSE, full.names = FALSE)
  expect_true(length(card_dirs) >= 2)

  notes <- paste(readLines(file.path(out_dir, "CONVERSION_NOTES.md")), collapse = "\n")
  expect_match(notes, "scaffold-oriented")
  expect_match(notes, "Card mode")
})
