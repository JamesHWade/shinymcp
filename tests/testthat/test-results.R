# Tool results: text for the model, structured content, and the view payload
# the page renders (R/results.R).

view_of <- function(result) {
  result[["_meta"]][["shinymcp/view"]]
}

content_types <- function(result) {
  vapply(result$content, `[[`, character(1), "type")
}

draw_points <- function() {
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot(1:3)
}

# ---- Typed constructors ----

test_that("typed constructors record their kind, value, and options", {
  text <- mcp_result_text(c("a", "b"))
  expect_s3_class(text, "shinymcp_result")
  expect_equal(text$kind, "text")
  expect_equal(text$value, "a\nb")
  expect_equal(text$text, "a\nb")

  expect_equal(mcp_result_html("<b>x</b>")$kind, "html")
  expect_equal(mcp_result_table(mtcars)$kind, "table")
  expect_equal(mcp_result_image("abc")$kind, "image")
  expect_equal(mcp_result_widget(htmltools::div())$kind, "widget")

  plot <- mcp_result_plot(
    draw_points,
    width = 300,
    height = 200,
    res = 72,
    scale = 2
  )
  expect_equal(plot$kind, "plot")
  expect_equal(
    plot$options,
    list(width = 300, height = 200, res = 72, scale = 2)
  )

  pdf <- mcp_result_pdf("report.pdf", filename = "Report.pdf")
  expect_equal(pdf$kind, "pdf")
  expect_equal(pdf$options$filename, "Report.pdf")
})

# The pixel size of a base64 PNG.
png_dims <- function(b64) {
  bytes <- jsonlite::base64_dec(b64)
  c(
    readBin(bytes[17:20], "integer", size = 4, endian = "big"),
    readBin(bytes[21:24], "integer", size = 4, endian = "big")
  )
}

test_that("the plot scale is the screen's density, else an option", {
  skip_if_not_installed("withr")
  withr::local_options(shinymcp.plot_scale = 3)
  plot <- mcp_result_plot(draw_points, width = 100, height = 50)
  expect_null(plot$options$scale)
  expect_equal(png_dims(resolve_plot_output(plot)$image$data), c(300, 150))
  expect_equal(
    png_dims(resolve_plot_output(plot, pixel_ratio = 2)$image$data),
    c(200, 100)
  )
  explicit <- mcp_result_plot(draw_points, width = 100, height = 50, scale = 1)
  expect_equal(
    png_dims(resolve_plot_output(explicit, pixel_ratio = 2)$image$data),
    c(100, 50)
  )
})

test_that("a plot without a size of its own follows its output's", {
  plot <- mcp_result_plot(draw_points)
  out <- resolve_plot_output(
    plot,
    size = list(width = 320, height = 180),
    pixel_ratio = 1
  )
  expect_equal(
    out$render[c("width", "height", "fit")],
    list(width = 320, height = 180, fit = TRUE)
  )
  expect_equal(png_dims(out$image$data), c(320, 180))

  # Without a size from the page: 800 by 500, and the page asks again.
  default <- resolve_plot_output(plot, pixel_ratio = 1)$render
  expect_equal(
    default[c("width", "height", "fit")],
    list(width = 800, height = 500, fit = TRUE)
  )

  # A plot with a size of its own keeps it.
  fixed <- resolve_plot_output(
    mcp_result_plot(draw_points, width = 300, height = 200),
    size = list(width = 320, height = 180),
    pixel_ratio = 1
  )
  expect_equal(fixed$render$width, 300)
  expect_equal(fixed$render$height, 200)
  expect_null(fixed$render$fit)
})

test_that("an output that gives only a width gets a plot in the plot's own shape", {
  auto <- resolve_plot_output(
    mcp_result_plot(draw_points),
    size = list(width = 400),
    pixel_ratio = 1
  )
  expect_equal(
    auto$render[c("width", "height", "fit")],
    list(width = 400, height = 250, fit = TRUE)
  )
  expect_equal(png_dims(auto$image$data), c(400, 250))

  # A shape of its own: a height, or a width and height, set the ratio.
  tall <- resolve_plot_output(
    mcp_result_plot(draw_points, height = 600),
    size = list(width = 400),
    pixel_ratio = 1
  )$render
  expect_equal(c(tall$width, tall$height), c(400, 600))
  wide <- resolve_plot_output(
    mcp_result_plot(draw_points, width = 900),
    size = list(width = 400),
    pixel_ratio = 1
  )$render
  expect_equal(c(wide$width, wide$height), c(900, 500))
})

test_that("each plot in a result is drawn at its output's size", {
  result <- build_tool_result(
    list(a = mcp_result_plot(draw_points), b = mcp_result_plot(draw_points)),
    sizes = list(a = list(width = 200, height = 100)),
    pixel_ratio = 1
  )
  outputs <- view_of(result)$outputs
  expect_equal(outputs$a$value$width, 200)
  expect_equal(outputs$a$value$height, 100)
  expect_equal(outputs$b$value$width, 800)

  single <- build_tool_result(
    mcp_result_plot(draw_points),
    output_types = list(chart = "plot"),
    sizes = list(chart = list(width = 150, height = 90)),
    pixel_ratio = 1
  )
  expect_equal(view_of(single)$result$value$width, 150)
})

test_that("a page's call carries its outputs' sizes to the tool's plots", {
  app <- mcp_app(
    mcp_plot("chart"),
    tools = list(list(
      name = "draw",
      fun = function() list(chart = mcp_result_plot(draw_points))
    )),
    name = "drawing"
  )
  server <- McpServer$new(app)
  response <- server$handle(serving_rpc(
    "tools/call",
    list(
      name = "draw",
      `_meta` = list(
        `shinymcp/caller` = "app",
        `shinymcp/sizes` = list(
          chart = list(width = 240, height = 160),
          bogus = list(width = -1, height = 5)
        ),
        `shinymcp/pixelRatio` = 2
      )
    )
  ))
  chart <- response$result[["_meta"]][["shinymcp/view"]]$outputs$chart$value
  expect_equal(chart$width, 240)
  expect_equal(chart$height, 160)
  expect_true(chart$fit)
  png <- sub("^data:image/png;base64,", "", chart$src)
  expect_equal(png_dims(png), c(480, 320))
})

test_that("output sizes and pixel ratios from a page are checked", {
  expect_null(output_sizes(NULL))
  expect_null(output_sizes(list()))
  expect_null(output_sizes("x"))
  expect_equal(
    output_sizes(list(
      a = list(width = 10, height = 20),
      b = list(width = "x", height = 1),
      c = list(width = 0, height = 1),
      d = list(width = 20000, height = 1),
      e = list(width = 30),
      f = list(width = 40, height = -1)
    )),
    list(
      a = list(width = 10, height = 20),
      e = list(width = 30),
      f = list(width = 40)
    )
  )
  expect_equal(pixel_ratio(2.5), 2.5)
  expect_equal(pixel_ratio(0.5), 1)
  expect_equal(pixel_ratio(9), 3)
  expect_null(pixel_ratio("2"))
  expect_null(pixel_ratio(NA_real_))
  expect_null(pixel_ratio(c(1, 2)))
})

# ---- Plain values ----

test_that("a string is a single text result", {
  result <- build_tool_result("hello")

  expect_equal(result$content, list(list(type = "text", text = "hello")))
  expect_null(result$structuredContent)
  expect_null(result$isError)
  expect_equal(view_of(result)$result, list(kind = "text", value = "hello"))
  expect_null(view_of(result)$outputs)
})

test_that("numbers and flags are shown as text", {
  expect_equal(build_tool_result(42)$content[[1]]$text, "42")
  expect_equal(build_tool_result(TRUE)$content[[1]]$text, "TRUE")
  expect_equal(
    build_tool_result(c(1.5, 2, 3))$content[[1]]$text,
    "1.5, 2.0, 3.0"
  )
  expect_equal(view_of(build_tool_result(42))$result$kind, "text")
})

test_that("NULL is an empty text result", {
  result <- build_tool_result(NULL)
  expect_equal(result$content[[1]]$text, "")
  expect_equal(view_of(result)$result$value, "")
})

test_that("a data frame is a table with rows for the model", {
  result <- build_tool_result(data.frame(x = 1:2, y = c("a", "b")))
  view <- view_of(result)$result

  expect_equal(view$kind, "table")
  expect_match(
    view$value,
    '<table class="table table-sm shinymcp-table">',
    fixed = TRUE
  )
  expect_match(view$value, "<th>x</th>", fixed = TRUE)
  expect_match(view$value, "<td>b</td>", fixed = TRUE)
  # structuredContent must be an object, so the rows are wrapped.
  expect_equal(
    result$structuredContent,
    list(value = list(list(x = 1L, y = "a"), list(x = 2L, y = "b")))
  )
  expect_match(result$content[[1]]$text, "x y")
  expect_match(result$content[[1]]$text, "2 b")
})

test_that("a matrix is a table", {
  result <- build_tool_result(matrix(1:4, 2))
  expect_equal(view_of(result)$result$kind, "table")
  expect_equal(result$structuredContent$value[[1]], list(V1 = 1L, V2 = 3L))
})

test_that("an unnamed list is described as text", {
  result <- build_tool_result(list(1, "a"))
  expect_equal(view_of(result)$result$kind, "text")
  expect_match(result$content[[1]]$text, "List of 2")
})

test_that("a named list fills outputs by id", {
  result <- build_tool_result(list(summary = "ok", n = 3))
  view <- view_of(result)

  expect_null(view$result)
  expect_equal(names(view$outputs), c("summary", "n"))
  expect_equal(view$outputs$summary, list(kind = "text", value = "ok"))
  expect_equal(view$outputs$n, list(kind = "text", value = "3"))
  expect_equal(result$structuredContent, list(summary = "ok", n = 3))
  expect_equal(result$content[[1]]$text, "summary: ok\n\nn: 3")
})

test_that("multi-line output text starts on its own line", {
  result <- build_tool_result(list(a = "one\ntwo", b = ""))
  # Empty outputs are left out of the text.
  expect_equal(result$content[[1]]$text, "a:\none\ntwo")
  expect_equal(result$structuredContent$b, "")
})

test_that("htmltools tags are HTML outputs whose text is readable", {
  result <- build_tool_result(list(
    note = htmltools::tags$div(
      htmltools::tags$p("First & foremost"),
      htmltools::tags$ul(htmltools::tags$li("one"), htmltools::tags$li("two"))
    )
  ))
  entry <- view_of(result)$outputs$note

  expect_equal(entry$kind, "html")
  expect_match(entry$value, "<li>one</li>", fixed = TRUE)
  expect_match(entry$value, "First &amp; foremost", fixed = TRUE)
  expect_equal(result$structuredContent$note, "First & foremost\none\ntwo")
  expect_equal(result$content[[1]]$text, "note:\nFirst & foremost\none\ntwo")
})

test_that("a single tag gets structured content wrapped in an object", {
  result <- build_tool_result(htmltools::tags$p("Hello"))
  expect_equal(view_of(result)$result$kind, "html")
  expect_equal(result$structuredContent, list(value = "Hello"))
})

test_that("ggplot objects are plots", {
  skip_if_not_installed("ggplot2")
  plot <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  result <- build_tool_result(list(chart = plot))
  entry <- view_of(result)$outputs$chart

  expect_equal(entry$kind, "plot")
  expect_match(entry$value$src, "^data:image/png;base64,")
  expect_equal(content_types(result), c("text", "image"))
})

# ---- Typed outputs ----

test_that("mcp_result_text() can give the model a different value", {
  result <- build_tool_result(list(
    status = mcp_result_text(
      "Ready",
      model_value = list(ready = TRUE),
      text = "All set"
    )
  ))

  expect_equal(result$structuredContent, list(status = list(ready = TRUE)))
  expect_equal(result$content[[1]]$text, "status: All set")
  expect_equal(view_of(result)$outputs$status$value, "Ready")

  single <- build_tool_result(mcp_result_text(
    "Ready",
    model_value = list(ready = TRUE)
  ))
  expect_equal(single$structuredContent, list(ready = TRUE))
})

test_that("mcp_result_html() accepts strings and tags", {
  result <- build_tool_result(list(
    raw = mcp_result_html("<p>a &amp; b</p>"),
    tag = mcp_result_html(htmltools::tags$em("c")),
    given = mcp_result_html(
      "<p>x</p>",
      text = "custom",
      model_value = list(k = 1)
    )
  ))
  outputs <- view_of(result)$outputs

  expect_equal(outputs$raw, list(kind = "html", value = "<p>a &amp; b</p>"))
  expect_equal(outputs$tag$value, "<em>c</em>")
  expect_equal(result$structuredContent$raw, "a & b")
  expect_equal(result$structuredContent$given, list(k = 1))
  expect_match(result$content[[1]]$text, "given: custom", fixed = TRUE)
})

test_that("table cells are formatted for display and records for the model", {
  data <- data.frame(
    amount = c(1234.5, NA),
    group = factor(c("u", "v")),
    day = as.Date(c("2024-01-01", NA))
  )
  result <- build_tool_result(list(rows = mcp_result_table(data)))

  expect_equal(
    result$structuredContent$rows,
    list(
      list(amount = 1234.5, group = "u", day = "2024-01-01"),
      list(amount = NULL, group = "v", day = NULL)
    )
  )
  html <- view_of(result)$outputs$rows$value
  expect_match(html, "<td>1,234.5</td>", fixed = TRUE)
  expect_match(html, "<td></td>", fixed = TRUE)
  expect_match(html, "<td>2024-01-01</td>", fixed = TRUE)
})

test_that("tables are capped for the model and for display", {
  skip_if_not_installed("withr")
  withr::local_options(
    shinymcp.max_model_rows = 2,
    shinymcp.max_display_rows = 3
  )
  result <- build_tool_result(list(rows = data.frame(x = 1:5)))

  expect_length(result$structuredContent$rows, 2)
  expect_match(result$content[[1]]$text, "(3 more rows)", fixed = TRUE)
  html <- view_of(result)$outputs$rows$value
  expect_equal(helper_count(html, "<tr>"), 4) # header + 3 rows
  expect_match(html, "Showing 3 of 5 rows.", fixed = TRUE)
})

test_that("empty tables have no rows for the model", {
  result <- build_tool_result(list(rows = data.frame(x = integer())))
  expect_equal(result$structuredContent$rows, list())
  expect_equal(view_of(result)$outputs$rows$kind, "table")
})

test_that("HTML tables become Markdown tables in the text", {
  html <- paste0(
    "<table><thead><tr><th>Name</th><th>Value</th></tr></thead>",
    "<tbody><tr><td>a|b</td><td>1 &amp; 2</td></tr><tr><td>c</td></tr></tbody></table>"
  )
  result <- build_tool_result(list(t = mcp_result_table(html)))

  expect_equal(view_of(result)$outputs$t, list(kind = "table", value = html))
  expect_equal(
    result$structuredContent$t,
    "| Name | Value |\n| --- | --- |\n| a\\|b | 1 & 2 |\n| c | |"
  )
})

test_that("values that aren't tables fall back to printed text", {
  result <- build_tool_result(list(
    t = mcp_result_table(list(a = 1:2, b = 1:3))
  ))
  entry <- view_of(result)$outputs$t
  expect_equal(entry$kind, "text")
  expect_match(entry$value, "$a", fixed = TRUE)
})

test_that("plots are rendered to PNG with an image for the model", {
  result <- build_tool_result(list(
    chart = mcp_result_plot(
      draw_points,
      text = "Three points",
      width = 300,
      height = 200,
      scale = 1
    )
  ))
  entry <- view_of(result)$outputs$chart

  expect_equal(entry$kind, "plot")
  expect_match(entry$value$src, "^data:image/png;base64,iVBORw0KGgo")
  expect_equal(entry$value$width, 300)
  expect_equal(entry$value$height, 200)
  expect_equal(entry$value$alt, "Three points")
  expect_equal(result$structuredContent$chart, "Three points")
  expect_equal(content_types(result), c("text", "image"))
  expect_equal(result$content[[2]]$mimeType, "image/png")
  expect_equal(
    paste0("data:image/png;base64,", result$content[[2]]$data),
    entry$value$src
  )
})

test_that("plots without a description are described as plots", {
  result <- build_tool_result(mcp_result_plot(
    draw_points,
    width = 300,
    height = 300,
    scale = 1
  ))
  expect_equal(result$content[[1]]$text, "A plot.")
  expect_equal(result$structuredContent, list(value = "A plot."))
  expect_equal(view_of(result)$result$kind, "plot")
})

test_that("plots can be drawn at a higher pixel density", {
  result <- build_tool_result(
    mcp_result_plot(draw_points, width = 100, height = 80, scale = 2),
    images = FALSE
  )
  png <- jsonlite::base64_dec(sub(
    "^data:image/png;base64,",
    "",
    view_of(result)$result$value$src
  ))
  # PNG width and height are big-endian integers at bytes 17-24.
  dims <- readBin(png[17:24], "integer", n = 2, size = 4, endian = "big")
  expect_equal(dims, c(200L, 160L))
})

test_that("image files, data URIs, and raw bytes are images", {
  path <- helper_png_file()
  base64 <- base64_file(path)

  from_file <- build_tool_result(mcp_result_image(path, text = "Tiny"))
  expect_equal(view_of(from_file)$result$kind, "image")
  expect_equal(
    view_of(from_file)$result$value$src,
    paste0("data:image/png;base64,", base64)
  )
  expect_equal(view_of(from_file)$result$value$alt, "Tiny")
  expect_equal(
    from_file$content[[2]],
    list(type = "image", data = base64, mimeType = "image/png")
  )

  uri <- build_tool_result(mcp_result_image(paste0(
    "data:image/png;base64,",
    base64
  )))
  expect_equal(uri$content[[2]]$data, base64)
  expect_equal(uri$content[[1]]$text, "An image.")

  raw <- build_tool_result(mcp_result_image(readBin(
    path,
    "raw",
    n = file.size(path)
  )))
  expect_equal(raw$content[[2]]$data, base64)

  # Base64 without a data: prefix is sniffed.
  jpeg_like <- build_tool_result(mcp_result_image("/9j/4AAQSkZJRg=="))
  expect_equal(jpeg_like$content[[2]]$mimeType, "image/jpeg")

  # So are raw bytes.
  starts <- list(
    "image/jpeg" = as.raw(c(0xff, 0xd8, 0xff, 0xe0)),
    "image/gif" = charToRaw("GIF89a"),
    "image/webp" = c(charToRaw("RIFF"), as.raw(c(0, 0, 0, 0))),
    "image/png" = as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
  )
  for (mime in names(starts)) {
    bytes <- c(starts[[mime]], as.raw(1:32))
    result <- build_tool_result(mcp_result_image(bytes))
    expect_equal(result$content[[2]]$mimeType, mime, info = mime)
    expect_match(
      view_of(result)$result$value$src,
      paste0("^data:", mime, ";base64,"),
      info = mime
    )
  }
})

test_that("images the model can't view get no image block", {
  svg <- tempfile(fileext = ".svg")
  writeLines('<svg xmlns="http://www.w3.org/2000/svg"></svg>', svg)
  result <- build_tool_result(mcp_result_image(svg))

  expect_equal(content_types(result), "text")
  expect_match(
    view_of(result)$result$value$src,
    "^data:image/svg\\+xml;base64,"
  )
})

test_that("images must be paths, raw vectors, or strings", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "bad", fun = function() mcp_result_image(42))),
    name = "bad-image"
  )
  result <- app$run_tool("bad")

  expect_true(result$isError)
  expect_match(result$content[[1]]$text, "Expected a file path")
})

test_that("PDFs are downloads", {
  path <- tempfile(fileext = ".pdf")
  writeBin(charToRaw("%PDF-1.4\n%%EOF\n"), path)
  result <- build_tool_result(list(report = mcp_result_pdf(path)))
  entry <- view_of(result)$outputs$report

  expect_equal(entry$kind, "download")
  expect_equal(entry$value$filename, basename(path))
  expect_equal(entry$value$mimeType, "application/pdf")
  expect_equal(entry$value$data, base64_file(path))
  expect_equal(entry$value$label, paste("Download", basename(path)))
  expect_equal(content_types(result), "text")

  named <- build_tool_result(list(
    report = mcp_result_pdf(charToRaw("%PDF"), filename = "summary.pdf")
  ))
  expect_equal(view_of(named)$outputs$report$value$filename, "summary.pdf")

  unnamed <- build_tool_result(list(report = mcp_result_pdf(charToRaw("%PDF"))))
  expect_equal(view_of(unnamed)$outputs$report$value$filename, "document.pdf")
})

test_that("PDF descriptions read naturally", {
  result <- build_tool_result(list(
    report = mcp_result_pdf(charToRaw("%PDF"), filename = "x.pdf")
  ))
  expect_equal(result$structuredContent$report, "A PDF, x.pdf.")
})

test_that("widgets are HTML with their dependencies", {
  skip_if_not_installed("htmlwidgets")
  widget <- htmlwidgets::createWidget(
    "mywidget",
    list(a = 1),
    package = "htmlwidgets"
  )
  result <- build_tool_result(list(
    w = widget,
    typed = mcp_result_widget(
      widget,
      text = "A chart",
      model_value = list(n = 1)
    )
  ))
  entry <- view_of(result)$outputs$w

  expect_equal(entry$kind, "widget")
  expect_match(entry$value, 'class="mywidget html-widget', fixed = TRUE)
  expect_match(entry$value, '{"x":{"a":1}', fixed = TRUE)
  dep_names <- vapply(entry$deps, `[[`, character(1), "name")
  expect_true("htmlwidgets" %in% dep_names)
  expect_true(all(c("name", "version", "head") %in% names(entry$deps[[1]])))
  expect_equal(result$structuredContent$typed, list(n = 1))
  expect_match(result$content[[1]]$text, "typed: A chart", fixed = TRUE)
})

# ---- Dependencies ----

test_that("HTML outputs carry their dependencies, inlined", {
  dir <- tempfile("dep")
  dir.create(dir)
  writeLines("window.demo = 1;", file.path(dir, "demo.js"))
  dep <- htmltools::htmlDependency(
    "demo",
    "1.2.3",
    src = c(file = dir),
    script = "demo.js"
  )
  tag <- htmltools::attachDependencies(htmltools::div("w"), dep)

  result <- build_tool_result(list(h = mcp_result_html(tag)))
  deps <- view_of(result)$outputs$h$deps

  expect_length(deps, 1)
  expect_equal(deps[[1]]$name, "demo")
  expect_equal(deps[[1]]$version, "1.2.3")
  expect_match(deps[[1]]$head, "window.demo = 1;", fixed = TRUE)
  expect_match(
    deps[[1]]$head,
    '<script data-shinymcp-dep="demo 1.2.3">',
    fixed = TRUE
  )
})

test_that("dependencies the page already has aren't sent again", {
  dep <- htmltools::htmlDependency(
    "demo",
    "1.2.3",
    src = c(href = "https://example.com"),
    script = "demo.js"
  )
  tag <- htmltools::attachDependencies(htmltools::div("w"), dep)

  result <- build_tool_result(
    list(h = mcp_result_html(tag)),
    skip_deps = "demo@1.2.3"
  )
  expect_null(view_of(result)$outputs$h$deps)

  # Any version the page has counts: a second copy of a library would
  # replace the first and drop what was attached to it.
  other_version <- build_tool_result(
    list(h = mcp_result_html(tag)),
    skip_deps = "demo@1.0.0"
  )
  expect_null(view_of(other_version)$outputs$h$deps)

  other_library <- build_tool_result(
    list(h = mcp_result_html(tag)),
    skip_deps = c("jquery@3.7.1", "demo-extra@1.2.3")
  )
  expect_length(view_of(other_library)$outputs$h$deps, 1)
})

test_that("dependency_loaded() matches dependencies by name", {
  dep <- htmltools::htmlDependency(
    "demo",
    "1.2.3",
    src = c(href = "https://example.com")
  )
  expect_true(dependency_loaded(dep, "demo@1.2.3"))
  expect_true(dependency_loaded(dep, c("jquery@3.7.1", "demo@0.1")))
  expect_false(dependency_loaded(dep, character()))
  expect_false(dependency_loaded(dep, "demonstration@1.2.3"))
  expect_equal(dependency_key(dep), "demo@1.2.3")
})

test_that("apps skip the dependencies the page reports", {
  dep <- htmltools::htmlDependency(
    "demo",
    "1.2.3",
    src = c(href = "https://example.com"),
    script = "demo.js"
  )
  app <- mcp_app(
    mcp_html("h"),
    tools = list(list(
      name = "show",
      fun = function() {
        list(h = htmltools::attachDependencies(htmltools::div("w"), dep))
      }
    )),
    name = "deps"
  )

  expect_length(view_of(app$run_tool("show"))$outputs$h$deps, 1)
  expect_null(
    view_of(app$run_tool(
      "show",
      context = list(skip_deps = "demo@1.2.3")
    ))$outputs$h$deps
  )
})

# ---- Images for the model ----

test_that("images go to the model, not to the app's own calls", {
  app <- mcp_app(
    mcp_plot("chart"),
    tools = list(list(
      name = "draw",
      fun = function() {
        list(
          chart = mcp_result_plot(
            draw_points,
            width = 300,
            height = 300,
            scale = 1
          )
        )
      }
    )),
    name = "images"
  )

  expect_equal(content_types(app$run_tool("draw")), c("text", "image"))
  expect_equal(
    content_types(app$run_tool("draw", context = list(caller = "app"))),
    "text"
  )
  # The page still gets the plot either way.
  expect_equal(
    view_of(app$run_tool(
      "draw",
      context = list(caller = "app")
    ))$outputs$chart$kind,
    "plot"
  )
})

test_that("apps can turn off images for the model", {
  app <- mcp_app(
    mcp_plot("chart"),
    tools = list(list(
      name = "draw",
      fun = function() {
        list(
          chart = mcp_result_plot(
            draw_points,
            width = 300,
            height = 300,
            scale = 1
          )
        )
      }
    )),
    name = "no-images",
    images = FALSE
  )
  expect_equal(content_types(app$run_tool("draw")), "text")
})

test_that("base64 images returned for plot and image outputs are images", {
  base64 <- base64_file(helper_png_file())
  app <- mcp_app(
    htmltools::tagList(mcp_plot("chart"), mcp_text("caption")),
    tools = list(list(
      name = "draw",
      fun = function() {
        list(
          chart = base64,
          caption = base64,
          uri = paste0("data:image/png;base64,", base64)
        )
      }
    )),
    name = "base64"
  )
  outputs <- view_of(app$run_tool("draw"))$outputs

  expect_equal(outputs$chart$kind, "image")
  expect_equal(
    outputs$chart$value$src,
    paste0("data:image/png;base64,", base64)
  )
  # The same string for a text output stays text, and outputs the UI
  # doesn't show aren't guessed at.
  expect_equal(outputs$caption$kind, "text")
  expect_equal(outputs$uri$kind, "text")
})

test_that("image data is recognized from its first bytes", {
  expect_equal(sniff_image_mime("iVBORw0KGgoAAA"), "image/png")
  expect_equal(sniff_image_mime("/9j/4AAQ"), "image/jpeg")
  expect_equal(sniff_image_mime("R0lGODlh"), "image/gif")
  expect_equal(sniff_image_mime("UklGRiQA"), "image/webp")
  expect_true(is.na(sniff_image_mime("hello")))

  expect_true(looks_like_image_data("data:image/png;base64,xyz"))
  expect_true(looks_like_image_data(paste0("iVBORw0KGgo", strrep("A", 60))))
  expect_false(looks_like_image_data("iVBORw0KGgo")) # too short to be an image
  expect_false(looks_like_image_data("plain words"))
  expect_false(looks_like_image_data(c("a", "b")))
  expect_false(looks_like_image_data(NA_character_))
})

# ---- mcp_tool_result() ----

test_that("mcp_tool_result() sets the text, data, and error flag", {
  result <- build_tool_result(mcp_tool_result(
    summary = "s",
    text = c("line1", "line2"),
    data = list(id = "P-3"),
    error = TRUE
  ))

  expect_equal(result$content, list(list(type = "text", text = "line1\nline2")))
  expect_equal(result$structuredContent, list(id = "P-3"))
  expect_true(result$isError)
  expect_equal(
    view_of(result)$outputs$summary,
    list(kind = "text", value = "s")
  )
})

test_that("mcp_tool_result() without overrides behaves like a named list", {
  wrapped <- build_tool_result(mcp_tool_result(summary = "ok", n = 3))
  plain <- build_tool_result(list(summary = "ok", n = 3))
  expect_equal(wrapped, plain)
})

test_that("mcp_tool_result() with no outputs is a text result", {
  result <- build_tool_result(mcp_tool_result(
    text = "Nothing to show",
    data = list(count = 0)
  ))

  expect_equal(result$content[[1]]$text, "Nothing to show")
  expect_equal(result$structuredContent, list(count = 0))
  expect_null(result$isError)

  # With neither outputs nor data, the structured content is an empty
  # object, never an array.
  bare <- build_tool_result(mcp_tool_result(text = "Done"))
  expect_match(
    as.character(to_json(bare)),
    '"structuredContent":{}',
    fixed = TRUE
  )
})

test_that("mcp_tool_result() outputs must be named", {
  expect_error(mcp_tool_result("a", "b"), class = "shinymcp_error_validation")
  expect_error(
    mcp_tool_result(a = "a", "b"),
    class = "shinymcp_error_validation"
  )
  expect_s3_class(mcp_tool_result(), "shinymcp_tool_result")
})

test_that("tools can return an error result the model reads", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(
      name = "check",
      fun = function() {
        mcp_tool_result(text = "Batch B-7 is locked.", error = TRUE)
      }
    )),
    name = "errors"
  )
  result <- app$run_tool("check")

  expect_true(result$isError)
  expect_equal(result$content[[1]]$text, "Batch B-7 is locked.")
  expect_equal(view_of(result)$tool, "check")
})

# ---- Text limits ----

test_that("long output text is truncated for the model", {
  skip_if_not_installed("withr")
  withr::local_options(shinymcp.max_text_chars = 10)
  result <- build_tool_result(list(a = strrep("x", 25), b = "short"))

  expect_equal(
    result$content[[1]]$text,
    "a:\nxxxxxxxxxx\n... [15 more characters]\n\nb: short"
  )
  # The page and structured content still get everything.
  expect_equal(result$structuredContent$a, strrep("x", 25))
  expect_equal(view_of(result)$outputs$a$value, strrep("x", 25))
})

test_that("long text from a single value is truncated for the model", {
  skip_if_not_installed("withr")
  withr::local_options(shinymcp.max_text_chars = 10)

  result <- build_tool_result(strrep("y", 25))
  expect_equal(result$content[[1]]$text, "yyyyyyyyyy\n... [15 more characters]")
})

test_that("text written with mcp_tool_result() is sent as written", {
  skip_if_not_installed("withr")
  withr::local_options(shinymcp.max_text_chars = 5)
  result <- build_tool_result(mcp_tool_result(a = "x", text = strrep("z", 20)))
  expect_equal(result$content[[1]]$text, strrep("z", 20))
})

test_that("truncate_text() notes how much was cut", {
  expect_equal(truncate_text("abcdef", 3), "abc\n... [3 more characters]")
  expect_equal(truncate_text("abc", 3), "abc")
  expect_equal(truncate_text("abc", NULL), "abc")
})

# ---- Errors ----

test_that("a tool that throws gives an error result with the message", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(name = "boom", fun = function() stop("kaboom"))),
    name = "throws"
  )
  result <- app$run_tool("boom")

  expect_equal(
    result,
    list(
      content = list(list(type = "text", text = "Error: kaboom")),
      isError = TRUE
    )
  )
})

test_that("rlang and cli errors are reported by their message", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(
      list(name = "rlang", fun = function() rlang::abort("rlang failure")),
      list(name = "cli", fun = function() cli::cli_abort("Bad {.val x} value"))
    ),
    name = "rlang-errors"
  )

  expect_equal(app$run_tool("rlang")$content[[1]]$text, "Error: rlang failure")
  expect_equal(app$run_tool("cli")$content[[1]]$text, 'Error: Bad "x" value')
})

test_that("outputs that can't be built are reported as errors", {
  app <- mcp_app(
    htmltools::div(),
    tools = list(list(
      name = "odd",
      fun = function() {
        list(a = structure(list(kind = "weird"), class = "shinymcp_result"))
      }
    )),
    name = "odd-output"
  )
  result <- app$run_tool("odd")

  expect_true(result$isError)
  expect_match(result$content[[1]]$text, "Unknown output kind")
})

# ---- Helpers ----

test_that("the view payload carries the tool name when an app runs the tool", {
  app <- helper_greeter_app()
  result <- app$run_tool("greet", list(name = "Ada"))

  expect_equal(view_of(result)$tool, "greet")
  expect_equal(
    view_of(result)$outputs$message,
    list(kind = "text", value = "Hello, Ada!")
  )
  expect_equal(result$structuredContent, list(message = "Hello, Ada!"))
  expect_equal(result$content[[1]]$text, "message: Hello, Ada!")
})

test_that("json_safe() makes model values serializable", {
  out <- json_safe(list(
    day = as.Date("2024-01-02"),
    group = factor("a"),
    rows = data.frame(x = 1),
    time = as.POSIXct("2024-01-02 03:04:05", tz = "UTC"),
    nested = list(f = factor("b"))
  ))

  expect_equal(out$day, "2024-01-02")
  expect_equal(out$group, "a")
  expect_equal(out$rows, list(list(x = 1)))
  expect_equal(out$time, "2024-01-02 03:04:05")
  expect_equal(out$nested$f, "b")
  expect_null(json_safe(NULL))
})

test_that("html_to_text() keeps text and structure, not markup", {
  html <- paste0(
    "<div><p>First &amp; <b>bold</b></p><script>var x = 1;</script>",
    "<style>.a{}</style><p>Second<br>line</p><ul><li>one</li><li>two</li></ul></div>"
  )
  expect_equal(html_to_text(html), "First & bold\nSecond\nline\none\ntwo")
  expect_equal(
    html_to_text("plain   text\twith   spaces"),
    "plain text with spaces"
  )
  expect_equal(html_to_text(c("<p>a</p>", "<p>b</p>")), "a\nb")
  expect_equal(html_to_text("<p>x &lt; y and y &gt; z</p>"), "x < y and y > z")
})

test_that("html_to_text() keeps escaped angle brackets in table cells", {
  html <- "<table><tr><th>p</th><th>n</th></tr><tr><td>&lt; 0.001</td><td>&gt; 5</td></tr></table>"
  expect_equal(
    html_to_text(html),
    "| p | n |\n| --- | --- |\n| < 0.001 | > 5 |"
  )
})

test_that("unescape_html() decodes each entity once", {
  expect_equal(
    unescape_html("&amp;lt; &quot;q&quot; &#39;s&#39;"),
    "&lt; \"q\" 's'"
  )
})

test_that("tables_to_markdown() leaves HTML without tables alone", {
  expect_equal(tables_to_markdown("<p>no table</p>"), "<p>no table</p>")
  expect_equal(html_to_text("<table></table>"), "")
})

test_that("base64 data has no line breaks", {
  png <- as.raw(c(
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    rep(0:255, 4)
  ))
  result <- build_tool_result(mcp_result_image(png))
  expect_false(grepl("\n", result$content[[2]]$data, fixed = TRUE))
  expect_identical(jsonlite::base64_dec(result$content[[2]]$data), png)
})

test_that("a result sends each library once", {
  dep <- htmltools::htmlDependency(
    "shared-lib",
    "1.0",
    src = c(file = withr::local_tempdir()),
    head = "<script>window.sharedLib = 1;</script>"
  )
  result <- build_tool_result(list(
    a = mcp_result_html(htmltools::tagList(htmltools::p("a"), dep)),
    b = mcp_result_html(htmltools::tagList(htmltools::p("b"), dep))
  ))
  outputs <- view_of(result)$outputs
  expect_length(outputs$a$deps, 1)
  expect_null(outputs$b$deps)
})
