# Helpers for the app, tool, result, page, host, and shinychat tests.
#
# Names start with `helper_` so they don't collide with helpers in other
# files.

# A small app: a text input, a text output, and a tool that fills it.
helper_greeter_app <- function(name = "greeter", ...) {
  mcp_app(
    ui = htmltools::tagList(
      mcp_text_input("name", "Name", value = "world"),
      mcp_text("message")
    ),
    tools = list(
      list(
        name = "greet",
        description = "Greet someone by name.",
        inputSchema = list(
          type = "object",
          properties = list(
            name = list(type = "string", description = "Who to greet")
          )
        ),
        fun = function(name = "world") {
          list(message = paste0("Hello, ", name, "!"))
        }
      )
    ),
    name = name,
    ...
  )
}

# The text inside the first <script> element whose opening tag matches
# `opening` (a regular expression).
helper_script_text <- function(html, opening) {
  html <- paste(as.character(html), collapse = "\n")
  pattern <- paste0("(?s)", opening, ".*?</script>")
  found <- regmatches(html, regexpr(pattern, html, perl = TRUE))
  if (length(found) == 0) {
    return(NULL)
  }
  sub("</script>$", "", sub(paste0("(?s)^", opening), "", found, perl = TRUE))
}

# The bridge configuration of an app page, parsed as the bridge parses it.
helper_page_config <- function(html) {
  json <- helper_script_text(
    html,
    '<script id="shinymcp-config" type="application/json">'
  )
  jsonlite::parse_json(json)
}

# The configuration a host shell carries in its markup, parsed as the host
# script parses it.
helper_markup_config <- function(markup) {
  json <- helper_script_text(
    markup,
    '<script type="application/json" class="shinymcp-host-config">'
  )
  if (is.null(json)) {
    return(NULL)
  }
  jsonlite::parse_json(json)
}

# How many times `fixed` occurs in `x`.
helper_count <- function(x, fixed) {
  x <- paste(as.character(x), collapse = "\n")
  lengths(regmatches(x, gregexpr(fixed, x, fixed = TRUE)))
}

# A shiny::MockShinySession that records the custom messages sent to it.
# `messages(type)` returns the recorded messages (their payloads), optionally
# only those of one type.
helper_capture_session <- function() {
  session <- shiny::MockShinySession$new()
  log <- new.env(parent = emptyenv())
  log$sent <- list()
  session$sendCustomMessage <- function(type, message) {
    log$sent[[length(log$sent) + 1]] <- list(type = type, message = message)
    invisible()
  }
  list(
    session = session,
    messages = function(type = NULL) {
      sent <- log$sent
      if (!is.null(type)) {
        sent <- Filter(function(m) identical(m$type, type), sent)
      }
      lapply(sent, `[[`, "message")
    }
  )
}

# The smallest session handle_host_event() needs: a way to send messages,
# and the signed-in user.
helper_fake_session <- function(user = NULL, groups = NULL) {
  session <- new.env(parent = emptyenv())
  session$sent <- list()
  session$sendCustomMessage <- function(type, message) {
    session$sent[[length(session$sent) + 1]] <- list(
      type = type,
      message = message
    )
    invisible()
  }
  session$user <- user
  session$groups <- groups
  session
}

# A registry like the one ensure_shiny_host_registry() keeps per session.
helper_host_registry <- function(...) {
  registry <- new.env(parent = emptyenv())
  registry$instances <- new.env(parent = emptyenv())
  states <- list(...)
  for (id in names(states)) {
    registry$instances[[id]] <- states[[id]]
  }
  registry
}

# A JSON-RPC request from a hosted page, as the host script sends it.
helper_host_request <- function(
  instance_id,
  method,
  params = NULL,
  id = 1,
  request_id = "r1"
) {
  message <- list(jsonrpc = "2.0", id = id, method = method)
  if (!is.null(params)) {
    message$params <- params
  }
  list(
    instanceId = instance_id,
    requestId = request_id,
    type = "request",
    message = message
  )
}

# A PNG file, drawn with base graphics.
helper_png_file <- function(width = 20, height = 20) {
  path <- tempfile(fileext = ".png")
  grDevices::png(path, width = width, height = height)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  grDevices::dev.off()
  path
}
