# The app page: one self-contained HTML document (R/html.R).

local_dependency_dir <- function(env = parent.frame()) {
  dir <- tempfile("shinymcp-dep")
  dir.create(dir)
  writeLines(
    "var x = '</script><script>alert(1)</script>';",
    file.path(dir, "a.js")
  )
  writeLines("export const y = 1;", file.path(dir, "m.js"))
  writeLines(".a { color: red; } /* </style> */", file.path(dir, "a.css"))
  dir
}

# ---- The document ----

test_that("the page is a complete HTML document", {
  app <- mcp_app(
    htmltools::div("Test content"),
    name = "doc",
    title = "Doc <App>"
  )
  html <- app$html_resource()

  expect_type(html, "character")
  expect_length(html, 1)
  expect_match(html, "^<!DOCTYPE html>\n<html lang=\"en\" class=\"shinymcp\">")
  expect_match(html, '<meta charset="utf-8">', fixed = TRUE)
  expect_match(
    html,
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    fixed = TRUE
  )
  expect_match(
    html,
    '<meta name="color-scheme" content="light dark">',
    fixed = TRUE
  )
  expect_match(html, "<title>Doc &lt;App&gt;</title>", fixed = TRUE)
  expect_match(html, '<style id="shinymcp-style">', fixed = TRUE)
  expect_match(html, "Test content", fixed = TRUE)
  expect_match(html, "</html>$")
})

test_that("the title falls back to the app name", {
  html <- mcp_app(htmltools::div(), name = "untitled")$html_resource()
  expect_match(html, "<title>untitled</title>", fixed = TRUE)
})

test_that("fragments are wrapped in a main element in the body", {
  html <- mcp_app(htmltools::div("Fragment"), name = "fragment")$html_resource()

  expect_match(
    html,
    '<body data-shinymcp-body="">\n<main class="shinymcp-app">\n<div>Fragment</div>\n</main>',
    fixed = TRUE
  )
  expect_equal(helper_count(html, "<body"), 1)
})

test_that("the bridge and its configuration come once, at the end of the body", {
  html <- helper_greeter_app()$html_resource()

  expect_equal(helper_count(html, '<script id="shinymcp-config"'), 1)
  expect_equal(helper_count(html, '<script id="shinymcp-bridge">'), 1)
  config_at <- regexpr('<script id="shinymcp-config"', html, fixed = TRUE)
  bridge_at <- regexpr('<script id="shinymcp-bridge">', html, fixed = TRUE)
  body_end <- regexpr("</body>", html, fixed = TRUE)
  expect_true(config_at < bridge_at)
  expect_true(bridge_at < body_end)
  expect_true(regexpr("</main>", html, fixed = TRUE) < config_at)
  expect_match(html, bridge_js(), fixed = TRUE)
  expect_match(html, bridge_css(), fixed = TRUE)
})

test_that("the page is rendered the same way each time", {
  app <- helper_greeter_app()
  expect_identical(app$html_resource(), app$html_resource())
})

# ---- Configuration ----

test_that("the configuration describes the app's tools and outputs", {
  app <- mcp_app(
    htmltools::tagList(
      mcp_select("species", "Species", c("A", "B")),
      mcp_text("summary"),
      mcp_plot("chart")
    ),
    tools = list(
      list(
        name = "explore",
        description = "Explore",
        fun = function(species = "A", n = 1) list(summary = species),
        annotations = list(read_only_hint = TRUE)
      ),
      list(
        name = "approve",
        description = "Approve",
        fun = function(id) id,
        annotations = list(destructive_hint = TRUE)
      )
    ),
    name = "configured",
    version = "1.0.0",
    tool_visibility = list(approve = "app"),
    tool_outputs = list(explore = c("summary", "chart")),
    trigger = "change",
    debounce_ms = 100
  )
  config <- helper_page_config(app$html_resource())

  expect_equal(config$app, "configured")
  expect_equal(config$version, "1.0.0")
  expect_equal(config$appsProtocolVersion, SHINYMCP_APPS_PROTOCOL_VERSION)
  expect_equal(config$mode, "tools")
  expect_equal(
    config$tools,
    list(
      list(
        name = "explore",
        args = list("species", "n"),
        outputs = list("summary", "chart"),
        app = TRUE,
        model = TRUE,
        readOnly = TRUE
      ),
      list(
        name = "approve",
        args = list("id"),
        app = TRUE,
        model = FALSE,
        destructive = TRUE
      )
    )
  )
  expect_equal(config$outputs, list(summary = "text", chart = "plot"))
  expect_equal(config$trigger, "change")
  expect_equal(config$debounceMs, 100)
  expect_true(config$hostStyles)
  expect_true(config$modelContext)
  expect_equal(config$deps, list())
  expect_null(config$runtime)
})

test_that("the configuration lists ellmer tool arguments", {
  skip_if_not_installed("ellmer")
  app <- mcp_app(
    htmltools::div(),
    tools = list(ellmer::tool(
      fun = function(dataset = "mtcars", n_rows = 10) dataset,
      name = "get_summary",
      description = "Get summary",
      arguments = list(
        dataset = ellmer::type_string("Dataset name"),
        n_rows = ellmer::type_number("Number of rows")
      )
    )),
    name = "args-test"
  )
  config <- helper_page_config(app$html_resource())

  expect_equal(config$tools[[1]]$name, "get_summary")
  expect_equal(config$tools[[1]]$args, list("dataset", "n_rows"))
})

test_that("an app without tools or outputs has empty lists, not nulls", {
  html <- mcp_app(htmltools::div("Hello"), name = "empty-tools")$html_resource()
  json <- helper_script_text(
    html,
    '<script id="shinymcp-config" type="application/json">'
  )

  expect_match(json, '"tools":[]', fixed = TRUE)
  expect_match(json, '"outputs":{}', fixed = TRUE)
  expect_match(json, '"deps":[]', fixed = TRUE)
  expect_false(grepl('"trigger"', json, fixed = TRUE))
})

test_that("tools without arguments list an empty array of args", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "go", fun = function() 1)),
    name = "no-args"
  )
  json <- helper_script_text(
    app$html_resource(),
    '<script id="shinymcp-config" type="application/json">'
  )
  expect_match(
    json,
    '{"name":"go","args":[],"app":true,"model":true}',
    fixed = TRUE
  )
})

test_that("host styles and model context can be turned off", {
  app <- mcp_app(htmltools::div(), host_styles = FALSE, model_context = FALSE)
  config <- helper_page_config(app$html_resource())

  expect_false(config$hostStyles)
  expect_false(config$modelContext)
})

test_that("apps served from Shiny run in shiny mode", {
  runtime <- list(bridge_config = function() {
    list(viewTool = "live_view", entryTool = "live")
  })
  app <- mcp_app(htmltools::div(), name = "live", runtime = runtime)
  config <- helper_page_config(app$html_resource())

  expect_equal(config$mode, "shiny")
  expect_equal(config$runtime, list(viewTool = "live_view", entryTool = "live"))
})

test_that("hosts can merge their own settings into the configuration", {
  app <- mcp_app(htmltools::div(), name = "merged", trigger = "change")
  config <- helper_page_config(app$html_resource(
    config = list(trigger = "manual", hostStyles = NULL, extra = list(a = 1))
  ))

  expect_equal(config$trigger, "manual")
  expect_equal(config$extra, list(a = 1))
  # NULL removes a setting.
  expect_false("hostStyles" %in% names(config))
  expect_equal(config$app, "merged")
})

test_that("the configuration can't close its own script element", {
  app <- mcp_app(
    mcp_text("</script><script>alert(2)</script>"),
    name = "escaped"
  )
  html <- app$html_resource()
  json <- helper_script_text(
    html,
    '<script id="shinymcp-config" type="application/json">'
  )

  expect_false(grepl("</script>", json, fixed = TRUE))
  config <- jsonlite::parse_json(json)
  expect_equal(names(config$outputs), "</script><script>alert(2)</script>")
})

test_that("json_for_script() escapes closing tags and stays valid JSON", {
  json <- json_for_script(list(a = "</script>", b = "</div>"))
  expect_false(grepl("</", json, fixed = TRUE))
  expect_equal(jsonlite::parse_json(json), list(a = "</script>", b = "</div>"))
})

test_that("json_for_script() output with HTML comments stays valid JSON", {
  json <- json_for_script(list(a = "<!-- note -->"))
  expect_false(grepl("<!--", json, fixed = TRUE))
  expect_equal(jsonlite::parse_json(json), list(a = "<!-- note -->"))
})

# ---- Dependencies ----

test_that("pages built from Shiny and bslib are self-contained", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  app <- mcp_app(
    bslib::page_sidebar(
      sidebar = bslib::sidebar(shiny::selectInput(
        "species",
        "Species",
        c("a", "b")
      )),
      mcp_plot("chart")
    ),
    name = "bslib-page"
  )
  html <- app$html_resource()

  expect_false(grepl("<link[^>]+href=", html))
  expect_false(grepl("<script[^>]+src=", html))
  expect_match(html, 'data-shinymcp-dep="bootstrap ', fixed = TRUE)
  expect_match(html, 'data-shinymcp-dep="jquery ', fixed = TRUE)
})

test_that("full pages keep their own body", {
  skip_if_not_installed("bslib")
  html <- mcp_app(
    bslib::page_fillable(mcp_text("x")),
    name = "page"
  )$html_resource()

  expect_equal(helper_count(html, "<body"), 1)
  expect_equal(helper_count(html, "</body>"), 1)
  expect_match(
    html,
    '<body data-shinymcp-body="" class="bslib-page-fill',
    fixed = TRUE
  )
  expect_false(grepl('<main class="shinymcp-app">', html, fixed = TRUE))
  expect_true(
    regexpr('<script id="shinymcp-bridge">', html, fixed = TRUE) <
      regexpr("</body>", html, fixed = TRUE)
  )
})

test_that("the html element names the Bootstrap version", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  html_tag <- function(ui) {
    html <- mcp_app(ui)$html_resource()
    regmatches(html, regexpr("<html[^>]*>", html))
  }

  expect_equal(html_tag(htmltools::div()), '<html lang="en" class="shinymcp">')
  expect_equal(
    html_tag(shiny::fluidPage(mcp_text("x"))),
    '<html lang="en" class="shinymcp shinymcp-bootstrap shinymcp-bs3">'
  )
  expect_equal(
    html_tag(bslib::page_fillable(mcp_text("x"))),
    '<html lang="en" class="shinymcp shinymcp-bootstrap shinymcp-bs5">'
  )
  expect_equal(
    html_tag(bslib::page_fluid(
      theme = bslib::bs_theme(version = 4),
      mcp_text("x")
    )),
    '<html lang="en" class="shinymcp shinymcp-bootstrap shinymcp-bs4">'
  )
})

test_that("widget libraries the bridge replaces are left out", {
  skip_if_not_installed("shiny")
  app <- mcp_app(
    shiny::fluidPage(
      shiny::selectizeInput("a", "A", c("x", "y")),
      shiny::dateInput("d", "D"),
      shiny::sliderInput("s", "S", 0, 10, 5),
      shiny::icon("house"),
      mcp_text("x")
    ),
    name = "replaced"
  )
  html <- app$html_resource()
  config <- helper_page_config(html)
  inlined <- regmatches(html, gregexpr('data-shinymcp-dep="[^"]*"', html))[[1]]
  inlined <- unique(sub(' .*$', "", sub('^data-shinymcp-dep="', "", inlined)))

  expect_setequal(inlined, c("jquery", "bootstrap"))
  expect_false(any(inlined %in% SHINYMCP_REPLACED_DEPS))
  deps <- unlist(config$deps)
  expect_setequal(sub("@.*$", "", deps), c("jquery", "bootstrap"))
})

test_that("dependencies are inlined, with their closing tags escaped", {
  dir <- local_dependency_dir()
  dep <- htmltools::htmlDependency(
    "localdep",
    "0.1.0",
    src = c(file = dir),
    script = list("a.js", list(src = "m.js", type = "module")),
    stylesheet = "a.css",
    head = "<meta name='localdep'>"
  )
  app <- mcp_app(
    htmltools::attachDependencies(htmltools::div("ui"), dep),
    name = "inlined"
  )
  html <- app$html_resource()

  expect_match(html, '<style data-shinymcp-dep="localdep 0.1.0">', fixed = TRUE)
  expect_match(
    html,
    '<script data-shinymcp-dep="localdep 0.1.0">',
    fixed = TRUE
  )
  expect_match(
    html,
    '<script type="module" data-shinymcp-dep="localdep 0.1.0">',
    fixed = TRUE
  )
  expect_match(html, "export const y = 1;", fixed = TRUE)
  expect_match(html, "<meta name='localdep'>", fixed = TRUE)
  # Inlined code can't end its own element early.
  expect_match(
    html,
    "var x = '<\\/script><script>alert(1)<\\/script>';",
    fixed = TRUE
  )
  expect_match(html, "/* <\\/style> */", fixed = TRUE)
  expect_false(grepl("alert(1)</script>", html, fixed = TRUE))
  expect_equal(unlist(helper_page_config(html)$deps), "localdep@0.1.0")
})

test_that("dependencies served from a URL are linked", {
  dep <- htmltools::htmlDependency(
    "remotedep",
    "2.0.0",
    src = c(href = "https://cdn.example.com/r"),
    script = "r.js",
    stylesheet = "r.css"
  )
  html <- mcp_app(
    htmltools::attachDependencies(htmltools::div(), dep),
    name = "remote"
  )$html_resource()

  expect_match(
    html,
    '<link rel="stylesheet" href="https://cdn.example.com/r/r.css">',
    fixed = TRUE
  )
  expect_match(
    html,
    '<script src="https://cdn.example.com/r/r.js"></script>',
    fixed = TRUE
  )
})

test_that("head content from the UI goes in the head", {
  ui <- htmltools::tagList(
    htmltools::tags$head(htmltools::tags$style(
      id = "user-head",
      ".x { color: red; }"
    )),
    htmltools::div("body")
  )
  html <- mcp_app(ui, name = "head")$html_resource()

  head_end <- regexpr("</head>", html, fixed = TRUE)
  user_head <- regexpr('<style id="user-head">', html, fixed = TRUE)
  expect_true(user_head > 0)
  expect_true(user_head < head_end)
})

test_that("raw HTML UIs are embedded as they are", {
  html <- mcp_app(
    htmltools::HTML("<p>raw <em>html</em></p>"),
    name = "raw"
  )$html_resource()
  expect_match(
    html,
    "<main class=\"shinymcp-app\">\n<p>raw <em>html</em></p>\n</main>",
    fixed = TRUE
  )
})

# ---- Hand-built pages ----

test_that("bridge tags can be added to hand-built pages", {
  script <- bridge_script_tag()
  expect_s3_class(script, "shiny.tag")
  expect_equal(script$name, "script")
  expect_equal(htmltools::tagGetAttribute(script, "id"), "shinymcp-bridge")
  expect_match(as.character(script), "shinymcp", fixed = TRUE)

  config <- bridge_config_tag(list(
    app = "hand-built",
    tools = list(list(name = "go", args = I("x")))
  ))
  expect_equal(htmltools::tagGetAttribute(config, "id"), "shinymcp-config")
  expect_equal(htmltools::tagGetAttribute(config, "type"), "application/json")
  parsed <- helper_page_config(as.character(config))
  expect_equal(
    parsed,
    list(app = "hand-built", tools = list(list(name = "go", args = list("x"))))
  )
})

test_that("inlined stylesheets drop @imports of relative URLs", {
  css <- c(
    "@import url(\"font.css\");:root{a:1}",
    "@import 'x.css' screen;b{}",
    "@import url(https://fonts.example.com/a.css);c{}",
    "@import url(data:text/css,x);d{}"
  )
  expect_identical(
    drop_relative_imports(css),
    c(
      ":root{a:1}",
      "b{}",
      "@import url(https://fonts.example.com/a.css);c{}",
      "@import url(data:text/css,x);d{}"
    )
  )
})

test_that("files the UI refers to locally are written into the page", {
  www <- withr::local_tempdir()
  writeLines("window.fromWww = 1;", file.path(www, "app.js"))
  writeLines(".from-www { color: red; }", file.path(www, "app.css"))
  png <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1:20))
  writeBin(png, file.path(www, "logo.png"))
  ui <- htmltools::tagList(
    htmltools::tags$head(
      htmltools::tags$script(src = "app.js"),
      htmltools::tags$link(rel = "stylesheet", href = "app.css"),
      htmltools::tags$script(src = "https://cdn.example.com/x.js")
    ),
    htmltools::tags$img(src = "logo.png", alt = "Logo"),
    htmltools::tags$img(src = "missing.png")
  )
  html <- mcp_app(ui, www = www)$html_resource()
  expect_match(html, "window.fromWww = 1;", fixed = TRUE)
  expect_match(html, ".from-www { color: red; }", fixed = TRUE)
  expect_match(html, "<img src=\"data:image/png;base64,", fixed = TRUE)
  expect_match(html, "alt=\"Logo\"", fixed = TRUE)
  expect_no_match(html, "src=\"app.js\"", fixed = TRUE)
  # Remote and missing files are left as they are.
  expect_match(html, "src=\"https://cdn.example.com/x.js\"", fixed = TRUE)
  expect_match(html, "src=\"missing.png\"", fixed = TRUE)

  expect_error(
    mcp_app(ui, www = "no/such/dir"),
    class = "shinymcp_error_validation"
  )
})

test_that("paths added with addResourcePath() are found without www", {
  skip_if_not_installed("shiny")
  dir <- withr::local_tempdir()
  writeLines("window.fromResource = 1;", file.path(dir, "lib.js"))
  shiny::addResourcePath("shinymcp-test-res", dir)
  withr::defer(shiny::removeResourcePath("shinymcp-test-res"))
  ui <- htmltools::tags$script(src = "shinymcp-test-res/lib.js")
  expect_match(
    mcp_app(ui)$html_resource(),
    "window.fromResource = 1;",
    fixed = TRUE
  )
  # Paths can't climb out of the directory.
  expect_null(resolve_local_asset("shinymcp-test-res/../secret", asset_roots()))
})

test_that("stylesheets keep images and lose fonts they can't load", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "img"))
  writeBin(
    as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)),
    file.path(dir, "img", "a.png")
  )
  css <- paste(
    "@font-face{font-family:x;src:url(../fonts/x.woff2)}",
    "@font-face{font-family:y;src:url(https://fonts.example.com/y.woff2)}",
    ".a{background:url(img/a.png)}",
    ".b{background:url(\"https://example.com/b.png\")}"
  )
  out <- inline_css(css, dir)
  expect_no_match(out, "x.woff2", fixed = TRUE)
  expect_match(out, "https://fonts.example.com/y.woff2", fixed = TRUE)
  expect_match(out, "url(\"data:image/png;base64,", fixed = TRUE)
  expect_match(out, "https://example.com/b.png", fixed = TRUE)
})

test_that("pages load the stand-in for Shiny's browser API first", {
  html <- mcp_app(htmltools::div("x"))$html_resource()
  shim <- regexpr("<script id=\"shinymcp-shiny\"", html, fixed = TRUE)
  style <- regexpr("<style id=\"shinymcp-style\"", html, fixed = TRUE)
  expect_gt(shim, 0)
  expect_lt(shim, style)
  expect_match(html, "window.Shiny = Shiny;", fixed = TRUE)
})
