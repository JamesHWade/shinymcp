# Assembling the app page (the `ui://` resource)
#
# Hosts load the page into a sandboxed iframe with a strict Content Security
# Policy, often from a `srcdoc` with no base URL. So the page is one
# self-contained document: CSS and JavaScript inlined, no links to package
# resources, and the bridge script plus its configuration at the end of
# <body>.

# Widget libraries the bridge replaces with native controls. Inlining them
# only adds weight: without Shiny's client they never initialize.
SHINYMCP_REPLACED_DEPS <- c(
  "selectize",
  "bootstrap-datepicker-js",
  "bootstrap-datepicker-css",
  "ionrangeslider-javascript",
  "ionrangeslider-css",
  "strftime",
  # Icon fonts can't load under the default CSP (no font-src), so the
  # stylesheet would only add weight. Use inline SVG icons instead.
  "font-awesome"
)

#' @noRd
build_app_html <- function(app, private, config = NULL) {
  rendered <- private$rendered()
  deps <- htmltools::resolveDependencies(rendered$dependencies)
  deps <- Filter(function(d) !d$name %in% SHINYMCP_REPLACED_DEPS, deps)
  bootstrap <- Filter(function(d) identical(d$name, "bootstrap"), deps)
  bootstrap_major <- if (length(bootstrap)) {
    sub("\\..*$", "", as.character(bootstrap[[1]]$version))
  }

  bridge_config <- app_bridge_config(app, private, deps)
  if (!is.null(config)) {
    bridge_config <- utils::modifyList(bridge_config, config, keep.null = FALSE)
  }

  head <- c(
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<meta name="color-scheme" content="light dark">',
    paste0(
      "<title>",
      htmltools::htmlEscape(app$title %||% app$name),
      "</title>"
    ),
    paste0('<style id="shinymcp-style">\n', bridge_css(), "\n</style>"),
    vapply(deps, inline_dependency, character(1)),
    if (nzchar(rendered$head %||% "")) as.character(rendered$head)
  )

  scripts <- paste0(
    '<script id="shinymcp-config" type="application/json">',
    json_for_script(bridge_config),
    "</script>\n<script id=\"shinymcp-bridge\">\n",
    bridge_js(),
    "\n</script>"
  )

  html <- as.character(rendered$html)
  # Bootstrap 3 and 4 have no dark mode; the bridge keeps those pages light.
  classes <- paste(
    c(
      "shinymcp",
      if (!is.null(bootstrap_major)) {
        c("shinymcp-bootstrap", paste0("shinymcp-bs", bootstrap_major))
      }
    ),
    collapse = " "
  )
  if (grepl("^\\s*<body", html)) {
    # Full pages (bslib::page_*(), fluidPage()) render their own <body>.
    html <- sub("<body", paste0("<body data-shinymcp-body=\"\""), html)
    close <- regexpr("</body>\\s*$", html)
    body <- if (close > 0) {
      paste0(substr(html, 1, close - 1), scripts, "\n</body>")
    } else {
      paste0(html, "\n", scripts)
    }
  } else {
    body <- paste0(
      "<body data-shinymcp-body=\"\">\n<main class=\"shinymcp-app\">\n",
      html,
      "\n</main>\n",
      scripts,
      "\n</body>"
    )
  }

  paste0(
    "<!DOCTYPE html>\n<html lang=\"en\" class=\"",
    classes,
    "\">\n<head>\n",
    paste(head, collapse = "\n"),
    "\n</head>\n",
    body,
    "\n</html>"
  )
}

#' Configuration the bridge reads from `#shinymcp-config`
#' @noRd
app_bridge_config <- function(app, private, deps = list()) {
  tools <- lapply(unname(private$.tools), function(tool) {
    compact_list(list(
      name = tool$name,
      args = I(tool_argument_names(tool)),
      outputs = if (length(tool$outputs)) I(tool$outputs),
      app = tool_visible_to(tool, "app"),
      model = tool_visible_to(tool, "model"),
      readOnly = tool$annotations$readOnlyHint,
      destructive = tool$annotations$destructiveHint
    ))
  })
  runtime <- private$.runtime
  outputs <- private$ui_outputs()
  compact_list(list(
    app = app$name,
    version = app$version,
    appsProtocolVersion = SHINYMCP_APPS_PROTOCOL_VERSION,
    mode = if (is.null(runtime)) "tools" else "shiny",
    tools = I(tools),
    outputs = if (length(outputs)) as.list(outputs) else json_object(),
    trigger = private$.trigger,
    debounceMs = private$.debounce_ms,
    hostStyles = private$.host_styles,
    modelContext = private$.model_context,
    deps = I(vapply(deps, dependency_key, character(1))),
    runtime = if (!is.null(runtime)) runtime$bridge_config()
  ))
}

#' JSON safe to embed in a <script> element
#' @noRd
json_for_script <- function(x) {
  # "\u003c" is "<" to a JSON parser, and no "</script>" or "<!--" is left
  # for the HTML parser to see. ("<" only occurs inside JSON strings.)
  gsub("<", "\\u003c", as.character(to_json(x)), fixed = TRUE)
}

#' @noRd
bridge_js <- function() {
  if (is.null(the$bridge_js) || isTRUE(getOption("shinymcp.dev_reload"))) {
    the$bridge_js <- read_package_file("js", "shinymcp-bridge.js")
  }
  the$bridge_js
}

#' @noRd
bridge_css <- function() {
  if (is.null(the$bridge_css) || isTRUE(getOption("shinymcp.dev_reload"))) {
    the$bridge_css <- read_package_file("js", "shinymcp-bridge.css")
  }
  the$bridge_css
}

#' The bridge script as an HTML tag
#'
#' `bridge_script_tag()` and `bridge_config_tag()` are for pages built by
#' hand: include both, the config first, at the end of `<body>`.
#' [mcp_app()] adds them for you, so most apps never need these.
#'
#' @param config A named list: the bridge configuration. At minimum `app`
#'   (a name) and `tools`, a list of `list(name =, args =)` records.
#' @return An htmltools `<script>` tag.
#' @family advanced
#' @export
bridge_script_tag <- function() {
  htmltools::tags$script(id = "shinymcp-bridge", htmltools::HTML(bridge_js()))
}

#' @rdname bridge_script_tag
#' @export
bridge_config_tag <- function(config) {
  htmltools::tags$script(
    id = "shinymcp-config",
    type = "application/json",
    htmltools::HTML(json_for_script(config))
  )
}

#' Is a UI a whole page (one that brings Bootstrap)?
#' @noRd
is_page <- function(ui) {
  if (inherits(ui, "bslib_page")) {
    return(TRUE)
  }
  deps <- htmltools::findDependencies(ui)
  any(vapply(deps, function(d) identical(d$name, "bootstrap"), logical(1)))
}
