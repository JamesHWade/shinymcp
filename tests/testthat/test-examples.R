# Runnability checks for every rung of the "shinymcp by example" ladder.
# Each example must actually build and render, not merely parse. MCP-App examples
# are driven through the full preview path (which sources app.R, builds the ui://
# resource, and starts the host server); the serve-to-client server is built from
# its serve.R; the full Shiny examples are sourced into a shiny app object.

require_pkgs <- function(pkgs) {
  for (p in pkgs) {
    skip_if_not_installed(p)
  }
}

example_dir <- function(name) {
  dir <- system.file("examples", name, package = "shinymcp")
  skip_if(dir == "", paste0("example not installed: ", name))
  dir
}

# --- MCP-App examples: verified through the full preview render path -----------

preview_examples <- list(
  "hello-mcp-minimal" = c("ellmer", "httpuv"),
  "hello-mcp" = c("ellmer", "httpuv", "bslib", "base64enc"),
  "penguins" = c(
    "ellmer",
    "httpuv",
    "bslib",
    "ggplot2",
    "palmerpenguins",
    "shiny",
    "base64enc"
  ),
  "bslib-inputs" = c("ellmer", "httpuv", "bslib", "shiny"),
  "bind-mcp-demo" = c("ellmer", "httpuv", "bslib", "shiny", "base64enc"),
  "multi-tool" = c("ellmer", "httpuv", "shiny", "base64enc"),
  "module-tool" = c("ellmer", "httpuv", "bslib", "shiny", "base64enc"),
  "converted-dashboard" = c("ellmer", "httpuv"),
  "data-explorer" = c(
    "ellmer",
    "httpuv",
    "bslib",
    "ggplot2",
    "shiny",
    "base64enc"
  )
)

for (nm in names(preview_examples)) {
  local({
    name <- nm
    deps <- preview_examples[[nm]]
    test_that(paste0("example renders via preview: ", name), {
      skip_on_cran()
      require_pkgs(deps)
      dir <- example_dir(name)
      srv <- preview_app(dir, launch = FALSE)
      on.exit(srv$stop(), add = TRUE)
      expect_match(srv$url, "^http://127\\.0\\.0\\.1:")
    })
  })
}

# --- serve-to-client: a stdio server entry point (serve.R, not app.R) ----------

test_that("example builds: serve-to-client", {
  skip_if_not_installed("ellmer")
  path <- file.path(example_dir("serve-to-client"), "serve.R")
  env <- new.env()
  env$serve <- function(app, ...) app # stub so the stdio loop never starts
  sys.source(path, envir = env)
  expect_s3_class(env$app, "McpApp")
  expect_identical(env$app$name, "shinymcp-demo")
})

# --- Full Shiny examples: app.R must source into a shiny app object ------------

shiny_examples <- list(
  "shinychat-card" = c("shiny", "bslib", "ellmer", "shinychat"),
  "embed-in-shiny" = c("shiny", "bslib", "ellmer"),
  "rpharma-hangout" = c("shiny", "bslib", "ellmer", "shinychat")
)

for (nm in names(shiny_examples)) {
  local({
    name <- nm
    deps <- shiny_examples[[nm]]
    test_that(paste0("example builds shiny app: ", name), {
      require_pkgs(deps)
      path <- file.path(example_dir(name), "app.R")
      env <- new.env()
      built <- new.env()
      env$shinyApp <- function(ui, server, ...) {
        built$ok <- TRUE
        structure(list(), class = "shiny.appobj")
      }
      sys.source(path, envir = env)
      expect_true(isTRUE(built$ok))
    })
  })
}
