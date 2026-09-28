# shinychat integration: MCP Apps as live tool cards

#' Use an MCP App's tools in a shinychat conversation
#'
#' @description
#' `as_shinychat_tool()` turns the tools of an app, or of a remote MCP
#' server, into [ellmer::tool()] objects for a chat built with shinychat.
#' When the model calls one that shows an app, shinychat shows the app,
#' live, in the tool's card. The model gets the tool's structured result
#' (or the text, if there is none); the person gets the app.
#'
#' [mcp_chat_host()] does this for you and also passes what the person does
#' in the cards on to the model. Use `as_shinychat_tool()` on its own for
#' cards without that.
#'
#' For a remote server, call `as_shinychat_tool()` where the app starts,
#' outside the server function, and register the tools in each session:
#' listing a server's tools waits for it. In a Shiny session it uses only
#' the list the client already has, and is an error without one.
#'
#' `mcp_content_result()` builds a card by hand, for a result you append to
#' the chat yourself.
#'
#' @param source Where the tools come from: an [McpApp] (or a list of
#'   them), or an [McpClient] from [mcp_client()].
#' @param tool Names of the tools to wrap. Defaults to every tool the model
#'   may call. For `mcp_content_result()`, the tool that opens the app: by
#'   default the first the model may call that shows one. Name it for a
#'   remote server.
#' @param value_fn Optional function computing the value returned to the
#'   model. It can take any of `result` (the MCP result), `arguments` (the
#'   model's, as parsed JSON: arrays are lists), and, for apps in this
#'   process, `raw_result` (what the tool function returned).
#' @param summary Optional text shown in the card when it can't show the
#'   app, or a function taking the same arguments as `value_fn`.
#' @param title,icon Card title and icon (a string or tag, or a function
#'   taking the same arguments as `value_fn`). Default to the tool's title.
#' @param open Whether the card starts expanded.
#' @param show_request Whether the card shows the call's arguments.
#' @param full_screen Whether the card offers a full-screen view.
#' @return For one tool, an [ellmer::tool()]; for several, a named list of
#'   them. `mcp_content_result()` returns an [ellmer::ContentToolResult]. In
#'   a Shiny session it calls the tool first and returns a promise of the
#'   card, which [shinychat::chat_append()] waits for; the card is saved
#'   with the app's opening result, so a restored conversation shows the app
#'   without calling the tool again.
#' @family hosting
#' @export
#' @examples
#' \dontrun{
#' chat <- ellmer::chat("anthropic/claude-sonnet-5")
#' chat$register_tool(as_shinychat_tool(app, title = "Penguins"))
#' }
as_shinychat_tool <- function(
  source,
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
    reason = "to use MCP Apps in a shinychat conversation."
  )
  source <- as_host_source(source)
  # In a Shiny session a remote server's tools come from the list its
  # client already has: listing them would hold up the session.
  listed <- NULL
  if (
    inherits(source, "shinymcp_host_source_remote") &&
      !is.null(active_shiny_session())
  ) {
    listed <- source$tools(wait = FALSE)
    if (is.null(listed)) {
      shinymcp_abort(
        c(
          "Make {.val {source$key}}'s tools where the app starts, not in a Shiny session.",
          "i" = "Listing a remote server's tools waits for it, which would hold up the session. Call {.fn as_shinychat_tool} outside the server function and register its tools in each session.",
          "i" = "A client made in the session can list them first with {.code $tools()}, which waits."
        ),
        class = "shinymcp_error_validation"
      )
    }
  }
  tools <- shinychat_tools(
    source,
    tool = tool,
    session = NULL,
    listed = listed,
    card = list(
      value_fn = value_fn,
      summary = summary,
      title = title,
      icon = icon,
      open = open,
      show_request = show_request,
      full_screen = full_screen
    )
  )
  if (length(tools) == 1) tools[[1]] else tools
}

#' ellmer tools for a source's tools the model may call
#'
#' @param session The Shiny session cards are shown in, or `NULL` for the
#'   one active when the tool is called.
#' @param listed The source's tools, if already listed.
#' @noRd
shinychat_tools <- function(
  source,
  tool = NULL,
  session = NULL,
  card = list(),
  listed = NULL
) {
  definitions <- Filter(
    function(t) tool_wire_visible_to(t, "model"),
    listed %||% source$tools()
  )
  names(definitions) <- vapply(definitions, function(t) t$name, character(1))
  if (!is.null(tool)) {
    unknown <- setdiff(tool, names(definitions))
    if (length(unknown)) {
      shinymcp_abort(
        "{.val {source$key}} has no tool the model can call named {.val {unknown}}.",
        class = "shinymcp_error_validation"
      )
    }
    definitions <- definitions[tool]
  }
  if (length(definitions) == 0) {
    shinymcp_abort(
      "{.val {source$key}} has no tools for the model to call.",
      class = "shinymcp_error_validation"
    )
  }
  # The model's arguments go to the source as it sent them: ellmer's
  # conversion would make an array of one value a single value, which the
  # tool then refuses.
  lapply(definitions, function(definition) {
    ellmer::tool(
      shinychat_tool_function(source, definition, session, card),
      name = definition$name,
      description = definition$description %||% definition$title %||% "",
      arguments = schema_to_ellmer_types(definition$inputSchema %||% list()),
      convert = FALSE,
      annotations = shinychat_annotations(definition, card$title)
    )
  })
}

#' @noRd
shinychat_annotations <- function(definition, title = NULL) {
  ann <- definition$annotations %||% list()
  args <- compact_list(list(
    title = if (is.character(title)) title else definition$title %||% ann$title,
    read_only_hint = ann$readOnlyHint,
    destructive_hint = ann$destructiveHint,
    idempotent_hint = ann$idempotentHint,
    open_world_hint = ann$openWorldHint
  ))
  do.call(ellmer::tool_annotations, args)
}

#' Build the function behind a shinychat tool
#' @noRd
shinychat_tool_function <- function(source, definition, session, card) {
  arg_names <- names(definition$inputSchema$properties %||% list())
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
    run_shinychat_tool(source, definition, arguments, session, card)
  }
  formals(fun) <- rlang::rep_named(arg_names, list(rlang::missing_arg()))
  fun
}

#' Call a tool for the model and make its card
#'
#' In a Shiny session the call is asynchronous (the tool returns a promise,
#' which ellmer waits for); outside one it blocks.
#' @noRd
run_shinychat_tool <- function(source, definition, arguments, session, card) {
  session <- session %||% active_shiny_session()
  context <- list(transport = "shinychat")
  finish <- function(call) {
    shinychat_card(source, definition, arguments, call, session, card)
  }
  if (is.null(session)) {
    return(finish(source$call(definition$name, arguments, context)))
  }
  rlang::check_installed(
    c("promises", "later"),
    reason = "to call MCP App tools from a Shiny chat."
  )
  context <- utils::modifyList(host_call_context(session), context)
  promises::then(
    source$call_async(definition$name, arguments, context),
    finish
  )
}

#' The tool result the model gets, with the card shinychat shows
#' @noRd
shinychat_card <- function(source, definition, arguments, call, session, card) {
  result <- call$result
  context <- list(raw_result = call$raw, result = result, arguments = arguments)
  if (isTRUE(result$isError)) {
    text <- result_text(result)
    return(ellmer::ContentToolResult(
      error = if (nzchar(text)) text else "The tool failed."
    ))
  }
  value <- if (is.function(card$value_fn)) {
    call_with_supported_args(card$value_fn, context)
  } else {
    default_model_value(result)
  }
  if (is.null(tool_resource_uri(definition))) {
    return(ellmer::ContentToolResult(value = value))
  }
  resolve <- function(x) {
    if (is.function(x)) call_with_supported_args(x, context) else x
  }
  live_card_result(
    source = source,
    value = value,
    title = resolve(card$title) %||% definition$title,
    icon = resolve(card$icon),
    open = card$open %||% TRUE,
    show_request = card$show_request %||% FALSE,
    full_screen = card$full_screen %||% TRUE,
    text = resolve(card$summary) %||% result_text(result),
    tool = definition$name,
    arguments = arguments,
    result = result,
    session = session,
    owner = card$owner
  )
}

#' The value the model sees for a tool result
#'
#' The structured result, except when it's empty (`{}`), or a single value
#' that was wrapped only because structuredContent has to be an object: the
#' text says more, or reads better.
#' @noRd
default_model_value <- function(result) {
  structured <- result$structuredContent
  lone_value <- identical(names(structured), "value") &&
    is.atomic(structured$value) &&
    length(structured$value) <= 1
  if (length(structured) == 0 || lone_value) {
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
#'
#' In a Shiny session the card carries a descriptor of the app's instance;
#' the host script attaches it and loads the page. Outside one, it shows
#' `text`.
#' @noRd
live_card_result <- function(
  source,
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
  request = NULL,
  session = NULL,
  owner = NULL
) {
  rlang::check_installed("ellmer", reason = "for shinychat tool results.")
  display <- compact_list(list(
    title = title,
    icon = icon,
    open = open,
    show_request = show_request,
    full_screen = full_screen
  ))
  session <- session %||% active_shiny_session()
  if (!is.null(session)) {
    registered <- register_shiny_host_instance(
      session = session,
      source = source,
      tool = tool,
      arguments = arguments,
      result = result,
      kind = "card",
      title = if (is.character(title)) title,
      owner = owner
    )
    if (is.null(result)) {
      start_host_call(root_shiny_session(session), registered$state)
    }
    display$html <- mcp_host_markup(
      sanitize_dom_id(registered$state$instance_id),
      config = registered$config,
      toolbar = FALSE,
      fallback = if (is_string(text) && nzchar(text)) text
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
#' @param arguments For `mcp_content_result()`, arguments for the tool that
#'   opens the app, called when the card is shown, as a client would send
#'   them. A vector of one value is one value; write an array of one as
#'   `list(x)`.
#' @param text Plain-text fallback shown where the app can't render.
#' @export
mcp_content_result <- function(
  source,
  value,
  tool = NULL,
  arguments = NULL,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE,
  text = NULL
) {
  rlang::check_installed("ellmer", reason = "for shinychat tool results.")
  source <- as_host_source(source)
  # The card is saved naming its tool. Picking a remote server's default
  # would mean listing its tools here, holding up the session.
  if (is.null(tool) && !in_process_source(source)) {
    shinymcp_abort(
      c(
        "Name the {.arg tool} that opens the app.",
        "i" = "{.val {source$key}} is a remote server; listing its tools here would hold up the Shiny session."
      ),
      class = "shinymcp_error_validation"
    )
  }
  tool <- tool %||% default_source_tool(source)
  request <- ellmer::ContentToolRequest(
    id = unique_id("call"),
    name = tool %||% source$key,
    arguments = arguments %||% list()
  )
  card <- function(result = NULL, session = NULL) {
    live_card_result(
      source = source,
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
      result = result,
      request = request,
      session = session
    )
  }
  session <- active_shiny_session()
  if (is.null(session) || is.null(tool)) {
    return(card())
  }
  # The tool is called before the card is made, so the card is saved with
  # the app's opening result: a restored card never calls its tool.
  rlang::check_installed(
    c("promises", "later"),
    reason = "to open MCP Apps in a Shiny chat."
  )
  if (in_process_source(source)) {
    # A mistake in the tool is an error here, as for a pane.
    host_tool(source, source$tools(), tool)
  }
  promises::then(
    source$call_async(tool, arguments %||% list(), host_call_context(session)),
    function(call) {
      if (isTRUE(call$result$isError)) {
        text <- result_text(call$result)
        return(ellmer::ContentToolResult(
          error = if (nzchar(text)) text else "The tool failed.",
          request = request
        ))
      }
      card(call$result, session)
    }
  )
}
