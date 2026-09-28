# Internal utilities

#' Path to a file installed with the package
#' @noRd
system_file <- function(...) {
  system.file(..., package = "shinymcp", mustWork = TRUE)
}

#' Read a text file installed with the package
#' @noRd
read_package_file <- function(...) {
  paste(
    readLines(system_file(...), warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
}

#' A hard-to-guess identifier
#'
#' Instance ids let a client drive a live session, so they come from the
#' operating system's random source rather than R's RNG (which a user's
#' `set.seed()` would make repeatable). Where there is no `/dev/urandom`
#' the id is a hash of the clock, the process id, and a counter.
#' @noRd
unique_id <- function(prefix = "shinymcp", n = 16) {
  the$id_counter <- (the$id_counter %||% 0) + 1
  bytes <- tryCatch(
    readBin("/dev/urandom", "raw", n = 16),
    error = function(e) NULL,
    warning = function(w) NULL
  )
  id <- if (length(bytes) == 16) {
    paste(as.character(bytes), collapse = "")
  } else {
    rlang::hash(list(
      as.numeric(Sys.time()),
      proc.time()[[3]],
      Sys.getpid(),
      the$id_counter
    ))
  }
  id <- substr(id, 1, n)
  if (nzchar(prefix)) paste0(prefix, "-", id) else id
}

#' Serialize to JSON the way MCP expects
#' @noRd
to_json <- function(x, pretty = FALSE) {
  jsonlite::toJSON(
    x,
    auto_unbox = TRUE,
    pretty = pretty,
    null = "null",
    na = "null",
    digits = NA,
    force = TRUE
  )
}

#' A field of a parsed JSON object, matched exactly
#'
#' `$` matches a prefix (`x$name` finds `nameExtra`), which messages from
#' outside mustn't be able to use. `NULL` for anything but a list.
#' @noRd
json_field <- function(x, name) {
  if (is.list(x)) x[[name]]
}

#' Parse JSON text without simplifying arrays
#'
#' jsonlite::parse_json() only ever reads its argument as JSON.
#' jsonlite::fromJSON() would read a string that names a file, or fetch one
#' that is a URL, which a request body must never be able to do.
#' @noRd
from_json <- function(x) {
  jsonlite::parse_json(x, simplifyVector = FALSE)
}

#' Remove NULL entries from a list
#' @noRd
compact_list <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}

#' Base64-encode a file
#' @noRd
base64_file <- function(path) {
  size <- file.info(path)$size
  if (is.na(size)) {
    shinymcp_abort("Can't read {.file {path}}.")
  }
  base64_raw(readBin(path, "raw", n = size))
}

#' Base64-encode a raw vector
#' @noRd
base64_raw <- function(x) {
  # jsonlite wraps lines; MCP hosts expect plain base64.
  gsub("\n", "", as.character(jsonlite::base64_enc(x)), fixed = TRUE)
}

#' MIME type from a file extension
#' @noRd
mime_type_for <- function(path, default = "application/octet-stream") {
  ext <- tolower(tools::file_ext(path))
  types <- c(
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    webp = "image/webp",
    svg = "image/svg+xml",
    pdf = "application/pdf",
    csv = "text/csv",
    tsv = "text/tab-separated-values",
    txt = "text/plain",
    md = "text/markdown",
    html = "text/html",
    json = "application/json",
    xml = "application/xml",
    zip = "application/zip",
    xlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    xls = "application/vnd.ms-excel",
    docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    pptx = "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    rds = "application/octet-stream",
    parquet = "application/vnd.apache.parquet"
  )
  if (ext %in% names(types)) types[[ext]] else default
}

#' Inline an HTML dependency as `<style>` and `<script>` tags
#'
#' MCP hosts block external scripts and stylesheets unless the app declares
#' their domains, so dependencies are embedded in the page. A dependency that
#' only has an `href` is linked instead (and needs a `csp` declaration).
#' @noRd
inline_dependency <- function(dep) {
  parts <- character()
  base <- dep$src$file
  label <- paste0(dep$name, " ", dep$version)

  if (!is.null(base) && nzchar(base)) {
    for (css in dep$stylesheet) {
      path <- file.path(base, css)
      if (file.exists(path)) {
        parts <- c(
          parts,
          paste0(
            "<style data-shinymcp-dep=\"",
            htmltools::htmlEscape(label, TRUE),
            "\">\n",
            escape_inline_close(
              inline_css(read_text_file(path), dirname(path)),
              "style"
            ),
            "\n</style>"
          )
        )
      }
    }
    for (js in dep$script) {
      file <- if (is.list(js)) js$src else js
      path <- file.path(base, file)
      if (!file.exists(path)) {
        next
      }
      type <- if (is.list(js) && !is.null(js$type)) {
        paste0(" type=\"", js$type, "\"")
      } else {
        ""
      }
      parts <- c(
        parts,
        paste0(
          "<script",
          type,
          " data-shinymcp-dep=\"",
          htmltools::htmlEscape(label, TRUE),
          "\">\n",
          escape_inline_close(read_text_file(path), "script"),
          "\n</script>"
        )
      )
    }
    if (identical(dep$name, "leaflet")) {
      parts <- c(parts, leaflet_icon_patch(base))
    }
  } else if (!is.null(dep$src$href)) {
    href <- dep$src$href
    for (css in dep$stylesheet) {
      parts <- c(
        parts,
        sprintf("<link rel=\"stylesheet\" href=\"%s/%s\">", href, css)
      )
    }
    for (js in dep$script) {
      file <- if (is.list(js)) js$src else js
      parts <- c(parts, sprintf("<script src=\"%s/%s\"></script>", href, file))
    }
  }
  if (length(dep$head)) {
    parts <- c(parts, paste(dep$head, collapse = "\n"))
  }
  paste(parts, collapse = "\n")
}

#' Leaflet's default marker, from the images the library ships
#'
#' The leaflet package points Leaflet's default marker icons at unpkg.com,
#' which hosts block, so markers would be missing. This script, run after
#' Leaflet loads, hands out the library's own images as data URIs instead.
#' @noRd
leaflet_icon_patch <- function(base) {
  images <- file.path(
    base,
    "images",
    c("marker-icon.png", "marker-icon-2x.png", "marker-shadow.png")
  )
  if (!all(file.exists(images))) {
    return(character())
  }
  uris <- vapply(images, function(path) data_uri(path) %||% "", character(1))
  if (!all(nzchar(uris))) {
    return(character())
  }
  paste0(
    "<script data-shinymcp-dep=\"leaflet icons\">\n",
    "(function () {\n",
    "  if (!window.L || !L.Icon || !L.Icon.Default) return;\n",
    "  var icon = \"",
    uris[[1]],
    "\";\n",
    "  var retina = \"",
    uris[[2]],
    "\";\n",
    "  var shadow = \"",
    uris[[3]],
    "\";\n",
    "  L.Icon.Default.prototype._getIconUrl = function (name) {\n",
    "    if (name === \"shadow\") return shadow;\n",
    "    return L.Browser.retina ? retina : icon;\n",
    "  };\n",
    "})();\n",
    "</script>"
  )
}

#' @noRd
read_text_file <- function(path) {
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

#' Keep inlined code from closing its own tag early
#'
#' A literal `</script>` inside inlined JavaScript would end the element.
#' @noRd
escape_inline_close <- function(text, tag) {
  gsub(
    paste0("</(", tag, ")"),
    "<\\\\/\\1",
    text,
    ignore.case = TRUE,
    perl = TRUE
  )
}

#' Is a value a single non-empty string?
#' @noRd
is_string <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)
}

#' Tool and resource names must be safe for MCP clients
#'
#' MCP recommends 1-128 characters from `A-Za-z0-9_.-`; several clients also
#' reject dots, so shinymcp derives names from letters, digits, `_` and `-`.
#' @noRd
sanitize_name <- function(x) {
  x <- gsub("[^A-Za-z0-9_-]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  if (!nzchar(x)) "app" else substr(x, 1, 64)
}
