# State shared by shinymcp's hosts (panes, shinychat cards).

#' State for one hosted app instance
#'
#' An instance is one app page in one card or pane: the source it comes
#' from, the tool call that opened it, and what the page has said since.
#' @param kind `"pane"` or `"card"`. Chat hosts pass the context and
#'   messages of cards on to the model.
#' @noRd
new_mcp_host_state <- function(
  source,
  instance_id = unique_id("host"),
  tool = NULL,
  arguments = NULL,
  result = NULL,
  kind = "pane",
  title = NULL,
  config = NULL
) {
  state <- new.env(parent = emptyenv())
  state$source <- as_host_source(source)
  state$instance_id <- instance_id
  state$kind <- kind
  state$tool <- tool
  state$arguments <- arguments %||% json_object()
  state$result <- result
  state$title <- title %||% state$source$title
  # Without a title of its own, an instance takes its tool's or its page's.
  state$title_given <- !is.null(title)
  state$default_title <- is.null(title)
  # Bridge settings for in-process pages (trigger, debounce).
  state$config <- config
  state$call_seq <- 0L
  state$call_error <- NULL
  state$attached <- FALSE
  state$model_context <- NULL
  state$context_time <- NULL
  state$last_tool_call <- NULL
  state$last_size <- NULL
  state$messages <- list()
  state$views <- NULL
  state$disposed <- FALSE
  state$on_model_context <- NULL
  state$on_tool_call <- NULL
  state$on_message <- NULL
  state$on_size <- NULL
  state
}

#' @noRd
mcp_host_callback <- function(state, name, value) {
  callback <- state[[name]]
  if (is.function(callback)) {
    tryCatch(
      callback(value),
      error = function(e) {
        cli::cli_warn(
          "Host callback {.field {name}} failed: {conditionMessage(e)}"
        )
      }
    )
  }
  invisible(value)
}

#' Record a tool call made in a hosted app
#' @noRd
mcp_host_record_call <- function(state, name, arguments, result) {
  view <- result[["_meta"]][["shinymcp/view"]]$instance
  if (is_string(view)) {
    state$views <- unique(c(state$views, view))
  }
  call <- list(name = name, arguments = arguments %||% list(), result = result)
  state$last_tool_call <- call
  mcp_host_callback(state, "on_tool_call", call)
  invisible(state)
}

#' Handle a notification from a hosted app
#' @noRd
mcp_host_notification <- function(state, method, params) {
  switch(
    method %||% "",
    "ui/update-model-context" = {
      state$model_context <- params
      state$context_time <- as.numeric(Sys.time())
      mcp_host_callback(state, "on_model_context", params)
    },
    "ui/message" = {
      state$messages <- c(state$messages, list(params))
      mcp_host_callback(state, "on_message", params)
    },
    "ui/notifications/size-changed" = {
      state$last_size <- compact_list(list(
        width = params$width,
        height = params$height
      ))
      mcp_host_callback(state, "on_size", state$last_size)
    },
    "ui/resource-teardown" = mcp_host_dispose(state),
    NULL
  )
  invisible(state)
}

#' @noRd
mcp_host_dispose <- function(state) {
  if (!isTRUE(state$disposed)) {
    state$disposed <- TRUE
    # Views of a live Shiny app opened by this instance die with it.
    if (length(state$views)) {
      state$source$close_views(state$views)
    }
  }
  invisible(state)
}

#' The text of a message or model context an app sent
#'
#' Text blocks, then the structured content as JSON, cut to `limit`
#' characters.
#' @noRd
host_content_text <- function(params, limit = Inf) {
  blocks <- Filter(
    function(b) is.list(b) && identical(b$type, "text") && is_string(b$text),
    params$content %||% list()
  )
  parts <- vapply(blocks, function(b) b$text, character(1))
  if (!is.null(params$structuredContent)) {
    parts <- c(parts, as.character(to_json(params$structuredContent)))
  }
  text <- paste(parts, collapse = "\n")
  if (is.finite(limit) && nchar(text) > limit) {
    text <- paste0(substr(text, 1, limit - 3), "...")
  }
  text
}

#' The text of an HTML page's `<title>`, or NULL
#' @noRd
html_page_title <- function(html) {
  if (!is_string(html)) {
    return(NULL)
  }
  found <- regmatches(
    html,
    regexpr("<title[^>]*>[^<]*</title>", html, ignore.case = TRUE, perl = TRUE)
  )
  if (length(found) == 0) {
    return(NULL)
  }
  text <- gsub("<[^>]+>", "", found)
  for (entity in list(
    c("&lt;", "<"),
    c("&gt;", ">"),
    c("&quot;", "\""),
    c("&#39;", "'"),
    c("&amp;", "&")
  )) {
    text <- gsub(entity[[1]], entity[[2]], text, fixed = TRUE)
  }
  text <- trimws(text)
  if (nzchar(text)) text else NULL
}
