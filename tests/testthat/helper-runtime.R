# Helpers for driving the live Shiny runtime the way the protocol does.
#
# The model calls the app tool (named after the app); the page calls the
# view tool (`<tool>_view`) with the view's instance id and its inputs.
# Names are prefixed with `rt_` to stay clear of package internals and other
# helper files.

# An McpApp served from a Shiny app, with the live runtime.
rt_app <- function(ui, server, name = "app", ...) {
  as_mcp_app(shiny::shinyApp(ui, server), name = name, ...)
}

# `_meta["shinymcp/view"]` of a wire result.
rt_meta <- function(result) {
  result[["_meta"]][["shinymcp/view"]]
}

# The text block the model reads.
rt_text <- function(result) {
  result$content[[1]]$text
}

# Content block types, in order.
rt_content_types <- function(result) {
  vapply(result$content, function(block) block$type, character(1))
}

# The model opens (or, with `view`, steers) the app.
rt_open <- function(app, arguments = list(), context = list()) {
  app$run_tool(app$runtime()$tool_name, arguments, context = context)
}

# The page calls the view tool. `view` is the `shinymcp/view` meta of an
# earlier result (for its instance id and revision).
rt_update <- function(
  app,
  view,
  inputs = list(),
  changed = NULL,
  ...,
  revision = view$revision,
  context = list()
) {
  arguments <- list(
    action = "update",
    instance = view$instance,
    revision = revision,
    inputs = inputs,
    changed = if (!is.null(changed)) as.list(changed),
    ...
  )
  arguments <- arguments[!vapply(arguments, is.null, logical(1))]
  app$run_tool(
    app$runtime()$view_tool_name,
    arguments,
    context = utils::modifyList(list(caller = "app"), context)
  )
}

# The runtime's private state (the instances environment lives there).
rt_private <- function(app) {
  app$runtime()$.__enclos_env__$private
}

# The environment behind one view.
rt_instance <- function(app, id) {
  rt_private(app)$instances[[id]]
}

# The current value of an input in a view's session.
rt_session_input <- function(app, id, input_id) {
  shiny::isolate(rt_instance(app, id)$session$input[[input_id]])
}

# shinyAppDir()'s onStart sources global.R and attaches shiny (reading ui.R
# does). Keep the working directory and search path as they were when the
# test ends, whatever the runtime does.
local_app_dir_side_effects <- function(env = parent.frame()) {
  withr::local_dir(getwd(), .local_envir = env)
  attached <- "package:shiny" %in% search()
  withr::defer(
    if (!attached && "package:shiny" %in% search()) {
      detach("package:shiny", character.only = TRUE)
    },
    envir = env
  )
}
