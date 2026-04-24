# Typed result helpers and shinychat integration.

#' @noRd
new_mcp_result <- function(kind, value, model_value = NULL, text = NULL) {
  structure(
    list(
      kind = kind,
      value = value,
      model_value = model_value,
      text = text
    ),
    class = "shinymcp_result"
  )
}

#' Build a typed text result
#'
#' @param value Text value.
#' @param model_value Optional machine-facing value. Defaults to `value`.
#' @export
mcp_result_text <- function(value, model_value = value) {
  new_mcp_result("text", as.character(value), model_value, as.character(value))
}

#' Build a typed HTML result
#'
#' @param html HTML string or htmltools tag object.
#' @param model_value Optional machine-facing value.
#' @param text Optional plain-text fallback.
#' @export
mcp_result_html <- function(html, model_value = NULL, text = NULL) {
  new_mcp_result("html", html, model_value, text)
}

#' Build a typed table result
#'
#' @param data A data frame, matrix, or table-like object.
#' @param model_value Optional machine-facing value. Defaults to `data`.
#' @param text Optional plain-text fallback.
#' @export
mcp_result_table <- function(data, model_value = data, text = NULL) {
  new_mcp_result("table", data, model_value, text)
}

#' Build a typed plot result
#'
#' @param plot A plotting function, ggplot object, recorded plot, or image path.
#' @param model_value Optional machine-facing value.
#' @param text Optional plain-text fallback.
#' @export
mcp_result_plot <- function(plot, model_value = NULL, text = NULL) {
  new_mcp_result("plot", plot, model_value, text)
}

#' Build a typed image result
#'
#' @param path_or_data Image path or raw/base64 data.
#' @param model_value Optional machine-facing value.
#' @param text Optional plain-text fallback.
#' @export
mcp_result_image <- function(path_or_data, model_value = NULL, text = NULL) {
  new_mcp_result("image", path_or_data, model_value, text)
}

#' Build a typed PDF result
#'
#' @param path_or_data PDF path or raw/base64 data.
#' @param model_value Optional machine-facing value.
#' @param text Optional plain-text fallback.
#' @export
mcp_result_pdf <- function(path_or_data, model_value = NULL, text = NULL) {
  new_mcp_result("pdf", path_or_data, model_value, text)
}

#' Build a typed widget result
#'
#' @param ui htmltools tag or tagList.
#' @param model_value Optional machine-facing value.
#' @param text Optional plain-text fallback.
#' @export
mcp_result_widget <- function(ui, model_value = NULL, text = NULL) {
  new_mcp_result("widget", ui, model_value, text)
}

#' @noRd
is_mcp_result <- function(x) {
  inherits(x, "shinymcp_result")
}

#' @noRd
call_with_supported_args <- function(fn, args) {
  if (!is.function(fn)) {
    return(fn)
  }
  formals_names <- names(formals(fn))
  if (is.null(formals_names)) {
    return(fn())
  }
  if ("..." %in% formals_names) {
    return(do.call(fn, args))
  }
  supported <- args[intersect(names(args), formals_names)]
  do.call(fn, supported)
}

#' @noRd
schema_properties_to_arguments <- function(schema) {
  props <- schema$properties %||% list()
  lapply(props, function(prop) {
    description <- prop$description %||% ""
    switch(
      prop$type %||% "string",
      string = ellmer::type_string(description),
      number = ellmer::type_number(description),
      integer = ellmer::type_integer(description),
      boolean = ellmer::type_boolean(description),
      ellmer::type_string(description)
    )
  })
}

#' @noRd
tool_formals <- function(tool) {
  if (is_ellmer_tool(tool)) {
    return(formals(tool))
  }
  if (is.list(tool) && is.function(tool$fun)) {
    return(formals(tool$fun))
  }
  as.pairlist(list())
}

#' @noRd
ellmer_tool_arguments <- function(tool) {
  arguments <- tool@arguments
  if (inherits(arguments, "ellmer::TypeObject")) {
    return(arguments@properties)
  }
  arguments
}

#' @noRd
as_shinychat_request_tool <- function(tool) {
  if (is.null(tool)) {
    return(NULL)
  }

  if (is_ellmer_tool(tool)) {
    return(tool)
  }

  if (!is.list(tool)) {
    return(NULL)
  }

  arguments <- schema_properties_to_arguments(
    tool$inputSchema %||%
      list(
        type = "object",
        properties = list()
      )
  )
  fun <- tool$fun
  if (!is.function(fun)) {
    fun <- function() NULL
    formals(fun) <- as.pairlist(
      stats::setNames(
        rep(list(NULL), length(arguments)),
        names(arguments)
      )
    )
  }

  ellmer::tool(
    fun = fun,
    name = tool_name(tool),
    description = tool$description %||% "",
    arguments = arguments,
    annotations = tool$annotations %||% list()
  )
}

#' @noRd
resolve_shinychat_request_source <- function(
  app,
  request_tool_name = NULL,
  app_tool = NULL
) {
  if (!is.null(app_tool)) {
    return(list(
      name = request_tool_name %||% tool_name(app_tool),
      tool = as_shinychat_request_tool(app_tool)
    ))
  }

  app <- as_mcp_app(app)
  app_tools <- app$mcp_tools()

  if (!is.null(request_tool_name)) {
    for (candidate in app_tools) {
      if (identical(tool_name(candidate), request_tool_name)) {
        app_tool <- candidate
        break
      }
    }
  } else if (length(app_tools) == 1) {
    app_tool <- app_tools[[1]]
  }

  if (!is.null(app_tool)) {
    return(list(
      name = tool_name(app_tool),
      tool = as_shinychat_request_tool(app_tool)
    ))
  }

  list(
    name = app$name %||% "shinymcp-app",
    tool = NULL
  )
}

#' @noRd
build_shinychat_request <- function(
  app,
  initial_arguments = NULL,
  request_tool_name = NULL,
  app_tool = NULL
) {
  source <- resolve_shinychat_request_source(
    app = app,
    request_tool_name = request_tool_name,
    app_tool = app_tool
  )

  ellmer::ContentToolRequest(
    id = unique_id("mcp-request"),
    name = source$name,
    arguments = initial_arguments %||% list(),
    tool = source$tool
  )
}

#' @noRd
build_shinychat_wrapper_fun <- function(
  app,
  app_tool,
  tool_nm,
  value_fn,
  summary,
  title,
  icon,
  open,
  show_request,
  full_screen
) {
  wrapped <- function() {}
  formals(wrapped) <- tool_formals(app_tool)

  environment(wrapped) <- list2env(
    list(
      APP = app,
      APP_TOOL = app_tool,
      TOOL_NM = tool_nm,
      VALUE_FN = value_fn,
      SUMMARY_FN = summary,
      TITLE_FN = title,
      ICON_FN = icon,
      OPEN_FLAG = open,
      SHOW_REQUEST_FLAG = show_request,
      FULL_SCREEN_FLAG = full_screen
    ),
    parent = environment()
  )

  body(wrapped) <- quote({
    args <- as.list(environment())
    raw_result <- APP$call_tool(TOOL_NM, args)
    context_args <- list(
      raw_result = raw_result,
      arguments = args,
      app = APP,
      tool = APP_TOOL,
      tool_name = TOOL_NM
    )

    model_value <- if (is.function(VALUE_FN)) {
      call_with_supported_args(VALUE_FN, context_args)
    } else {
      mcp_result_model_value(raw_result)
    }

    result_title <- if (is.function(TITLE_FN)) {
      call_with_supported_args(TITLE_FN, context_args)
    } else {
      TITLE_FN
    }
    result_icon <- if (is.function(ICON_FN)) {
      call_with_supported_args(ICON_FN, context_args)
    } else {
      ICON_FN
    }
    result_text <- if (is.function(SUMMARY_FN)) {
      call_with_supported_args(SUMMARY_FN, context_args)
    } else {
      SUMMARY_FN
    }

    mcp_content_result_internal(
      app = APP,
      value = model_value,
      title = result_title,
      icon = result_icon,
      open = OPEN_FLAG,
      show_request = SHOW_REQUEST_FLAG,
      full_screen = FULL_SCREEN_FLAG,
      text = result_text,
      intent = args[["_intent"]] %||% NULL,
      initial_arguments = args,
      request_tool_name = TOOL_NM,
      app_tool = APP_TOOL
    )
  })

  wrapped
}

#' @noRd
render_html_fragment <- function(x) {
  if (inherits(x, "shiny.tag.list")) {
    return(htmltools::renderTags(x)$html)
  }
  if (inherits(x, "shiny.tag")) {
    return(htmltools::renderTags(htmltools::tagList(x))$html)
  }
  as.character(x)
}

#' @noRd
render_table_fragment <- function(x) {
  if (is.character(x) && length(x) == 1) {
    return(x)
  }

  data <- tryCatch(as.data.frame(x), error = function(...) NULL)
  if (is.null(data)) {
    return(render_html_fragment(htmltools::tags$pre(capture.output(print(x)))))
  }

  header <- htmltools::tags$thead(
    htmltools::tags$tr(
      lapply(names(data), htmltools::tags$th)
    )
  )
  rows <- apply(data, 1, function(row) {
    htmltools::tags$tr(
      lapply(row, function(cell) htmltools::tags$td(as.character(cell)))
    )
  })

  render_html_fragment(
    htmltools::tags$table(
      class = "table table-sm",
      header,
      htmltools::tags$tbody(rows)
    )
  )
}

#' @noRd
render_plot_base64 <- function(x) {
  rlang::check_installed("base64enc", reason = "for plot/image encoding")

  if (is.character(x) && length(x) == 1 && file.exists(x)) {
    return(base64enc::base64encode(x))
  }

  tmp <- tempfile(fileext = ".png")
  grDevices::png(tmp, width = 800, height = 500, res = 96)
  on.exit(unlink(tmp), add = TRUE)

  if (is.function(x)) {
    x()
  } else if (inherits(x, "ggplot")) {
    print(x)
  } else if (inherits(x, "recordedplot")) {
    print(x)
  } else {
    print(x)
  }

  grDevices::dev.off()
  base64enc::base64encode(tmp)
}

#' @noRd
render_image_html <- function(x) {
  rlang::check_installed("base64enc", reason = "for image encoding")

  if (is.character(x) && length(x) == 1 && file.exists(x)) {
    ext <- tools::file_ext(x)
    mime <- switch(
      tolower(ext),
      png = "image/png",
      jpg = "image/jpeg",
      jpeg = "image/jpeg",
      gif = "image/gif",
      webp = "image/webp",
      "image/png"
    )
    data_uri <- paste0(
      "data:",
      mime,
      ";base64,",
      base64enc::base64encode(x)
    )
    return(render_html_fragment(
      htmltools::tags$img(
        src = data_uri,
        style = "max-width: 100%; height: auto;"
      )
    ))
  }

  render_html_fragment(
    htmltools::tags$img(
      src = paste0("data:image/png;base64,", as.character(x)),
      style = "max-width: 100%; height: auto;"
    )
  )
}

#' @noRd
render_pdf_html <- function(x) {
  rlang::check_installed("base64enc", reason = "for PDF encoding")

  if (is.character(x) && length(x) == 1 && file.exists(x)) {
    data_uri <- paste0(
      "data:application/pdf;base64,",
      base64enc::base64encode(x)
    )
    return(render_html_fragment(
      htmltools::tags$a(href = data_uri, target = "_blank", "Open PDF")
    ))
  }

  render_html_fragment(htmltools::tags$code("PDF output"))
}

#' @noRd
mcp_result_patch_value <- function(x) {
  if (!is_mcp_result(x)) {
    return(x)
  }

  switch(
    x$kind,
    text = as.character(x$value),
    html = render_html_fragment(x$value),
    table = render_table_fragment(x$value),
    plot = render_plot_base64(x$value),
    image = render_image_html(x$value),
    pdf = render_pdf_html(x$value),
    widget = render_html_fragment(x$value),
    x$value
  )
}

#' @noRd
mcp_result_output_type <- function(x) {
  if (!is_mcp_result(x)) {
    return("text")
  }

  switch(
    x$kind,
    image = "html",
    pdf = "html",
    widget = "html",
    x$kind
  )
}

#' @noRd
mcp_result_wire_payload <- function(x) {
  if (!is_mcp_result(x)) {
    return(NULL)
  }

  list(
    type = mcp_result_output_type(x),
    value = mcp_result_patch_value(x)
  )
}

#' @noRd
mcp_result_model_value <- function(x) {
  if (is_mcp_result(x)) {
    if (!is.null(x$model_value)) {
      return(x$model_value)
    }

    return(
      switch(
        x$kind,
        text = as.character(x$value),
        html = x$text %||% render_html_fragment(x$value),
        table = x$value,
        plot = x$text %||% "[plot]",
        image = x$text %||% "[image]",
        pdf = x$text %||% "[pdf]",
        widget = x$text %||% render_html_fragment(x$value),
        x$value
      )
    )
  }

  if (is.list(x) && !is.null(names(x))) {
    return(lapply(x, mcp_result_model_value))
  }

  x
}

#' @noRd
mcp_result_text_fallback <- function(x) {
  if (is_mcp_result(x)) {
    if (!is.null(x$text)) {
      return(as.character(x$text))
    }

    return(
      switch(
        x$kind,
        text = as.character(x$value),
        html = paste(trimws(gsub(
          "<[^>]+>",
          " ",
          render_html_fragment(x$value)
        ))),
        table = paste(
          capture.output(utils::head(as.data.frame(x$value))),
          collapse = "\n"
        ),
        plot = "[plot]",
        image = "[image]",
        pdf = "[pdf]",
        widget = "[widget]",
        ""
      )
    )
  }

  if (is.character(x)) {
    return(paste(x, collapse = "\n"))
  }

  if (is.list(x) && !is.null(names(x))) {
    parts <- vapply(x, mcp_result_text_fallback, character(1))
    return(paste(parts[nzchar(parts)], collapse = "\n\n"))
  }

  paste(capture.output(str(x, give.attr = FALSE)), collapse = "\n")
}

#' @noRd
mcp_result_structured_content <- function(result) {
  if (is.list(result) && !is.null(names(result))) {
    return(lapply(result, mcp_result_patch_value))
  }

  NULL
}

#' Build a shinychat-friendly tool result with a live embedded card
#'
#' @param app An [McpApp] object.
#' @param value Machine-facing value returned to the model.
#' @param title Optional card title.
#' @param icon Optional card icon.
#' @param open Whether the card starts expanded.
#' @param show_request Whether shinychat should show the request payload.
#' @param full_screen Whether shinychat should offer its full-screen tool-card
#'   mode when supported.
#' @param html Optional HTML display body.
#' @param markdown Optional markdown fallback.
#' @param text Optional plain-text fallback.
#' @param intent Optional display intent metadata.
#' @export
mcp_content_result <- function(
  app,
  value,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE,
  html = NULL,
  markdown = NULL,
  text = NULL,
  intent = NULL
) {
  mcp_content_result_internal(
    app = app,
    value = value,
    title = title,
    icon = icon,
    open = open,
    show_request = show_request,
    full_screen = full_screen,
    html = html,
    markdown = markdown,
    text = text,
    intent = intent,
    initial_arguments = NULL
  )
}

#' @noRd
mcp_content_result_internal <- function(
  app,
  value,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE,
  html = NULL,
  markdown = NULL,
  text = NULL,
  intent = NULL,
  initial_arguments = NULL,
  request_tool_name = NULL,
  app_tool = NULL
) {
  rlang::check_installed("ellmer", reason = "for shinychat tool results")

  display <- compact_list(list(
    title = title,
    icon = icon,
    open = open,
    show_request = show_request,
    full_screen = full_screen,
    intent = intent
  ))

  if (is.null(html) && is.null(markdown) && is.null(text)) {
    session <- active_shiny_session()
    if (!is.null(session) && !is.null(app)) {
      dom_id <- sanitize_dom_id(unique_id("shinymcp-card"))
      registered <- register_shiny_host_instance(
        session = session,
        app = app,
        instance_id = unique_id(paste0("mcp-", as_mcp_app(app)$name)),
        initial_arguments = initial_arguments
      )
      html <- mcp_host_markup(dom_id, registered$config)
    } else {
      text <- mcp_result_text_fallback(value)
    }
  }

  if (!is.null(html)) {
    display$html <- html
  }
  if (!is.null(markdown)) {
    display$markdown <- markdown
  }
  if (!is.null(text)) {
    display$text <- text
  }

  ellmer::ContentToolResult(
    value = value,
    extra = list(display = display),
    request = build_shinychat_request(
      app = app,
      initial_arguments = initial_arguments,
      request_tool_name = request_tool_name,
      app_tool = app_tool
    )
  )
}

#' Wrap an McpApp as an ellmer tool for shinychat
#'
#' Small single-card apps work best here. Multi-tool apps return a list of
#' wrapped ellmer tools, one wrapper per underlying app tool.
#'
#' @param app An [McpApp] object.
#' @param value_fn Optional function that derives the machine-facing value from
#'   the raw tool result.
#' @param summary Optional text fallback or summary function.
#' @param title Optional card title or title function.
#' @param icon Optional card icon or icon function.
#' @param open Whether the card starts expanded.
#' @param show_request Whether shinychat should show the request payload.
#' @param full_screen Whether shinychat should offer its full-screen tool-card
#'   mode when supported.
#' @export
as_shinychat_tool <- function(
  app,
  value_fn = NULL,
  summary = NULL,
  title = NULL,
  icon = NULL,
  open = TRUE,
  show_request = FALSE,
  full_screen = TRUE
) {
  rlang::check_installed("ellmer", reason = "for shinychat tool wrappers")
  app <- as_mcp_app(app)
  app_tools <- app$mcp_tools()

  wrapped <- lapply(app_tools, function(app_tool) {
    tool_nm <- tool_name(app_tool)
    description <- if (is_ellmer_tool(app_tool)) {
      app_tool@description %||% ""
    } else {
      app_tool$description %||% ""
    }

    arguments <- if (is_ellmer_tool(app_tool)) {
      ellmer_tool_arguments(app_tool)
    } else {
      schema_properties_to_arguments(
        app_tool$inputSchema %||%
          list(
            type = "object",
            properties = list()
          )
      )
    }

    annotations <- if (is_ellmer_tool(app_tool)) {
      app_tool@annotations %||% list()
    } else {
      app_tool$annotations %||% list()
    }

    ellmer::tool(
      fun = build_shinychat_wrapper_fun(
        app = app,
        app_tool = app_tool,
        tool_nm = tool_nm,
        value_fn = value_fn,
        summary = summary,
        title = title %||% annotations$title,
        icon = icon %||% annotations$icon,
        open = open,
        show_request = show_request,
        full_screen = full_screen
      ),
      name = tool_nm,
      description = description,
      arguments = arguments,
      annotations = annotations
    )
  })

  if (length(wrapped) == 1) {
    wrapped[[1]]
  } else {
    names(wrapped) <- vapply(app_tools, tool_name, character(1))
    wrapped
  }
}
