# shinychat integration: MCP Apps as live tool cards

#' Use an MCP App as a shinychat tool
#'
#' @description
#' `as_shinychat_tool()` turns an app's tools into [ellmer::tool()] objects
#' for a chat built with shinychat. When the model calls one, the tool runs
#' and shinychat shows the app, live, in the tool's card. The model gets the
#' tool's structured result (or the text, if there is none); the person
#' gets the app.
#'
#' `mcp_content_result()` builds the same kind of card by hand, for a
#' result you append to the chat yourself.
#'
#' @param app An [McpApp], or anything [as_mcp_app()] accepts.
#' @param tool Names of the app's tools to wrap. Defaults to every tool the
#'   model may call.
#' @param value_fn Optional function computing the value returned to the
#'   model. It can take any of `raw_result` (what the tool function
#'   returned), `result` (the MCP result), and `arguments`.
#' @param summary Optional text shown in the card when it can't show the
#'   app, or a function taking the same arguments as `value_fn`.
#' @param title,icon Card title and icon (a string or tag, or a function
#'   taking the same arguments as `value_fn`). Default to the tool's title
#'   annotation.
#' @param open Whether the card starts expanded.
#' @param show_request Whether the card shows the call's arguments.
#' @param full_screen Whether the card offers a full-screen view.
#' @return For one tool, an [ellmer::tool()]; for several, a named list of
#'   them.
#' @family hosting
#' @export
#' @examples
#' \dontrun{
#' chat <- ellmer::chat("anthropic/claude-sonnet-5")
#' chat$register_tool(as_shinychat_tool(app, title = "Penguins"))
#' }
as_shinychat_tool <- function(
  app,
  tool = NULL,
  value_fn = NULL,
  summary = NULL,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE
) {
  rlang::check_installed(
    "ellmer",
    reason = "to wrap MCP Apps as shinychat tools."
  )
  app <- as_mcp_app(app)
  tools <- app$tools("model")
  if (!is.null(tool)) {
    unknown <- setdiff(tool, names(tools))
    if (length(unknown)) {
      shinymcp_abort(
        "App {.val {app$name}} has no tool the model can call named {.val {unknown}}.",
        class = "shinymcp_error_validation"
      )
    }
    tools <- tools[tool]
  }
  if (length(tools) == 0) {
    shinymcp_abort("App {.val {app$name}} has no tools for the model to call.")
  }

  wrapped <- lapply(tools, function(t) {
    wrapper <- shinychat_tool_function(
      app = app,
      tool = t,
      value_fn = value_fn,
      summary = summary,
      title = title %||% t$title,
      icon = icon,
      open = open,
      show_request = show_request,
      full_screen = full_screen
    )
    ellmer::tool(
      wrapper,
      name = t$name,
      description = t$description,
      arguments = schema_to_ellmer_types(t$input_schema),
      annotations = shinychat_annotations(t, title)
    )
  })
  if (length(wrapped) == 1) wrapped[[1]] else wrapped
}

#' @noRd
shinychat_annotations <- function(tool, title) {
  ann <- tool$annotations %||% list()
  args <- compact_list(list(
    title = if (is.character(title)) title else tool$title,
    read_only_hint = ann$readOnlyHint,
    destructive_hint = ann$destructiveHint,
    idempotent_hint = ann$idempotentHint,
    open_world_hint = ann$openWorldHint
  ))
  do.call(ellmer::tool_annotations, args)
}

#' Build the function behind a shinychat tool
#' @noRd
shinychat_tool_function <- function(
  app,
  tool,
  value_fn,
  summary,
  title,
  icon,
  open,
  show_request,
  full_screen
) {
  arg_names <- tool_argument_names(tool)
  fun <- function() {
    env <- environment()
    arguments <- list()
    for (nm in arg_names) {
      if (!eval(call("missing", as.name(nm)), env)) {
        value <- get(nm, envir = env)
        if (!is.null(value)) {
          arguments[[nm]] <- value
        }
      }
    }
    run_shinychat_tool(
      app = app,
      tool = tool,
      arguments = arguments,
      value_fn = value_fn,
      summary = summary,
      title = title,
      icon = icon,
      open = open,
      show_request = show_request,
      full_screen = full_screen
    )
  }
  formals(fun) <- rlang::rep_named(arg_names, list(rlang::missing_arg()))
  fun
}

#' @noRd
run_shinychat_tool <- function(
  app,
  tool,
  arguments,
  value_fn,
  summary,
  title,
  icon,
  open,
  show_request,
  full_screen
) {
  run <- function() {
    raw <- app$call_tool(
      tool$name,
      arguments,
      list(caller = "model", transport = "shinychat")
    )
    result <- if (inherits(raw, "shinymcp_wire_result")) {
      unclass(raw)
    } else {
      build_tool_result(
        raw,
        images = FALSE,
        view = list(tool = tool$name),
        output_types = app$output_types()
      )
    }
    context <- list(raw_result = raw, result = result, arguments = arguments)
    value <- if (is.function(value_fn)) {
      call_with_supported_args(value_fn, context)
    } else {
      default_model_value(result)
    }
    card_title <- if (is.function(title)) {
      call_with_supported_args(title, context)
    } else {
      title
    }
    card_icon <- if (is.function(icon)) {
      call_with_supported_args(icon, context)
    } else {
      icon
    }
    text <- if (is.function(summary)) {
      call_with_supported_args(summary, context)
    } else {
      summary %||% result_text(result)
    }
    live_card_result(
      app = app,
      value = value,
      title = card_title,
      icon = card_icon,
      open = open,
      show_request = show_request,
      full_screen = full_screen,
      text = text,
      tool = tool$name,
      arguments = arguments,
      result = result
    )
  }
  # A Shiny app served live runs its own reactive session, which can't
  # flush while another flush is running; leave the current one first.
  if (!is.null(app$runtime()) && !is.null(shiny::getDefaultReactiveDomain())) {
    rlang::check_installed("promises", reason = "to run live apps from a chat.")
    return(promises::promise(function(resolve, reject) {
      later::later(function() tryCatch(resolve(run()), error = reject))
    }))
  }
  run()
}

#' The value the model sees for a tool result
#'
#' The structured result, except for a single value that was wrapped only
#' because structuredContent has to be an object: that reads better as text.
#' @noRd
default_model_value <- function(result) {
  structured <- result$structuredContent
  lone_value <- identical(names(structured), "value") &&
    is.atomic(structured$value) &&
    length(structured$value) <= 1
  if (is.null(structured) || lone_value) {
    return(result_text(result))
  }
  structured
}

#' @noRd
result_text <- function(result) {
  blocks <- Filter(
    function(b) identical(b$type, "text"),
    result$content %||% list()
  )
  paste(
    vapply(blocks, function(b) b$text %||% "", character(1)),
    collapse = "\n"
  )
}

#' @noRd
call_with_supported_args <- function(fn, args) {
  accepted <- names(formals(fn))
  if (is.null(accepted)) {
    return(fn())
  }
  if ("..." %in% accepted) {
    return(do.call(fn, args))
  }
  do.call(fn, args[intersect(names(args), accepted)])
}

#' A tool result that shows a live app in a shinychat card
#' @noRd
live_card_result <- function(
  app,
  value,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE,
  text = NULL,
  tool = NULL,
  arguments = NULL,
  result = NULL,
  request = NULL
) {
  rlang::check_installed("ellmer", reason = "for shinychat tool results.")
  display <- compact_list(list(
    title = title,
    icon = icon,
    open = open,
    show_request = show_request,
    full_screen = full_screen
  ))
  session <- active_shiny_session()
  if (!is.null(session)) {
    registered <- register_shiny_host_instance(
      session = session,
      app = app,
      tool = tool,
      arguments = arguments,
      result = result
    )
    display$html <- mcp_host_markup(
      sanitize_dom_id(registered$state$instance_id),
      config = registered$config,
      toolbar = FALSE
    )
  } else {
    display$text <- text %||% result_text(result)
  }
  ellmer::ContentToolResult(
    value = value,
    extra = list(display = display),
    request = request
  )
}

#' @rdname as_shinychat_tool
#' @param value For `mcp_content_result()`, the value for the model.
#' @param arguments For `mcp_content_result()`, arguments for the app's
#'   first tool, called when the card opens.
#' @param text Plain-text fallback shown where the app can't render.
#' @export
mcp_content_result <- function(
  app,
  value,
  arguments = NULL,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE,
  text = NULL
) {
  app <- as_mcp_app(app)
  tool <- default_entry_tool(app)
  request <- ellmer::ContentToolRequest(
    id = unique_id("call"),
    name = tool %||% app$name,
    arguments = arguments %||% list()
  )
  live_card_result(
    app = app,
    value = value,
    title = title,
    icon = icon,
    open = open,
    show_request = show_request,
    full_screen = full_screen,
    text = text %||%
      if (is.character(value)) {
        paste(value, collapse = "\n")
      } else {
        as.character(to_json(value, pretty = TRUE))
      },
    tool = tool,
    arguments = arguments,
    request = request
  )
}
