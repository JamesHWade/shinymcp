# mcp_chat_host(): MCP Apps in a shinychat conversation, with the model loop
#
# as_shinychat_tool() shows apps in cards. A chat host also does what an MCP
# App expects of its host: what the app tells the host about its state
# (ui/update-model-context) reaches the model with the person's next
# message, and messages the app asks to post (ui/message) go to the chat.
#
# The context is added from ellmer's on_request_start(), which can change
# the turns before the one being sent but not that one, so it is a user
# turn of its own, just before the person's. It is added only before a
# message from the person (tool results must follow their tool calls), and
# taken out again once the reply is complete, so the model sees each app's
# current state and the saved conversation keeps only what was said. See
# design/hosting.md.

#' Host MCP Apps in a shinychat conversation
#'
#' @description
#' `mcp_chat_host()` gives the model in a shinychat conversation the tools
#' of one or more MCP Apps, and shows each app it opens in the
#' conversation, live. The apps can be [McpApp]s in the same R process, or
#' come from any MCP server through [mcp_client()].
#'
#' It also does what an app expects of the chat that hosts it:
#'
#' * **What the person does in an app reaches the model.** Before each
#'   message the person sends, the model is told what each open app reports
#'   about what it shows (its model context). The model sees the apps'
#'   current state, not earlier ones, and the saved conversation doesn't
#'   keep it.
#' * **Apps can suggest messages.** A message an app asks to post goes into
#'   the chat's input box, for the person to read and send.
#' * **Saved conversations come back live.** Cards restored with a
#'   conversation show their apps again, without calling the tools again.
#'
#' What apps report is written by the apps, so treat it like anything else
#' a tool returns: the model is told where it came from, and each app's
#' report is cut to 2,000 characters, from the five apps that changed most
#' recently.
#'
#' A session can have several chats, each with its own `mcp_chat_host()`.
#' Each chat's model is told about, and gets messages from, only the cards
#' its tools opened. A card built with [mcp_content_result()] belongs to
#' the session's chat when there's only one.
#'
#' `on_app_call` checks the tool calls that apps' pages make in the chat's
#' cards, such as when the person presses a button in one; the model's own
#' calls aren't passed to it. It applies to the cards the chat's tools
#' open, cards restored with the conversation, and cards built with
#' [mcp_content_result()] while it's the session's only chat.
#'
#' @inheritSection mcp_host_ui Checking the app's calls
#'
#' @param chat The value of [shinychat::chat_server()], or an ellmer chat.
#'   With an ellmer chat, pass `chat_id` too, so apps' messages can reach
#'   the input box.
#' @param sources Where the apps come from: an [McpApp], an [McpClient], or
#'   a list of them.
#' @param context Whether to tell the model what the open apps show. The
#'   report goes to the model as a message of its own, just before the
#'   person's, and some providers (AWS Bedrock) refuse two user messages in
#'   a row. For those, set `context = FALSE` and add `host$context()` to
#'   the person's message yourself.
#' @param messages What to do with messages apps ask to post: `"compose"`
#'   puts them in the input box, `"submit"` sends them at once (for apps you
#'   trust), `"ignore"` drops them.
#' @param chat_id With an ellmer chat, the id of the [shinychat::chat_ui()].
#' @param on_app_call A function that checks each tool call the pages of
#'   the chat's cards make before it's sent, to let it through, refuse it,
#'   or record it. See "Checking the app's calls" below. `NULL`, the
#'   default, lets through every call the apps may make.
#' @param ... Passed to [as_shinychat_tool()]: `value_fn`, `summary`,
#'   `title`, `icon`, `open`, `show_request`, and `full_screen`.
#' @param session The Shiny session.
#' @return Invisibly, a list with `context()`, which returns the text the
#'   model is given about the open apps (or `NULL`), and `tools`, the ellmer
#'   tools registered with the chat.
#' @family hosting
#' @export
#' @examples
#' \dontrun{
#' library(shiny)
#' library(shinychat)
#'
#' ui <- bslib::page_fillable(chat_ui("chat"))
#' server <- function(input, output, session) {
#'   chat <- chat_server("chat", ellmer::chat("anthropic/claude-sonnet-5"))
#'   mcp_chat_host(chat, list(
#'     cars_app,
#'     mcp_client("https://connect.example.com/sales/mcp")
#'   ))
#' }
#' shinyApp(ui, server)
#' }
mcp_chat_host <- function(
  chat,
  sources,
  context = TRUE,
  messages = c("compose", "submit", "ignore"),
  chat_id = NULL,
  ...,
  on_app_call = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  rlang::check_installed(
    c("ellmer", "shiny", "shinychat", "promises", "later", "S7"),
    reason = "to host MCP Apps in a shinychat conversation."
  )
  messages <- rlang::arg_match(messages)
  check_app_call_hook(on_app_call)
  session <- root_shiny_session(session)
  if (is.null(session)) {
    shinymcp_abort(
      "Call {.fn mcp_chat_host} in a Shiny server function.",
      class = "shinymcp_error_validation"
    )
  }
  resolved <- resolve_chat(chat, chat_id, session)
  client <- resolved$client

  sources <- as_host_sources(sources)
  registry <- ensure_shiny_host_registry(session)
  for (source in sources) {
    register_host_source(registry, source, on_app_call)
  }
  # Several chats can share a session; each card is its chat's. The key is
  # saved with the card, so it has to be the same in every session: the
  # chat's id, or else its place among the session's chat hosts.
  key <- chat_host_key(registry, chat_id)
  card <- chat_card_options(...)
  card$owner <- key
  tools <- unname(unlist(
    lapply(sources, function(source) {
      shinychat_tools(source, session = session, card = card)
    }),
    recursive = FALSE
  ))
  client$register_tools(tools)

  if (isTRUE(context)) {
    removers <- install_app_context(client, registry, key)
    session$onSessionEnded(function() {
      for (remove in removers) {
        try(remove(), silent = TRUE)
      }
    })
  }

  on_message <- if (messages != "ignore") {
    function(state, params) {
      text <- host_content_text(list(content = params$content))
      if (!nzchar(text)) {
        return(invisible())
      }
      if (is.null(resolved$compose)) {
        cli::cli_warn(
          "An app asked to post a message, but {.fn mcp_chat_host} can't reach the chat's input box. Pass {.arg chat_id}."
        )
        return(invisible())
      }
      resolved$compose(text, submit = identical(messages, "submit"))
    }
  }
  # The cards that belong to the chat (see card_chat_key()) are checked by
  # its on_app_call.
  registry$chat_hosts[[key]] <- list(
    on_message = on_message,
    on_app_call = on_app_call
  )

  invisible(list(
    context = function() host_context_text(registry, key),
    tools = tools
  ))
}

#' The key a chat host's cards carry
#' @noRd
chat_host_key <- function(registry, chat_id = NULL) {
  taken <- names(registry$chat_hosts)
  key <- chat_id %||% paste0("chat-", length(taken) + 1L)
  utils::tail(make.unique(c(taken, key)), 1)
}

#' The ellmer client of a chat, and a way to fill its input box
#' @noRd
resolve_chat <- function(chat, chat_id, session) {
  if (inherits(chat, "Chat")) {
    compose <- if (!is.null(chat_id)) {
      function(text, submit = FALSE) {
        shinychat::update_chat_user_input(
          chat_id,
          value = text,
          submit = submit,
          focus = !submit,
          session = session
        )
      }
    }
    return(list(client = chat, compose = compose))
  }
  client <- if (is.environment(chat) || is.list(chat)) {
    tryCatch(chat$client, error = function(e) NULL)
  }
  if (!inherits(client, "Chat")) {
    shinymcp_abort(
      "{.arg chat} must be the value of {.fn shinychat::chat_server}, or an ellmer chat.",
      class = "shinymcp_error_validation"
    )
  }
  update <- chat$update_user_input
  compose <- if (is.function(update)) {
    function(text, submit = FALSE) {
      update(value = text, submit = submit, focus = !submit)
    }
  }
  list(client = client, compose = compose)
}

#' @noRd
chat_card_options <- function(
  value_fn = NULL,
  summary = NULL,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE
) {
  list(
    value_fn = value_fn,
    summary = summary,
    title = title,
    icon = icon,
    open = open,
    show_request = show_request,
    full_screen = full_screen
  )
}

# ---- Context for the model ----

#' Give the model the open apps' context before each message
#'
#' @return Functions that remove the callbacks.
#' @noRd
install_app_context <- function(client, registry, owner = NULL) {
  inserted <- list()

  without_inserted <- function(turns) {
    Filter(
      function(turn) {
        !any(vapply(inserted, identical, logical(1), turn))
      },
      turns
    )
  }

  on_start <- function(turns) {
    pending <- turns[[length(turns)]]
    if (!is_person_turn(pending)) {
      return(invisible())
    }
    current <- client$get_turns()
    kept <- without_inserted(current)
    inserted <<- list()
    text <- host_context_text(registry, owner)
    if (!is.null(text)) {
      turn <- ellmer::UserTurn(text)
      inserted <<- list(turn)
      kept <- c(kept, list(turn))
    }
    if (!identical(kept, current)) {
      client$set_turns(kept)
    }
    invisible()
  }

  on_end <- function(turn) {
    if (length(inserted) == 0 || has_tool_requests(turn)) {
      return(invisible())
    }
    current <- client$get_turns()
    kept <- without_inserted(current)
    inserted <<- list()
    if (length(kept) != length(current)) {
      client$set_turns(kept)
    }
    invisible()
  }

  list(client$on_request_start(on_start), client$on_request_end(on_end))
}

#' Is a turn a message from the person (not tool results)?
#' @noRd
is_person_turn <- function(turn) {
  if (!S7::S7_inherits(turn, ellmer::UserTurn)) {
    return(FALSE)
  }
  contents <- S7::prop(turn, "contents")
  !any(vapply(
    contents,
    function(x) S7::S7_inherits(x, ellmer::ContentToolResult),
    logical(1)
  ))
}

#' @noRd
has_tool_requests <- function(turn) {
  if (is.null(turn) || !S7::S7_inherits(turn, ellmer::Turn)) {
    return(FALSE)
  }
  any(vapply(
    S7::prop(turn, "contents"),
    function(x) S7::S7_inherits(x, ellmer::ContentToolRequest),
    logical(1)
  ))
}

#' What the open apps in a conversation report, for the model
#'
#' Each card's latest model context, cut to `max_chars`, from the
#' `max_apps` apps that reported most recently, oldest first. With `owner`,
#' only that chat host's cards.
#' @noRd
host_context_text <- function(
  registry,
  owner = NULL,
  max_apps = 5,
  max_chars = 2000
) {
  states <- Filter(
    function(state) {
      !is.null(state$model_context) &&
        nzchar(host_content_text(state$model_context)) &&
        (is.null(owner) || identical(card_chat_key(registry, state), owner))
    },
    host_instances(registry, "card")
  )
  if (length(states) == 0) {
    return(NULL)
  }
  times <- vapply(states, function(s) s$context_time %||% 0, numeric(1))
  states <- utils::head(states[order(times, decreasing = TRUE)], max_apps)
  states <- rev(states)
  blocks <- vapply(
    states,
    function(state) {
      text <- host_content_text(state$model_context, limit = max_chars)
      text <- gsub("</app-context", "<\\/app-context", text, fixed = TRUE)
      sprintf(
        "<app-context app=\"%s\" id=\"%s\">\n%s\n</app-context>",
        htmltools::htmlEscape(state$title %||% state$tool, attribute = TRUE),
        htmltools::htmlEscape(state$instance_id, attribute = TRUE),
        text
      )
    },
    character(1)
  )
  paste(
    c(
      paste(
        "The person has these apps open in the conversation. Each app reports",
        "what it shows now; the reports come from the apps, not from the person."
      ),
      blocks
    ),
    collapse = "\n\n"
  )
}
