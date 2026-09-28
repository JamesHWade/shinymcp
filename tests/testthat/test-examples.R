# Every example must build and answer, not merely parse.

require_pkgs <- function(pkgs) {
  for (p in pkgs) {
    skip_if_not_installed(p)
  }
}

example_dir <- function(name) {
  dir <- system.file("examples", name, package = "shinymcp")
  if (!nzchar(dir)) {
    dir <- testthat::test_path("..", "..", "inst", "examples", name)
  }
  skip_if_not(dir.exists(dir), paste0("example not found: ", name))
  dir
}

# Apps: load app.R the way preview_app() and serve() do, build the page, and
# call the first tool the model can call.
app_examples <- list(
  "hello" = list(pkgs = "ellmer", args = list(dataset = "faithful")),
  "faithful" = list(pkgs = "shiny", args = list(bins = 12)),
  "fuel-economy" = list(
    pkgs = c("shiny", "bslib", "ggplot2"),
    args = list(class = list("suv", "pickup"), metric = "cty")
  ),
  "sample-size" = list(
    pkgs = c("ellmer", "shiny", "bslib"),
    args = list(delta = 0.5, sd = 1)
  ),
  "shiny-module" = list(pkgs = "shiny", args = list(bins = 10)),
  "shiny-packages" = list(
    pkgs = c("shiny", "shinyWidgets", "DT"),
    args = list(cyl = list("4", "6"))
  ),
  "rewritten-dashboard" = list(
    pkgs = c("ellmer", "shiny"),
    args = list(dataset = "iris", obs = 3)
  ),
  "feature-tour" = list(pkgs = c("ellmer", "bslib"), args = list()),
  "ggplot-builder" = list(
    pkgs = c("ellmer", "bslib", "ggplot2", "palmerpenguins"),
    args = list()
  )
)

for (nm in names(app_examples)) {
  local({
    name <- nm
    spec <- app_examples[[nm]]
    test_that(paste0("the ", name, " example builds and answers its tool"), {
      skip_on_cran()
      require_pkgs(spec$pkgs)
      app <- suppressMessages(as_mcp_app(example_dir(name)))
      expect_s3_class(app, "McpApp")
      expect_match(app$html_resource(), "id=\"shinymcp-config\"", fixed = TRUE)

      tool <- app$tools("model")[[1]]
      result <- app$run_tool(tool$name, spec$args)
      expect_false(isTRUE(result$isError), info = result$content[[1]]$text)
      expect_true(nzchar(result$content[[1]]$text))
    })
  })
}

test_that("the hello example renders through preview_app()", {
  skip_on_cran()
  require_pkgs(c("ellmer", "httpuv"))
  preview <- suppressMessages(preview_app(example_dir("hello"), launch = FALSE))
  on.exit(preview$stop(), add = TRUE)
  expect_match(preview$url, "^http://127\\.0\\.0\\.1:")
})

test_that("the posit-connect example is a Shiny app with an MCP App next to it", {
  skip_on_cran()
  require_pkgs(c("shiny", "ellmer"))
  env <- new.env()
  app <- source(
    file.path(example_dir("posit-connect"), "app.R"),
    local = env
  )$value
  expect_s3_class(app, "shiny.appobj")
  expect_true(inherits(app$mcpServer, "McpServer"))
  mcp <- app$mcpServer$apps[[1]]
  expect_equal(mcp$name, "faithful")
  result <- mcp$run_tool("faithful_histogram", list(bins = 30))
  expect_false(isTRUE(result$isError))
  expect_equal(
    result$structuredContent$caption,
    "Showing 272 eruptions to you."
  )
})

test_that("the remote-host server serves its app", {
  require_pkgs(c("shiny", "ellmer"))
  env <- new.env()
  env$serve <- function(app, ...) app
  served <- source(
    file.path(example_dir("remote-host"), "serve.R"),
    local = env
  )$value
  expect_s3_class(served, "McpApp")
  result <- served$run_tool("faithful_histogram", list(bins = 10))
  expect_false(isTRUE(result$isError))
})

test_that("the local-clients server serves both of its apps", {
  require_pkgs(c("shiny", "ellmer"))
  env <- new.env()
  env$serve <- function(app, ...) app
  served <- source(
    file.path(example_dir("local-clients"), "serve.R"),
    local = env
  )$value
  server <- McpServer$new(served)
  expect_true(server$tool_app("faithful_histogram")$name == "faithful")
  expect_true(server$tool_app("summarize_dataset")$name == "dataset-summary")
})

# Shiny apps that host MCP Apps: app.R must source into a Shiny app object.
shiny_examples <- list(
  "shinychat" = c("shiny", "bslib", "ellmer", "shinychat"),
  "shiny-host" = c("shiny", "bslib", "ellmer"),
  "remote-host" = c("shiny", "bslib", "ellmer"),
  "rpharma-hangout" = c("shiny", "bslib", "ellmer", "shinychat")
)

for (nm in names(shiny_examples)) {
  local({
    name <- nm
    deps <- shiny_examples[[nm]]
    test_that(paste0("the ", name, " example builds a Shiny app"), {
      require_pkgs(deps)
      app <- suppressMessages(shiny::shinyAppDir(example_dir(name)))
      expect_s3_class(app, "shiny.appobj")
    })
  })
}
