# Files a page refers to by relative path
#
# A host shows the page from a `srcdoc` or a sandboxed frame: it has no base
# URL, and under the MCP Apps Content Security Policy it can load images
# only as `data:` URIs and fonts not at all. So what a Shiny app would serve
# (its www/ folder, paths added with shiny::addResourcePath(), files next to
# a dependency's stylesheet) goes into the page itself.

#' Prepare a stylesheet for inlining
#'
#' Relative `@import`s are dropped (bslib's font.css is the usual one), as
#' are `@font-face` rules that load relative files; images the stylesheet
#' refers to become `data:` URIs.
#' @param base Directory relative URLs resolve against.
#' @noRd
inline_css <- function(css, base = NULL) {
  css <- drop_relative_imports(css)
  css <- gsub(
    "(?is)@font-face\\s*\\{(?:[^{}]*?url\\(\\s*[\"']?(?![a-z][a-z0-9+.-]*:|//)[^)]*\\))[^{}]*\\}",
    "",
    css,
    perl = TRUE
  )
  if (is.null(base)) {
    return(css)
  }
  replace_matches(
    css,
    "url\\(\\s*([\"']?)(?![a-z][a-z0-9+.-]*:|//|#)([^\"')]+)\\1\\s*\\)",
    function(match) {
      ref <- sub(
        "^url\\(\\s*[\"']?([^\"')]+)[\"']?\\s*\\)$",
        "\\1",
        match,
        perl = TRUE
      )
      path <- local_file(ref, base)
      uri <- if (!is.null(path)) data_uri(path, max_bytes = 256 * 1024)
      if (is.null(uri)) match else paste0("url(\"", uri, "\")")
    }
  )
}

#' Remove `@import`s of relative URLs from a stylesheet
#' @noRd
drop_relative_imports <- function(css) {
  gsub(
    "@import\\s+(?:url\\(\\s*[\"']?|[\"'])(?![a-z][a-z0-9+.-]*:|//)[^\"')\\s;]+[\"']?\\s*\\)?[^;]*;",
    "",
    css,
    perl = TRUE,
    ignore.case = TRUE
  )
}

#' Where relative paths in a page can be found
#'
#' Shiny's resource paths (added by packages and apps with
#' shiny::addResourcePath()), and the app's www folder.
#' @return A named list: resource prefixes, plus `.www` for the folder.
#' @noRd
asset_roots <- function(www = NULL) {
  roots <- list()
  if (requireNamespace("shiny", quietly = TRUE)) {
    roots <- as.list(shiny::resourcePaths())
  }
  if (is_string(www) && dir.exists(www)) {
    roots$.www <- www
  }
  roots
}

#' The file behind a relative URL, if there is one
#' @noRd
resolve_local_asset <- function(ref, roots) {
  if (!is_string(ref) || is_remote_url(ref)) {
    return(NULL)
  }
  ref <- clean_relative_url(ref)
  if (is.null(ref)) {
    return(NULL)
  }
  prefix <- sub("/.*$", "", ref)
  rest <- sub("^[^/]*/?", "", ref)
  candidates <- character()
  if (prefix %in% setdiff(names(roots), ".www") && nzchar(rest)) {
    candidates <- c(candidates, local_file(rest, roots[[prefix]]))
  }
  if (!is.null(roots$.www)) {
    candidates <- c(candidates, local_file(ref, roots$.www))
  }
  # Never Shiny's own client: the page runs without it.
  candidates <- candidates[
    !basename(candidates) %in% c("shiny.js", "shiny.min.js")
  ]
  if (length(candidates)) candidates[[1]] else NULL
}

#' @noRd
is_remote_url <- function(ref) {
  grepl("^([a-z][a-z0-9+.-]*:|//|#)", ref, ignore.case = TRUE)
}

#' A relative URL as a path: no query, no fragment, no leading slash or
#' parent directories
#' @noRd
clean_relative_url <- function(ref) {
  ref <- sub("[?#].*$", "", ref)
  ref <- tryCatch(utils::URLdecode(ref), error = function(e) ref)
  ref <- sub("^(\\./|/)+", "", ref)
  if (!nzchar(ref) || grepl("(^|/)\\.\\.(/|$)", ref)) {
    return(NULL)
  }
  ref
}

#' A file under a directory, or NULL
#' @noRd
local_file <- function(ref, dir) {
  if (is.null(dir) || !dir.exists(dir)) {
    return(NULL)
  }
  if (is_remote_url(ref)) {
    return(NULL)
  }
  ref <- sub("[?#].*$", "", ref)
  ref <- tryCatch(utils::URLdecode(ref), error = function(e) ref)
  path <- file.path(dir, sub("^(\\./|/)+", "", ref))
  if (!file.exists(path) || dir.exists(path)) {
    return(NULL)
  }
  path
}

#' A file as a `data:` URI, or NULL when it's too big to embed
#' @noRd
data_uri <- function(path, max_bytes = 5 * 1024 * 1024) {
  size <- file.info(path)$size
  if (is.na(size) || size > max_bytes) {
    return(NULL)
  }
  mime <- mime_type_for(path, default = "")
  if (!nzchar(mime)) {
    return(NULL)
  }
  paste0("data:", mime, ";base64,", base64_file(path))
}

#' Inline the scripts, stylesheets and images a page refers to locally
#'
#' `<script src>`, `<link rel="stylesheet">` and `<img src>` whose paths
#' resolve under `roots` are replaced with their contents; others are left
#' alone.
#' @noRd
inline_local_assets <- function(html, roots) {
  if (length(roots) == 0 || !is_string(html)) {
    return(html)
  }
  html <- replace_matches(
    html,
    "(?is)<script\\b([^>]*)>\\s*</script>",
    function(match) {
      attrs <- parse_html_attributes(sub(
        "(?is)^<script\\b([^>]*)>.*$",
        "\\1",
        match,
        perl = TRUE
      ))
      path <- if ("src" %in% names(attrs)) {
        resolve_local_asset(attrs[["src"]], roots)
      }
      if (is.null(path)) {
        return(match)
      }
      keep <- attrs[
        !names(attrs) %in%
          c("src", "async", "defer", "integrity", "crossorigin")
      ]
      paste0(
        "<script",
        html_attributes_text(keep),
        ">\n",
        escape_inline_close(read_text_file(path), "script"),
        "\n</script>"
      )
    }
  )
  html <- replace_matches(
    html,
    "(?is)<link\\b[^>]*>",
    function(match) {
      attrs <- parse_html_attributes(sub(
        "(?is)^<link\\b|/?>$",
        "",
        match,
        perl = TRUE
      ))
      rel <- tolower(if ("rel" %in% names(attrs)) attrs[["rel"]] else "")
      if (
        !grepl("stylesheet", rel, fixed = TRUE) || !"href" %in% names(attrs)
      ) {
        return(match)
      }
      path <- resolve_local_asset(attrs[["href"]], roots)
      if (is.null(path)) {
        return(match)
      }
      paste0(
        "<style>\n",
        escape_inline_close(
          inline_css(read_text_file(path), dirname(path)),
          "style"
        ),
        "\n</style>"
      )
    }
  )
  replace_matches(
    html,
    "(?is)<img\\b[^>]*>",
    function(match) {
      attrs <- parse_html_attributes(sub(
        "(?is)^<img\\b|/?>$",
        "",
        match,
        perl = TRUE
      ))
      path <- if ("src" %in% names(attrs)) {
        resolve_local_asset(attrs[["src"]], roots)
      }
      uri <- if (!is.null(path)) data_uri(path)
      if (is.null(uri)) {
        return(match)
      }
      attrs[["src"]] <- uri
      paste0("<img", html_attributes_text(attrs), ">")
    }
  )
}

#' Attributes back into start-tag text
#' @noRd
html_attributes_text <- function(attrs) {
  if (length(attrs) == 0) {
    return("")
  }
  parts <- ifelse(
    nzchar(attrs),
    paste0(
      names(attrs),
      "=\"",
      htmltools::htmlEscape(attrs, attribute = TRUE),
      "\""
    ),
    names(attrs)
  )
  paste0(" ", paste(parts, collapse = " "))
}

#' Replace each match of a regular expression with a function of it
#' @noRd
replace_matches <- function(text, pattern, fn) {
  matches <- gregexpr(pattern, text, perl = TRUE)
  found <- regmatches(text, matches)[[1]]
  if (length(found) == 0) {
    return(text)
  }
  regmatches(text, matches) <- list(vapply(
    found,
    fn,
    character(1),
    USE.NAMES = FALSE
  ))
  text
}
