library(shiny)
library(bslib)
library(ellmer)
library(shinychat)
library(shinymcp)

current_file <- function() {
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    if (!is.null(frames[[i]]$ofile)) {
      return(normalizePath(frames[[i]]$ofile))
    }
  }
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]])))
  }
  normalizePath("shinychat-app.R", mustWork = FALSE)
}

example_dir <- dirname(current_file())
source(file.path(example_dir, "apps.R"), local = TRUE)

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

use_cases <- shinymcp_use_cases()

tool_title <- function(label) {
  force(label)
  function(raw_result, arguments, ...) {
    intent <- arguments[["_intent"]]
    if (!is.null(intent) && nzchar(intent)) {
      return(paste(label, "-", intent))
    }
    label
  }
}

tool_summary <- function(field = "summary") {
  force(field)
  function(raw_result, ...) {
    value <- raw_result[[field]]
    if (inherits(value, "shinymcp_result")) {
      return(value$text %||% as.character(value$value))
    }
    paste(capture.output(str(value, give.attr = FALSE)), collapse = "\n")
  }
}

use_case_tools <- list(
  as_shinychat_tool(
    use_cases$revenue,
    title = tool_title("Revenue Scenario Board"),
    summary = tool_summary("summary"),
    open = TRUE
  ),
  as_shinychat_tool(
    use_cases$experiment,
    title = tool_title("Experiment Planner"),
    summary = tool_summary("summary"),
    open = TRUE
  ),
  as_shinychat_tool(
    use_cases$incident,
    title = tool_title("Incident Triage Console"),
    summary = tool_summary("briefing"),
    open = TRUE
  )
)

has_openai_key <- nzchar(Sys.getenv("OPENAI_API_KEY"))

ui <- page_fillable(
  fillable_mobile = TRUE,
  theme = bs_theme(preset = "shiny", primary = "#1a8a9e"),
  titlePanel("shinymcp use-case chat"),
  if (has_openai_key) {
    chat_mod_ui(
      "chat",
      messages = list(
        list(
          role = "assistant",
          content = paste(
            "Ask for a revenue forecast, experiment plan, or incident triage.",
            "Each tool call returns a live shinymcp card in the chat."
          )
        )
      )
    )
  } else {
    chat_ui(
      "chat",
      messages = list(
        list(
          role = "assistant",
          content = paste(
            "Local demo mode: ask for revenue, experiment, or incident.",
            "No model provider is configured, so the app will append a live",
            "shinymcp card directly."
          )
        )
      )
    )
  }
)

local_demo_card <- function(message) {
  message <- tolower(message %||% "")

  if (grepl("experiment|test|sample|power", message)) {
    return(mcp_content_result(
      app = use_cases$experiment,
      value = list(card = "experiment"),
      title = "Experiment Planner"
    ))
  }

  if (grepl("incident|outage|triage|runbook", message)) {
    return(mcp_content_result(
      app = use_cases$incident,
      value = list(card = "incident"),
      title = "Incident Triage Console"
    ))
  }

  mcp_content_result(
    app = use_cases$revenue,
    value = list(card = "revenue"),
    title = "Revenue Scenario Board"
  )
}

server <- function(input, output, session) {
  if (has_openai_key) {
    client <- ellmer::chat("openai/gpt-4.1-nano")
    for (tool in use_case_tools) {
      client$register_tool(tool)
    }
    chat_mod_server("chat", client)
  } else {
    observeEvent(input$chat_user_input, {
      chat_append("chat", local_demo_card(input$chat_user_input))
    })
  }
}

shinyApp(ui, server)
