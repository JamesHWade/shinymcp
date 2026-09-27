# The live Shiny runtime
#
# as_mcp_app() turns a Shiny app into an MCP App without rewriting it. The
# page the host shows is the app's own UI, rendered once to static HTML. The
# app's server function runs in R, headless: each view of the app gets its
# own session (a shiny::MockShinySession, the same object testServer() uses),
# with inputs set from the page or from the model, and outputs read back and
# sent to the page as HTML, text, and images.
#
# Two tools connect them:
#
# * The app tool (named after the app) is what the model calls. Its
#   arguments are the app's inputs. Each call opens a new view: a fresh
#   session with those inputs, whose outputs come back as the tool result.
# * The view tool (`<name>_view`, visible only to the app) is what the page
#   calls as the user works. It carries the view's id and the inputs that
#   changed, and returns the outputs that changed.
#
# Sessions live in this R process. If a view's session is gone (evicted, or
# the request reached another process), the page's full input state is
# enough to start a new one; only state the server function kept outside its
# inputs is lost.

#' @noRd
ShinyRuntime <- R6::R6Class(
  "ShinyRuntime",
  public = list(
    app_name = NULL,
    tool_name = NULL,
    view_tool_name = NULL,
    title = NULL,
    description = NULL,
    inputs = NULL,
    outputs = NULL,
    model_inputs = NULL,
    model_outputs = NULL,
    max_instances = NULL,
    idle_seconds = NULL,

    initialize = function(
      server,
      ui,
      app_name,
      tool_name = NULL,
      title = NULL,
      description = NULL,
      on_start = NULL,
      selective = NULL,
      ns = NULL,
      max_instances = 50L,
      idle_seconds = 3600
    ) {
      if (!is.function(server)) {
        shinymcp_abort(
          "{.arg server} must be a function (a Shiny server function or a function returning one).",
          class = "shinymcp_error_validation"
        )
      }
      private$server_source <- server
      private$on_start <- on_start
      private$ns_prefix <- ns
      self$app_name <- app_name
      self$tool_name <- tool_name %||% sanitize_name(app_name)
      self$view_tool_name <- paste0(self$tool_name, "_view")
      self$title <- title
      self$description <- description
      self$max_instances <- max_instances
      self$idle_seconds <- idle_seconds

      inputs <- describe_ui_inputs(ui)
      outputs <- describe_ui_outputs(ui)
      if (!is.null(ns)) {
        inputs <- strip_namespace(inputs, ns)
        outputs <- strip_namespace(outputs, ns)
      }
      self$inputs <- inputs
      self$outputs <- outputs

      if (is.null(selective)) {
        selective <- any(vapply(inputs, function(i) isTRUE(i$bound), logical(1))) ||
          any(vapply(outputs, function(o) isTRUE(o$bound), logical(1)))
      }
      private$selective <- selective
      self$model_inputs <- names(Filter(
        function(i) {
          if (selective) {
            isTRUE(i$bound) && !i$kind %in% c("password", "file")
          } else {
            i$kind %in% MODEL_INPUT_KINDS
          }
        },
        inputs
      ))
      self$model_outputs <- names(Filter(
        function(o) {
          (!selective || isTRUE(o$bound)) && !identical(o$type, "download")
        },
        outputs
      ))
      private$instances <- new.env(parent = emptyenv())
      invisible(self)
    },

    # The two tools the runtime adds to its app.
    tools = function() {
      properties <- lapply(self$model_inputs, function(id) input_json_schema(self$inputs[[id]]))
      names(properties) <- self$model_inputs
      open_schema <- list(
        type = "object",
        properties = if (length(properties)) properties else json_object()
      )
      runtime <- self
      list(
        new_mcp_tool(
          name = self$tool_name,
          title = self$title,
          description = self$description %||% default_runtime_description(self),
          input_schema = open_schema,
          outputs = self$model_outputs,
          annotations = list(readOnlyHint = FALSE, openWorldHint = FALSE),
          handler = function(arguments, context) runtime$open(arguments, context),
          source = "runtime"
        ),
        new_mcp_tool(
          name = self$view_tool_name,
          description = paste0(
            "Used by the ", self$title %||% self$app_name,
            " app to send input changes to its R session. Not for the model."
          ),
          input_schema = view_tool_schema(),
          visibility = "app",
          handler = function(arguments, context) runtime$view(arguments, context),
          source = "runtime"
        )
      )
    },

    bridge_config = function() {
      compact_list(list(
        viewTool = self$view_tool_name,
        entryTool = self$tool_name,
        ns = private$ns_prefix
      ))
    },

    # The model opened the app (or a host asked for a first render).
    open = function(arguments, context = list()) {
      arguments <- arguments %||% list()
      unknown <- setdiff(names(arguments), self$model_inputs)
      values <- list()
      pressed <- character()
      for (id in intersect(names(arguments), self$model_inputs)) {
        spec <- self$inputs[[id]]
        if (identical(spec$kind, "action")) {
          if (isTRUE(as.logical(arguments[[id]]))) {
            pressed <- c(pressed, id)
          }
          next
        }
        values[[id]] <- coerce_input_value(arguments[[id]], spec, strict = TRUE)
      }
      instance <- private$create_instance(values, context)
      if (length(pressed)) {
        presses <- lapply(pressed, function(id) action_value(1L))
        names(presses) <- pressed
        private$set_inputs(instance, presses)
      }
      with_request_context(context, private$settle(instance))
      private$result(instance, context, model = TRUE, all_outputs = TRUE, unknown = unknown)
    },

    # The page sent input changes, asked for a download, or closed.
    view = function(arguments, context = list()) {
      action <- arguments$action %||% "update"
      id <- arguments$instance
      instance <- if (is_string(id)) private$get_instance(id, context)
      restarted <- FALSE

      if (identical(action, "close")) {
        if (!is.null(instance)) {
          private$close_instance(instance)
        }
        return(wire_result(list(content = list(text_block("closed")))))
      }

      page_inputs <- arguments$inputs %||% list()
      kinds <- arguments$kinds %||% list()
      if (is.null(instance)) {
        # A new view, or one whose session is gone: rebuild it from the
        # page's full input state.
        values <- private$page_values(page_inputs, kinds, NULL)
        instance <- private$create_instance(values, context, id = if (is_string(id)) id)
        instance$page_sent <- private$dom_keys(values)
        restarted <- is_string(id)
        all_outputs <- TRUE
      } else {
        changed <- as.character(unlist(arguments$changed))
        if (length(changed) == 0) {
          changed <- names(page_inputs)
        }
        values <- private$page_values(page_inputs[intersect(changed, names(page_inputs))], kinds, instance)
        instance$page_sent <- private$dom_keys(values)
        private$set_inputs(instance, values, dedupe = TRUE)
        all_outputs <- isTRUE(arguments$all)
      }
      private$apply_sizes(instance, arguments$sizes, arguments$pixelRatio)

      if (identical(action, "download")) {
        return(private$download(instance, arguments$output, context))
      }
      with_request_context(context, private$settle(instance))
      private$result(
        instance,
        context,
        model = FALSE,
        all_outputs = all_outputs,
        restarted = restarted
      )
    },

    close_all = function() {
      for (id in ls(private$instances)) {
        private$close_instance(private$instances[[id]])
      }
      invisible(self)
    },

    instance_count = function() {
      length(ls(private$instances))
    }
  ),

  private = list(
    server_source = NULL,
    on_start = NULL,
    started = FALSE,
    ns_prefix = NULL,
    selective = FALSE,
    instances = NULL,

    ensure_started = function() {
      if (!private$started) {
        private$started <- TRUE
        if (is.function(private$on_start)) {
          private$on_start()
        }
      }
    },

    server_function = function() {
      src <- private$server_source
      # shiny.appobj$serverFuncSource() returns the server; a plain server
      # function takes input and output.
      if (length(formals(src)) == 0) src() else src
    },

    create_instance = function(values, context, id = NULL) {
      private$ensure_started()
      private$evict()
      rlang::check_installed("shiny", reason = "to run a Shiny app as an MCP App.")

      inst <- new.env(parent = emptyenv())
      inst$id <- id %||% unique_id("view")
      inst$user <- context$user
      inst$created <- as.numeric(Sys.time())
      inst$last_used <- inst$created
      inst$clock <- inst$created
      inst$digests <- character()
      inst$outputs <- character()
      inst$downloads <- list()
      inst$input_messages <- list()
      inst$notifications <- list()
      inst$modals <- list()
      inst$ui_changes <- list()
      inst$custom_messages <- list()
      inst$messages <- list()
      inst$model_context <- NULL
      inst$model_context_sent <- NULL
      inst$pixel_ratio <- 1

      session <- runtime_session_class()$new()
      inst$session <- session
      inst$client <- shiny::reactiveValues(pixelratio = 1)
      for (out in self$outputs) {
        size <- out$size %||% list()
        inst$client[[paste0("output_", out$dom_id %||% out$id, "_width")]] <- size$width %||% 640
        inst$client[[paste0("output_", out$dom_id %||% out$id, "_height")]] <- size$height %||% 400
      }
      session$clientData <- structure(list(), class = "shinymcp_clientdata", instance = inst)
      session$user <- context$user
      session$groups <- context$groups
      session$userData$.shinymcp <- inst
      install_session_hooks(session, inst)

      # Inputs first, as Shiny's client sends them before the server runs.
      defaults <- lapply(self$inputs, function(spec) spec$value)
      names(defaults) <- vapply(self$inputs, function(s) s$dom_id %||% s$id, character(1))
      defaults <- defaults[!vapply(defaults, is.null, logical(1))]
      initial <- utils::modifyList(defaults, private$dom_keys(values), keep.null = TRUE)
      initial <- initial[!vapply(initial, is.null, logical(1))]
      if (length(initial)) {
        with_mock_context(session, do.call(session$setInputs, initial))
      }

      server <- private$server_function()
      args <- list(input = session$input, output = session$output, session = session)
      accepted <- names(formals(server))
      if (!"..." %in% accepted) {
        args <- args[intersect(names(args), accepted)]
      }
      with_request_context(
        context,
        with_mock_context(session, do.call(server, args))
      )
      private$instances[[inst$id]] <- inst
      inst
    },

    get_instance = function(id, context) {
      inst <- private$instances[[id]]
      if (is.null(inst)) {
        return(NULL)
      }
      # A view belongs to the user who opened it.
      if (!is.null(inst$user) && !identical(inst$user, context$user)) {
        return(NULL)
      }
      inst$last_used <- as.numeric(Sys.time())
      inst
    },

    close_instance = function(inst) {
      if (exists(inst$id, envir = private$instances, inherits = FALSE)) {
        rm(list = inst$id, envir = private$instances)
      }
      if (!inst$session$isClosed()) {
        try(with_mock_context(inst$session, inst$session$close()), silent = TRUE)
      }
    },

    evict = function() {
      ids <- ls(private$instances)
      if (length(ids) == 0) {
        return()
      }
      now <- as.numeric(Sys.time())
      last <- vapply(ids, function(id) private$instances[[id]]$last_used, numeric(1))
      stale <- ids[now - last > self$idle_seconds]
      keep <- setdiff(ids, stale)
      if (length(keep) >= self$max_instances) {
        ordered <- keep[order(last[keep])]
        stale <- c(stale, ordered[seq_len(length(keep) - self$max_instances + 1)])
      }
      for (id in stale) {
        private$close_instance(private$instances[[id]])
      }
    },

    # Map model/view ids to the ids inside the session (modules add a
    # namespace prefix).
    dom_keys = function(values) {
      if (length(values) == 0) {
        return(list())
      }
      keys <- vapply(
        names(values),
        function(id) self$inputs[[id]]$dom_id %||% private$namespaced(id),
        character(1)
      )
      names(values) <- keys
      values
    },

    namespaced = function(id) {
      if (is.null(private$ns_prefix)) id else paste0(private$ns_prefix, "-", id)
    },

    # Values sent by the page, keyed by their DOM ids.
    page_values = function(page_inputs, kinds, instance) {
      out <- list()
      for (dom_id in names(page_inputs)) {
        if (startsWith(dom_id, ".") || !nzchar(dom_id)) {
          next
        }
        public_id <- private$public_id(dom_id)
        spec <- self$inputs[[public_id]] %||%
          list(id = dom_id, kind = kinds[[dom_id]]$kind %||% kinds[[dom_id]] %||% "unknown")
        if (is.list(kinds[[dom_id]]) && !is.null(kinds[[dom_id]]$dataType)) {
          spec$data_type <- kinds[[dom_id]]$dataType
        }
        previous <- if (!is.null(instance)) {
          shiny::isolate(instance$session$input[[dom_id]])
        }
        out[[public_id]] <- coerce_input_value(page_inputs[[dom_id]], spec, previous = previous)
      }
      out
    },

    public_id = function(dom_id) {
      prefix <- private$ns_prefix
      if (!is.null(prefix) && startsWith(dom_id, paste0(prefix, "-"))) {
        substr(dom_id, nchar(prefix) + 2, nchar(dom_id))
      } else {
        dom_id
      }
    },

    set_inputs = function(inst, values, dedupe = FALSE) {
      values <- private$dom_keys(values)
      if (dedupe && length(values)) {
        same <- vapply(
          names(values),
          function(id) {
            identical(shiny::isolate(inst$session$input[[id]]), values[[id]])
          },
          logical(1)
        )
        values <- values[!same]
      }
      if (length(values) == 0) {
        return(invisible())
      }
      with_mock_context(inst$session, do.call(inst$session$setInputs, values))
    },

    apply_sizes = function(inst, sizes, pixel_ratio) {
      if (is.numeric(pixel_ratio) && length(pixel_ratio) == 1) {
        ratio <- min(max(pixel_ratio, 1), 3)
        if (abs(ratio - inst$pixel_ratio) > 0.01) {
          inst$pixel_ratio <- ratio
          inst$client$pixelratio <- ratio
        }
      }
      for (id in names(sizes)) {
        size <- sizes[[id]]
        for (dim in c("width", "height")) {
          value <- size[[dim]]
          if (!is.numeric(value) || value <= 0) {
            next
          }
          key <- paste0("output_", id, "_", dim)
          current <- shiny::isolate(inst$client[[key]])
          # Ignore jitter: small changes aren't worth a redraw.
          if (is.null(current) || abs(current - value) > max(8, 0.05 * current)) {
            inst$client[[key]] <- round(value)
          }
        }
      }
    },

    # Flush reactives, run due timers, and apply input updates the server
    # sent (updateSelectInput() and friends) the way the browser would.
    settle = function(inst) {
      now <- as.numeric(Sys.time())
      elapsed <- min(max(0, (now - inst$clock) * 1000), 5000)
      inst$clock <- now
      with_mock_context(inst$session, {
        if (elapsed > 0) {
          inst$session$elapse(elapsed)
        } else {
          inst$session$flushReact()
        }
      })
      for (i in seq_len(5)) {
        echoed <- private$echo_input_messages(inst)
        if (length(echoed) == 0) {
          break
        }
        with_mock_context(inst$session, do.call(inst$session$setInputs, echoed))
      }
    },

    # Input values implied by messages the server sent since the last echo.
    echo_input_messages = function(inst) {
      pending <- inst$input_messages[seq_along(inst$input_messages) > (inst$echoed %||% 0)]
      inst$echoed <- length(inst$input_messages)
      values <- list()
      for (msg in pending) {
        value <- implied_input_value(msg, self$inputs[[private$public_id(msg$id)]], inst$session)
        if (!is.null(value)) {
          values[[msg$id]] <- value$value
        }
      }
      values
    },

    result = function(inst, context, model, all_outputs, restarted = FALSE, unknown = character()) {
      collected <- with_request_context(context, collect_runtime_outputs(inst, self$outputs))
      changed <- if (all_outputs) {
        names(collected)
      } else {
        names(collected)[vapply(
          names(collected),
          function(id) !identical(inst$digests[[id]] %||% "", collected[[id]]$digest),
          logical(1)
        )]
      }
      for (id in names(collected)) {
        inst$digests[[id]] <- collected[[id]]$digest
      }

      view <- compact_list(list(
        instance = inst$id,
        outputs = lapply(collected[changed], function(o) o$payload),
        inputs = page_input_updates(inst, model),
        inputMessages = drain(inst, "input_messages", reset_echo = TRUE),
        notifications = drain(inst, "notifications"),
        modals = drain(inst, "modals"),
        uiChanges = drain(inst, "ui_changes"),
        customMessages = drain(inst, "custom_messages"),
        messages = drain(inst, "messages"),
        modelContext = runtime_model_context(inst, self, collected, publish = !model),
        restarted = if (restarted) TRUE
      ))
      if (length(view$outputs) == 0) {
        view$outputs <- json_object()
      }

      content <- list(text_block(runtime_result_text(self, inst, collected, model, unknown)))
      if (model && private$images_enabled(context)) {
        for (id in self$model_outputs) {
          img <- collected[[id]]$image
          if (!is.null(img)) {
            content <- c(content, list(image_block(img)))
          }
        }
      }
      result <- list(content = content)
      if (model) {
        outputs <- lapply(self$model_outputs, function(id) json_safe(collected[[id]]$model))
        names(outputs) <- self$model_outputs
        outputs <- compact_list(outputs)
        result$structuredContent <- list(
          inputs = runtime_input_snapshot(self, inst),
          outputs = if (length(outputs)) outputs else json_object()
        )
      }
      result[["_meta"]] <- list(`shinymcp/view` = view)
      wire_result(result)
    },

    images_enabled = function(context) {
      !identical(context$caller, "app") && !isFALSE(context$images)
    },

    download = function(inst, output_id, context) {
      dom_id <- self$outputs[[output_id %||% ""]]$dom_id %||% private$namespaced(output_id %||% "")
      if (is.null(inst$downloads[[dom_id]])) {
        return(wire_result(list(
          content = list(text_block(paste0("No download named '", output_id, "'."))),
          isError = TRUE
        )))
      }
      path <- tryCatch(
        with_request_context(context, with_mock_context(inst$session, inst$session$getOutput(dom_id))),
        error = function(e) e
      )
      if (inherits(path, "error")) {
        return(wire_result(tool_error_result(path)))
      }
      max_bytes <- getOption("shinymcp.max_download_bytes", 25 * 1024^2)
      size <- file.info(path)$size
      if (is.na(size) || size > max_bytes) {
        return(wire_result(list(
          content = list(text_block(sprintf(
            "The download is %s, over the %s limit (option shinymcp.max_download_bytes).",
            format(structure(size, class = "object_size"), units = "auto"),
            format(structure(max_bytes, class = "object_size"), units = "auto")
          ))),
          isError = TRUE
        )))
      }
      filename <- basename(path)
      mime <- inst$downloads[[dom_id]]$content_type %||% mime_type_for(filename)
      wire_result(list(
        content = list(text_block(paste("Prepared", filename))),
        `_meta` = list(`shinymcp/view` = list(
          instance = inst$id,
          download = list(
            output = output_id,
            filename = filename,
            mimeType = mime,
            data = base64_file(path)
          )
        ))
      ))
    }
  )
)

#' @noRd
wire_result <- function(x) {
  structure(x, class = "shinymcp_wire_result")
}

#' @noRd
view_tool_schema <- function() {
  list(
    type = "object",
    properties = list(
      action = list(type = "string", enum = I(c("update", "download", "close"))),
      instance = list(type = "string"),
      inputs = list(type = "object"),
      changed = list(type = "array", items = list(type = "string")),
      kinds = list(type = "object"),
      sizes = list(type = "object"),
      pixelRatio = list(type = "number"),
      output = list(type = "string"),
      all = list(type = "boolean")
    )
  )
}

#' @noRd
default_runtime_description <- function(runtime) {
  title <- runtime$title %||% runtime$app_name
  inputs <- runtime$model_inputs
  outputs <- runtime$model_outputs
  paste0(
    "Show the interactive ", title, " app in the conversation. ",
    if (length(inputs)) {
      paste0(
        "Arguments set the app's inputs (",
        paste(inputs, collapse = ", "),
        "); omitted ones keep their defaults. "
      )
    } else {
      ""
    },
    if (length(outputs)) {
      paste0("The result reports what the app shows (", paste(outputs, collapse = ", "), "). ")
    } else {
      ""
    },
    "The user can keep adjusting the app after it opens."
  )
}

# ---- Session plumbing ----

#' Evaluate in a mock session's reactive domain
#' @noRd
with_mock_context <- function(session, expr) {
  old <- options(shiny.allowoutputreads = TRUE)
  on.exit(options(old), add = TRUE)
  shiny::isolate(shiny::withReactiveDomain(session, expr))
}

#' Record what the server sends to the browser
#'
#' MockShinySession drops messages meant for the client (input updates,
#' notifications, modals, inserted UI). The runtime relays them to the page.
#' @noRd
install_session_hooks <- function(session, inst) {
  push <- function(field, value) {
    inst[[field]] <- c(inst[[field]], list(value))
  }
  session$sendInputMessage <- function(inputId, message) {
    push("input_messages", list(id = inputId, message = message))
  }
  session$sendNotification <- function(type, message) {
    push("notifications", compact_list(list(
      type = type,
      message = runtime_html_message(message)
    )))
  }
  session$sendModal <- function(type, message) {
    push("modals", compact_list(list(type = type, message = runtime_html_message(message))))
  }
  session$sendInsertUI <- function(selector, multiple, where, content) {
    push("ui_changes", list(
      op = "insert",
      selector = selector,
      multiple = isTRUE(multiple),
      where = where,
      content = runtime_html_message(content)
    ))
  }
  session$sendRemoveUI <- function(selector, multiple) {
    push("ui_changes", list(op = "remove", selector = selector, multiple = isTRUE(multiple)))
  }
  session$sendCustomMessage <- function(type, message) {
    push("custom_messages", list(type = type, message = message))
  }
  session$sendChangeTabVisibility <- function(message) {
    push("ui_changes", list(op = "tab-visibility", message = message))
  }

  invisible(session)
}

#' The session class behind each view
#'
#' A shiny::MockShinySession that also records outputs and downloads for the
#' runtime, and gives module scopes the input-update namespacing a real
#' session has (MockShinySession's scopes send updateSelectInput() and
#' friends to the unprefixed id).
#'
#' MockShinySession is a non-portable R6 class, so a subclass's methods,
#' inherited ones included, look up variables from the subclass's parent
#' environment. That has to be shiny's namespace, and shiny is optional, so
#' the class is made the first time a view opens.
#' @noRd
runtime_session_class <- function() {
  if (is.null(the$runtime_session)) {
    the$runtime_session <- R6::R6Class(
      "ShinymcpRuntimeSession",
      inherit = shiny::MockShinySession,
      portable = FALSE,
      lock_objects = FALSE,
      parent_env = asNamespace("shiny"),
      public = list(
        makeScope = function(namespace) {
          scope <- super$makeScope(namespace)
          ns <- shiny::NS(namespace)
          root <- self
          overrides <- .subset2(scope, "overrides")
          overrides$sendInputMessage <- function(inputId, message) {
            root$sendInputMessage(ns(inputId), message)
          }
          assign("overrides", overrides, envir = scope)
          scope
        },
        defineOutput = function(name, func, label) {
          inst <- self$userData$.shinymcp
          if (!is.null(inst) && !name %in% inst$outputs) {
            inst$outputs <- c(inst$outputs, name)
          }
          super$defineOutput(name, func, label)
        },
        registerDownload = function(name, filename, contentType, content) {
          inst <- self$userData$.shinymcp
          if (!is.null(inst)) {
            inst$downloads[[name]] <- list(
              content_type = contentType,
              filename = if (is.function(filename)) filename else function() filename
            )
          }
          super$registerDownload(name, filename, contentType, content)
        }
      )
    )
  }
  the$runtime_session
}

#' Messages that carry HTML (and dependencies) for the page
#' @noRd
runtime_html_message <- function(message) {
  if (!is.list(message)) {
    return(message)
  }
  if (!is.null(message$html)) {
    message$html <- as.character(message$html)
  }
  if (length(message$deps)) {
    message$deps <- lapply(
      htmltools::resolveDependencies(message$deps),
      dependency_payload
    )
  }
  message
}

#' @noRd
drain <- function(inst, field, reset_echo = FALSE) {
  items <- inst[[field]]
  inst[[field]] <- list()
  if (reset_echo) {
    inst$echoed <- 0
  }
  if (length(items) == 0) NULL else items
}

#' Client data (sizes, pixel ratio) for a runtime session
#'
#' Reads go through reactive values, so a plot whose size changes on the
#' page redraws, as it does in a browser.
#' @export
#' @noRd
`$.shinymcp_clientdata` <- function(x, name) {
  inst <- attr(x, "instance")
  if (grepl("^output_.+_hidden$", name)) {
    return(FALSE)
  }
  value <- tryCatch(inst$client[[name]], error = function(e) shiny::isolate(inst$client[[name]]))
  if (!is.null(value)) {
    return(value)
  }
  if (grepl("^output_.+_(width|height)$", name)) {
    return(if (endsWith(name, "_width")) 640 else 400)
  }
  switch(
    name,
    pixelratio = 1,
    allowDataUriScheme = TRUE,
    url_protocol = "https:",
    url_hostname = "shinymcp",
    url_port = "",
    url_pathname = "/",
    url_search = "",
    url_hash = "",
    url_hash_initial = "",
    singletons = "",
    NULL
  )
}

#' @export
#' @noRd
`[[.shinymcp_clientdata` <- `$.shinymcp_clientdata`

# ---- Outputs ----

#' Describe the outputs in a Shiny UI
#' @noRd
describe_ui_outputs <- function(ui) {
  specs <- list()
  walk_tag_tree(ui, function(tag) {
    mcp_id <- htmltools::tagGetAttribute(tag, "data-shinymcp-output")
    role <- detect_mcp_role(tag)
    if (is.null(mcp_id) && (role$role != "output" || is.null(role$id))) {
      if (!has_class(tag, "shiny-download-link") || is.null(htmltools::tagGetAttribute(tag, "id"))) {
        return()
      }
      role <- list(role = "output", id = htmltools::tagGetAttribute(tag, "id"), type = "download")
    }
    dom_id <- htmltools::tagGetAttribute(tag, "id") %||% mcp_id
    id <- mcp_id %||% role$id
    if (is.null(id) || !is.null(specs[[id]])) {
      return()
    }
    type <- htmltools::tagGetAttribute(tag, "data-shinymcp-output-type") %||%
      role$type %||%
      "html"
    specs[[id]] <<- list(
      id = id,
      dom_id = dom_id %||% id,
      type = type,
      bound = !is.null(mcp_id),
      size = output_size_from_style(htmltools::tagGetAttribute(tag, "style"))
    )
  })
  specs
}

#' @noRd
has_class <- function(tag, cls) {
  cls %in% strsplit(htmltools::tagGetAttribute(tag, "class") %||% "", "\\s+")[[1]]
}

#' Pixel width and height from an output's inline style
#'
#' `plotOutput(height = "300px")` renders `style="width:100%;height:300px;"`.
#' Percentages and other units mean "whatever the page gives it", so only
#' pixel values are used; the page reports real sizes once it renders.
#' @noRd
output_size_from_style <- function(style) {
  if (is.null(style)) {
    return(NULL)
  }
  px <- function(prop) {
    m <- regmatches(style, regexec(paste0(prop, "\\s*:\\s*([0-9.]+)px"), style, perl = TRUE))[[1]]
    if (length(m) == 2) as.numeric(m[[2]]) else NULL
  }
  compact_list(list(width = px("(?<![a-z-])width"), height = px("(?<![a-z-])height")))
}

#' @noRd
strip_namespace <- function(specs, ns) {
  prefix <- paste0(ns, "-")
  out <- lapply(specs, function(s) {
    s$dom_id <- s$dom_id %||% s$id
    if (startsWith(s$id, prefix)) {
      s$id <- substr(s$id, nchar(prefix) + 1, nchar(s$id))
    }
    s
  })
  names(out) <- vapply(out, `[[`, character(1), "id")
  out
}

#' Read every output of a runtime session
#'
#' @return A named list (by public output id) of `payload` (for the page),
#'   `model` (for the model), `text`, `digest`, and `image`.
#' @noRd
collect_runtime_outputs <- function(inst, specs) {
  dom_to_public <- stats::setNames(
    vapply(specs, function(s) s$id, character(1)),
    vapply(specs, function(s) s$dom_id %||% s$id, character(1))
  )
  ids <- unique(c(names(dom_to_public), inst$outputs))
  out <- list()
  for (dom_id in ids) {
    if (!dom_id %in% inst$outputs) {
      next
    }
    public_id <- if (dom_id %in% names(dom_to_public)) dom_to_public[[dom_id]] else dom_id
    spec <- specs[[public_id]] %||% list(id = public_id, dom_id = dom_id, type = NULL)
    if (!is.null(inst$downloads[[dom_id]])) {
      filename <- tryCatch(
        with_mock_context(inst$session, as.character(inst$downloads[[dom_id]]$filename())),
        error = function(e) NULL
      )
      payload <- list(kind = "download", dom = dom_id, value = list(filename = filename))
      out[[public_id]] <- list(
        payload = payload,
        model = paste0("A file (", filename %||% "download", ") the user can download from the app."),
        text = NULL,
        digest = rlang::hash(payload)
      )
      next
    }
    value <- tryCatch(
      with_mock_context(inst$session, inst$session$getOutput(dom_id)),
      error = function(e) e
    )
    out[[public_id]] <- runtime_output_entry(value, spec, dom_id)
  }
  out
}

#' Turn a render function's value into a page payload and a model value
#' @noRd
runtime_output_entry <- function(value, spec, dom_id) {
  type <- spec$type
  entry <- if (inherits(value, "error")) {
    runtime_error_entry(value)
  } else if (is.null(value)) {
    list(payload = list(kind = "clear"), model = NULL, text = "")
  } else if (inherits(value, "json")) {
    # htmlwidgets: JSON with the widget's dependencies attached.
    deps <- attr(value, "deps")
    list(
      payload = compact_list(list(
        kind = "widget",
        value = as.character(value),
        deps = if (length(deps)) {
          lapply(htmltools::resolveDependencies(deps), dependency_payload)
        }
      )),
      model = "An interactive widget, shown in the app.",
      text = "An interactive widget, shown in the app."
    )
  } else if (is.list(value) && !is.null(value$src)) {
    alt <- value$alt
    if (is.null(alt) || identical(alt, "Plot object")) {
      alt <- sprintf(
        "A plot (%s x %s), shown in the app.",
        value$width %||% "?",
        value$height %||% "?"
      )
    }
    image <- if (startsWith(value$src, "data:image/")) {
      list(
        data = sub("^data:[^,]*,", "", value$src),
        mimeType = sub("^data:([^;,]+).*$", "\\1", value$src)
      )
    }
    list(
      payload = list(
        kind = "image",
        value = compact_list(list(
          src = value$src,
          width = value$width,
          height = value$height,
          alt = alt,
          style = value$style,
          class = value$class
        ))
      ),
      model = alt,
      text = alt,
      image = image
    )
  } else if (is.list(value) && !is.null(value$html)) {
    html <- as.character(value$html)
    deps <- value$deps
    text <- html_to_text(html)
    list(
      payload = compact_list(list(
        kind = "html",
        value = html,
        deps = if (length(deps)) {
          lapply(htmltools::resolveDependencies(deps), dependency_payload)
        }
      )),
      model = text,
      text = text
    )
  } else if (is.character(value)) {
    text_output <- identical(type, "text") ||
      identical(type, "verbatimText") ||
      (is.null(type) && !grepl("<[a-zA-Z][^>]*>", value[[1]]))
    text <- if (text_output) paste(value, collapse = "\n") else html_to_text(value)
    list(
      payload = list(
        kind = if (text_output) "text" else "html",
        value = paste(value, collapse = "\n")
      ),
      model = text,
      text = text
    )
  } else {
    text <- paste(utils::capture.output(print(value)), collapse = "\n")
    list(payload = list(kind = "text", value = text), model = text, text = text)
  }
  entry$payload$dom <- dom_id
  entry$digest <- rlang::hash(entry$payload)
  entry
}

#' @noRd
runtime_error_entry <- function(e) {
  message <- cli::ansi_strip(conditionMessage(e))
  if (inherits(e, "shiny.output.cancel")) {
    return(list(payload = list(kind = "keep"), model = NULL, text = ""))
  }
  if (inherits(e, "shiny.silent.error")) {
    # req() failing clears the output; validate() shows its message.
    if (!nzchar(message)) {
      return(list(payload = list(kind = "clear"), model = NULL, text = ""))
    }
    return(list(
      payload = list(kind = "error", value = message, validation = TRUE),
      model = message,
      text = message
    ))
  }
  if (isTRUE(getOption("shiny.sanitize.errors")) && !inherits(e, "shiny.custom.error")) {
    message <- "An error has occurred. Check your logs or contact the app author for clarification."
  }
  list(
    payload = list(kind = "error", value = message),
    model = paste("Error:", message),
    text = paste("Error:", message)
  )
}

#' Input values the page should show that differ from what it sent
#'
#' After the model opens the app, the page needs every exposed input set to
#' the value the session used; afterwards only values the server changed.
#' @noRd
page_input_updates <- function(inst, full) {
  values <- shiny::isolate(shiny::reactiveValuesToList(inst$session$input))
  if (!full && length(inst$last_inputs)) {
    changed <- vapply(
      names(values),
      function(id) !identical(values[[id]], inst$last_inputs[[id]]),
      logical(1)
    )
    sent <- values[changed]
  } else {
    sent <- values
  }
  inst$last_inputs <- values
  from_page <- inst$page_sent %||% list()
  inst$page_sent <- NULL
  echoed_back <- vapply(
    names(sent),
    function(id) id %in% names(from_page) && identical(sent[[id]], from_page[[id]]),
    logical(1)
  )
  sent <- sent[!echoed_back]
  sent <- sent[!startsWith(names(sent), ".")]
  sent <- lapply(sent, input_value_for_page)
  sent <- sent[!vapply(sent, is.null, logical(1))]
  if (length(sent) == 0) NULL else sent
}

#' @noRd
runtime_input_snapshot <- function(runtime, inst) {
  values <- lapply(runtime$model_inputs, function(id) {
    dom <- runtime$inputs[[id]]$dom_id %||% id
    input_value_for_page(shiny::isolate(inst$session$input[[dom]]))
  })
  names(values) <- runtime$model_inputs
  values <- values[!vapply(values, is.null, logical(1))]
  if (length(values)) values else json_object()
}

#' The value an input takes after the server updates it
#'
#' Mirrors what Shiny's input bindings do with `receiveMessage()`, so the
#' session sees the new value without a round trip to the page.
#' @return `list(value =)` or NULL when the value doesn't change.
#' @noRd
implied_input_value <- function(msg, spec, session) {
  message <- msg$message
  id <- msg$id
  current <- shiny::isolate(session$input[[id]])
  kind <- spec$kind %||% guess_kind_from_message(message, current)

  if (!is.null(message$value)) {
    value <- message$value
    if (is.list(value) && !is.null(value$start)) {
      value <- c(value$start, value$end)
    }
    new <- coerce_input_value(value, spec %||% list(id = id, kind = kind), previous = current)
    return(if (identical(new, current)) NULL else list(value = new))
  }
  if (!is.null(message$options) && kind %in% c("select", "radio")) {
    values <- option_values(message$options)
    selected <- attr(values, "selected")
    new <- if (length(selected)) {
      selected[[1]]
    } else if (!is.null(current) && current %in% values) {
      current
    } else if (identical(kind, "select") && length(values)) {
      values[[1]]
    }
    return(if (identical(new, current)) NULL else list(value = new))
  }
  if (!is.null(message$options) && kind %in% c("select-multiple", "checkbox-group")) {
    values <- option_values(message$options)
    selected <- attr(values, "selected")
    new <- if (length(selected)) selected else intersect(current, values)
    if (length(new) == 0) new <- NULL
    return(if (identical(new, current)) NULL else list(value = new))
  }
  NULL
}

#' @noRd
guess_kind_from_message <- function(message, current) {
  if (!is.null(message$options)) {
    return(if (length(current) > 1) "select-multiple" else "select")
  }
  if (is.logical(current)) "checkbox" else if (is.numeric(current)) "number" else "text"
}

#' Values (and selected values) in an HTML options fragment
#' @noRd
option_values <- function(html) {
  html <- paste(as.character(html), collapse = "")
  tags <- regmatches(html, gregexpr("<(option|input)\\b[^>]*>", html, ignore.case = TRUE))[[1]]
  values <- character()
  selected <- character()
  for (tag in tags) {
    if (grepl("^<input", tag, ignore.case = TRUE) && !grepl("type=[\"']?(radio|checkbox)", tag, ignore.case = TRUE)) {
      next
    }
    value <- sub(".*\\bvalue=\"([^\"]*)\".*", "\\1", tag)
    if (identical(value, tag)) {
      next
    }
    value <- unescape_html(value)
    values <- c(values, value)
    if (grepl("\\b(selected|checked)\\b", tag)) {
      selected <- c(selected, value)
    }
  }
  structure(values, selected = selected)
}

#' Text the model reads after opening or updating the app
#' @noRd
runtime_result_text <- function(runtime, inst, collected, model, unknown = character()) {
  title <- runtime$title %||% runtime$app_name
  limit <- getOption("shinymcp.max_text_chars", 4000)
  lines <- if (model) {
    paste0("The ", title, " app is open in the conversation.")
  } else {
    paste0(title, " updated.")
  }
  if (model) {
    snapshot <- runtime_input_snapshot(runtime, inst)
    if (length(snapshot)) {
      lines <- c(
        lines,
        paste0(
          "Inputs: ",
          paste(
            vapply(
              names(snapshot),
              function(id) paste0(id, " = ", format_snapshot_value(snapshot[[id]])),
              character(1)
            ),
            collapse = "; "
          ),
          "."
        )
      )
    }
    if (length(unknown)) {
      lines <- c(lines, paste0("Ignored unknown arguments: ", paste(unknown, collapse = ", "), "."))
    }
  }
  ids <- if (model) runtime$model_outputs else names(collected)
  for (id in ids) {
    text <- truncate_text(collected[[id]]$text %||% "", limit)
    if (!nzchar(text)) {
      next
    }
    lines <- c(
      lines,
      if (grepl("\n", text, fixed = TRUE)) paste0(id, ":\n", text) else paste0(id, ": ", text)
    )
  }
  paste(lines, collapse = "\n\n")
}

#' @noRd
format_snapshot_value <- function(x) {
  if (is.character(x) && length(x) == 1) {
    return(encodeString(x, quote = "\""))
  }
  if (is.logical(x)) {
    return(tolower(paste(x, collapse = ", ")))
  }
  paste(format(unlist(x)), collapse = ", ")
}

#' The model context a view publishes
#'
#' Set by the server function with [mcp_model_context()]; otherwise the
#' inputs the model can see and a short summary of the outputs.
#' @noRd
runtime_model_context <- function(inst, runtime, collected, publish = TRUE) {
  context <- inst$model_context
  if (is.null(context)) {
    snapshot <- runtime_input_snapshot(runtime, inst)
    summary <- lapply(runtime$model_outputs, function(id) {
      truncate_text(collected[[id]]$text %||% "", 300)
    })
    names(summary) <- runtime$model_outputs
    summary <- summary[nzchar(unlist(summary))]
    text <- paste0(
      "In the ", runtime$title %||% runtime$app_name, " app, the user has: ",
      if (length(snapshot)) {
        paste(
          vapply(names(snapshot), function(id) paste0(id, " = ", format_snapshot_value(snapshot[[id]])), character(1)),
          collapse = "; "
        )
      } else {
        "no inputs set"
      },
      "."
    )
    context <- list(
      text = text,
      data = list(app = runtime$app_name, view = inst$id, inputs = snapshot)
    )
  }
  payload <- compact_list(list(
    content = if (!is.null(context$text)) list(text_block(context$text)),
    structuredContent = context$data
  ))
  key <- rlang::hash(payload)
  if (identical(key, inst$model_context_sent)) {
    return(NULL)
  }
  inst$model_context_sent <- key
  # The model already has the result of the call that opened the view.
  if (publish) payload else NULL
}

# ---- Helpers for server functions ----

#' Talk to the model from a Shiny app served with shinymcp
#'
#' @description
#' In a Shiny app served as an MCP App with [as_mcp_app()], the server
#' function runs in shinymcp's live runtime. These helpers let it reach the
#' model and the chat. In a normal Shiny session they do nothing and return
#' `FALSE`, so the same app still runs with [shiny::runApp()].
#'
#' * `mcp_model_context()` sets what the model knows about this view of the
#'   app. Hosts give it to the model on its next turn. Each call replaces
#'   the last. Without it, shinymcp sends the input values and a short
#'   summary of each output. Keep it small and factual: identifiers and the
#'   numbers the user is looking at, not whole data sets.
#' * `mcp_send_message()` posts a message into the chat as the user, which
#'   usually prompts a reply from the model. Hosts may ask the user first.
#' * `is_mcp_session()` is `TRUE` when the server function is running in
#'   shinymcp's runtime.
#'
#' @param text Text for the model (or the chat message).
#' @param data A named list of structured data for the model.
#' @param session The Shiny session. The default works inside a server
#'   function and in modules.
#' @return `mcp_model_context()` and `mcp_send_message()` invisibly return
#'   `TRUE` when the message will be delivered, `FALSE` otherwise.
#'   `is_mcp_session()` returns a logical.
#' @family runtime helpers
#' @export
#' @examples
#' server <- function(input, output, session) {
#'   filtered <- shiny::reactive(mtcars[mtcars$cyl == input$cyl, ])
#'
#'   shiny::observe({
#'     mcp_model_context(
#'       text = paste("Showing", nrow(filtered()), "cars with", input$cyl, "cylinders."),
#'       data = list(cyl = input$cyl, n = nrow(filtered()))
#'     )
#'   })
#' }
mcp_model_context <- function(
  text = NULL,
  data = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  if (is.null(text) && is.null(data)) {
    shinymcp_abort("Supply {.arg text}, {.arg data}, or both.")
  }
  inst <- runtime_instance(session)
  if (is.null(inst)) {
    return(invisible(FALSE))
  }
  if (!is.null(text)) {
    text <- paste(as.character(text), collapse = "\n")
  }
  inst$model_context <- compact_list(list(text = text, data = data))
  invisible(TRUE)
}

#' @rdname mcp_model_context
#' @export
mcp_send_message <- function(text, session = shiny::getDefaultReactiveDomain()) {
  if (!is_string(text)) {
    shinymcp_abort("{.arg text} must be a single non-empty string.")
  }
  inst <- runtime_instance(session)
  if (is.null(inst)) {
    return(invisible(FALSE))
  }
  inst$messages <- c(inst$messages, list(text))
  invisible(TRUE)
}

#' @rdname mcp_model_context
#' @export
is_mcp_session <- function(session = shiny::getDefaultReactiveDomain()) {
  !is.null(runtime_instance(session))
}

#' @noRd
runtime_instance <- function(session) {
  if (is.null(session)) {
    return(NULL)
  }
  inst <- tryCatch(session$userData$.shinymcp, error = function(e) NULL)
  if (is.environment(inst)) inst else NULL
}
