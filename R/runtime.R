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
      lifecycle = NULL,
      selective = NULL,
      ns = NULL,
      max_instances = getOption("shinymcp.max_views", 50L),
      idle_seconds = getOption("shinymcp.view_timeout", 3600)
    ) {
      if (!is.function(server)) {
        shinymcp_abort(
          "{.arg server} must be a function (a Shiny server function or a function returning one).",
          class = "shinymcp_error_validation"
        )
      }
      check_live_runtime()
      private$server_source <- server
      private$lifecycle <- lifecycle %||% app_lifecycle()
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
        selective <- any(vapply(
          inputs,
          function(i) isTRUE(i$bound),
          logical(1)
        )) ||
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
      private$dep_cache <- new.env(parent = emptyenv())
      invisible(self)
    },

    # The two tools the runtime adds to its app.
    tools = function() {
      properties <- lapply(self$model_inputs, function(id) {
        input_json_schema(self$inputs[[id]])
      })
      names(properties) <- self$model_inputs
      if (!"view" %in% names(properties)) {
        properties$view <- list(
          type = "string",
          description = paste(
            "To change a view of the app that is already open, its id (the `view` field of that call's result).",
            "The user then sees the same session with your changes, and inputs you leave out keep their current values.",
            "Leave it out to open a new view."
          )
        )
      }
      open_schema <- list(
        type = "object",
        properties = properties
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
          handler = function(arguments, context) {
            runtime$open(arguments, context)
          },
          source = "runtime"
        ),
        new_mcp_tool(
          name = self$view_tool_name,
          description = paste0(
            "Used by the ",
            self$title %||% self$app_name,
            " app to send input changes to its R session. Not for the model."
          ),
          input_schema = view_tool_schema(),
          visibility = "app",
          handler = function(arguments, context) {
            runtime$view(arguments, context)
          },
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
      private$lifecycle$within(function() private$open_view(arguments, context))
    },

    # The page sent input changes, asked for a download, or closed.
    view = function(arguments, context = list()) {
      private$lifecycle$within(function() {
        private$update_view(arguments, context)
      })
    },

    close_all = function() {
      close <- function() {
        for (id in ls(private$instances)) {
          private$close_instance(private$instances[[id]])
        }
      }
      if (private$lifecycle$started()) {
        private$lifecycle$within(close)
      } else {
        close()
      }
      private$lifecycle$stop()
      invisible(self)
    },

    instance_count = function() {
      length(ls(private$instances))
    }
  ),

  private = list(
    server_source = NULL,
    lifecycle = NULL,
    ns_prefix = NULL,
    selective = FALSE,
    instances = NULL,
    dep_cache = NULL,
    uploads = character(),

    open_view = function(arguments, context) {
      arguments <- arguments %||% list()
      view_id <- if (!"view" %in% self$model_inputs) arguments$view
      if (!"view" %in% self$model_inputs) {
        arguments$view <- NULL
      }
      unknown <- setdiff(names(arguments), self$model_inputs)
      # The model can change a view that's open instead of opening another.
      instance <- if (is_string(view_id)) private$get_instance(view_id, context)
      continued <- !is.null(instance)
      values <- list()
      pressed <- character()
      for (id in intersect(names(arguments), self$model_inputs)) {
        spec <- private$instance_spec(instance, id)
        if (identical(spec$kind, "action")) {
          if (isTRUE(as.logical(arguments[[id]]))) {
            pressed <- c(pressed, id)
          }
          next
        }
        # `[<-` with list() keeps an input the model emptied, as NULL.
        values[id] <- list(coerce_input_value(
          arguments[[id]],
          spec,
          strict = TRUE
        ))
      }

      if (continued) {
        private$set_inputs(instance, values, dedupe = TRUE)
      } else {
        instance <- private$create_instance(values, context)
      }
      if (length(pressed)) {
        presses <- lapply(pressed, function(id) {
          dom_id <- self$inputs[[id]]$dom_id %||% private$namespaced(id)
          current <- if (continued) {
            shiny::isolate(instance$session$input[[dom_id]])
          }
          action_value(as.integer(current %||% 0L) + 1L)
        })
        names(presses) <- pressed
        private$set_inputs(instance, presses)
      }
      with_request_context(context, private$settle(instance))
      crashed <- private$crash_result(instance)
      if (!is.null(crashed)) {
        return(crashed)
      }
      private$result(
        instance,
        context,
        model = TRUE,
        all_outputs = TRUE,
        unknown = unknown,
        continued = continued,
        lost_view = if (is_string(view_id) && !continued) view_id
      )
    },

    update_view = function(arguments, context) {
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
      if (identical(action, "dependency")) {
        return(private$dependency_request(arguments$dependency))
      }
      if (identical(action, "data")) {
        # Data requests carry the page's inputs only when asked again after
        # the view's session was found gone: then it's rebuilt from them.
        rebuilt <- is.null(instance) && is.list(arguments$inputs)
        if (rebuilt) {
          instance <- private$rebuild_instance(arguments, context, id)
          private$apply_sizes(instance, arguments$sizes, arguments$pixelRatio)
          private$apply_host_context(instance, arguments$host)
          instance$uploads <- c(instance$uploads, private$uploads)
          private$uploads <- character()
          with_request_context(context, private$settle(instance))
          crashed <- private$crash_result(instance)
          if (!is.null(crashed)) {
            return(crashed)
          }
        }
        answer <- private$data_request(
          instance,
          arguments$output,
          arguments$body,
          context
        )
        if (rebuilt) {
          answer <- private$with_state(answer, instance, context)
        }
        return(answer)
      }

      page_inputs <- arguments$inputs %||% list()
      kinds <- arguments$kinds %||% list()
      rebuilt <- is.null(instance)
      if (rebuilt) {
        instance <- private$rebuild_instance(arguments, context, id)
        restarted <- is_string(id)
        all_outputs <- TRUE
      } else {
        # A page that missed updates (reloaded, or re-rendered from chat
        # history) shows an older state than the session: take all of its
        # inputs and send back every output.
        stale <- is.numeric(arguments$revision) &&
          !identical(as.integer(arguments$revision), instance$revision)
        changed <- as.character(unlist(arguments$changed))
        # A tick only runs the timers that are due.
        everything <- length(changed) == 0 && !isTRUE(arguments$tick)
        if (everything || stale || isTRUE(arguments$sync)) {
          changed <- names(page_inputs)
        }
        values <- private$page_values(
          page_inputs[intersect(changed, names(page_inputs))],
          kinds,
          instance
        )
        instance$page_sent <- private$dom_keys(values)
        private$set_inputs(
          instance,
          values,
          dedupe = TRUE,
          events = as.character(unlist(arguments$events))
        )
        all_outputs <- isTRUE(arguments$all) || stale
      }
      private$apply_sizes(instance, arguments$sizes, arguments$pixelRatio)
      private$apply_host_context(instance, arguments$host)

      # Uploads that came with the request belong to this view.
      instance$uploads <- c(instance$uploads, private$uploads)
      private$uploads <- character()

      # Settle first, even for a download: a new session registers its
      # download handlers when its server runs, and the file should reflect
      # the inputs sent with the request.
      with_request_context(context, private$settle(instance))
      crashed <- private$crash_result(instance)
      if (!is.null(crashed)) {
        return(crashed)
      }
      if (identical(action, "download")) {
        answer <- private$download(instance, arguments$output, context)
        if (rebuilt) {
          answer <- private$with_state(answer, instance, context)
        }
        return(answer)
      }
      private$result(
        instance,
        context,
        model = FALSE,
        all_outputs = all_outputs,
        restarted = restarted
      )
    },

    # A view rebuilt for a download or for data: the answer brings what an
    # update's would, since the new session may not show what the old one
    # did, even when there's nothing to download or no data to give. R
    # counts it as sent.
    with_state = function(answer, inst, context) {
      state <- private$result(
        inst,
        context,
        model = FALSE,
        all_outputs = TRUE,
        restarted = TRUE
      )
      view <- state[["_meta"]][["shinymcp/view"]]
      extra <- answer[["_meta"]][["shinymcp/view"]]
      for (key in setdiff(names(extra), names(view))) {
        view[[key]] <- extra[[key]]
      }
      answer[["_meta"]][["shinymcp/view"]] <- view
      answer
    },

    # A new view, or one whose session is gone, rebuilt from the page's
    # full input state. An id that's still in use belongs to someone
    # else's view, so the new one gets its own.
    rebuild_instance = function(arguments, context, id) {
      values <- private$page_values(
        arguments$inputs %||% list(),
        arguments$kinds %||% list(),
        NULL
      )
      # A new session starts its buttons at zero, so observers don't redo
      # earlier presses (a "Save" saving again); a press that came with
      # this request still counts.
      pressed <- as.character(unlist(arguments$changed))
      for (key in names(values)) {
        if (inherits(values[[key]], "shinyActionButtonValue")) {
          values[[key]] <- action_value(if (key %in% pressed) 1L else 0L)
        }
      }
      free <- is_string(id) &&
        !exists(id, envir = private$instances, inherits = FALSE)
      instance <- private$create_instance(values, context, id = if (free) id)
      instance$page_sent <- private$dom_keys(values)
      instance
    },

    server_function = function() {
      src <- private$server_source
      # shiny.appobj$serverFuncSource() returns the server; a plain server
      # function takes input and output.
      if (length(formals(src)) == 0) src() else src
    },

    create_instance = function(values, context, id = NULL) {
      private$evict()
      rlang::check_installed(
        "shiny",
        reason = "to run a Shiny app as an MCP App."
      )

      inst <- new.env(parent = emptyenv())
      inst$id <- id %||% unique_id("view")
      inst$user <- context$user
      inst$created <- as.numeric(Sys.time())
      inst$last_used <- inst$created
      inst$clock <- inst$created
      inst$digests <- character()
      inst$outputs <- character()
      inst$downloads <- list()
      inst$data_objects <- list()
      inst$bounds <- list()
      inst$input_messages <- list()
      inst$notifications <- list()
      inst$modals <- list()
      inst$ui_changes <- list()
      inst$custom_messages <- list()
      inst$messages <- list()
      inst$model_context <- NULL
      inst$model_context_sent <- NULL
      inst$pixel_ratio <- 1
      inst$host <- shiny::reactiveVal(list())

      session <- runtime_session_class()$new()
      inst$session <- session
      inst$client <- shiny::reactiveValues(pixelratio = 1)
      for (out in self$outputs) {
        size <- out$size %||% list()
        inst$client[[paste0(
          "output_",
          out$dom_id %||% out$id,
          "_width"
        )]] <- size$width %||% 640
        inst$client[[paste0(
          "output_",
          out$dom_id %||% out$id,
          "_height"
        )]] <- size$height %||% 400
      }
      session$clientData <- structure(
        list(),
        class = "shinymcp_clientdata",
        instance = inst
      )
      session$user <- context$user
      session$groups <- context$groups
      session$userData$.shinymcp <- inst
      install_session_hooks(session, inst)
      # An error in an observer ends a Shiny session; keep it to report.
      if (is.function(session$onUnhandledError)) {
        session$onUnhandledError(function(e) inst$crash <- e)
      }

      # Inputs first, as Shiny's client sends them before the server runs.
      defaults <- lapply(
        self$inputs,
        function(spec) as_session_value(spec$value, spec)
      )
      names(defaults) <- vapply(
        self$inputs,
        function(s) s$dom_id %||% s$id,
        character(1)
      )
      defaults <- defaults[!vapply(defaults, is.null, logical(1))]
      # Given values replace defaults whole: modifyList() would merge lists
      # (varSelectInput()'s symbols, a plot click) into them instead.
      initial <- defaults
      given <- private$dom_keys(values)
      initial[names(given)] <- given
      initial <- initial[!vapply(initial, is.null, logical(1))]
      if (length(initial)) {
        with_mock_context(
          session,
          do.call(session$setInputs, initial, quote = TRUE)
        )
      }

      server <- private$server_function()
      args <- list(
        input = session$input,
        output = session$output,
        session = session
      )
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
      if (length(inst$uploads)) {
        unlink(inst$uploads, recursive = TRUE)
      }
      if (!inst$session$isClosed()) {
        try(
          with_mock_context(inst$session, inst$session$close()),
          silent = TRUE
        )
      }
    },

    evict = function() {
      ids <- ls(private$instances)
      if (length(ids) == 0) {
        return()
      }
      now <- as.numeric(Sys.time())
      last <- vapply(
        ids,
        function(id) private$instances[[id]]$last_used,
        numeric(1)
      )
      stale <- ids[now - last > self$idle_seconds]
      keep <- setdiff(ids, stale)
      if (length(keep) >= self$max_instances) {
        ordered <- keep[order(last[keep])]
        stale <- c(
          stale,
          ordered[seq_len(length(keep) - self$max_instances + 1)]
        )
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
        if (!nzchar(dom_id)) {
          next
        }
        public_id <- private$public_id(dom_id)
        # The page describes each input as an object; a bare kind string
        # is accepted too.
        described <- kinds[[dom_id]]
        if (is_string(described)) {
          described <- list(kind = described)
        }
        if (!is.list(described)) {
          described <- list()
        }
        spec <- private$instance_spec(instance, public_id) %||%
          list(id = dom_id, kind = described$kind %||% "unknown")
        if (!is.null(described$dataType)) {
          spec$data_type <- described$dataType
        }
        previous <- if (!is.null(instance)) {
          shiny::isolate(instance$session$input[[dom_id]])
        }
        value <- page_inputs[[dom_id]]
        if (identical(spec$kind, "file") || identical(described$kind, "file")) {
          upload <- read_upload(value)
          if (!is.null(upload)) {
            private$uploads <- c(private$uploads, attr(upload, "dir"))
            attr(upload, "dir") <- NULL
          }
          out[public_id] <- list(upload)
          next
        }
        # Inputs from packages' own bindings, and values set from
        # JavaScript, may name an input handler, as they would in Shiny.
        if (is_string(described$type)) {
          value <- apply_input_handler(
            value,
            described$type,
            dom_id,
            if (!is.null(instance)) instance$session
          )
          out[public_id] <- list(value)
          next
        }
        # An input the page emptied (no boxes checked, no rows selected)
        # is NULL, and `[<-` with list() keeps it.
        out[public_id] <- list(
          coerce_input_value(value, spec, previous = previous)
        )
      }
      out
    },

    # An input's spec as a view's session has it: the server can move a
    # slider's bounds and replace a select's choices.
    instance_spec = function(inst, public_id) {
      spec <- self$inputs[[public_id]]
      changed <- if (!is.null(inst)) inst$bounds[[public_id]]
      if (is.null(spec) || length(changed) == 0) {
        return(spec)
      }
      utils::modifyList(spec, changed)
    },

    note_bounds = function(inst, public_id, message) {
      spec <- self$inputs[[public_id]]
      if (is.null(spec) || !is.list(message)) {
        return(invisible())
      }
      changed <- inst$bounds[[public_id]] %||% list()
      # updateSelectInput() and friends replace the choices.
      if (
        !is.null(message[["options"]]) &&
          spec$kind %in%
            c("select", "select-multiple", "radio", "checkbox-group")
      ) {
        changed$choices <- as.character(option_values(message[["options"]]))
        inst$bounds[[public_id]] <- changed
        return(invisible())
      }
      if (!spec$kind %in% c("slider", "slider-range")) {
        return(invisible())
      }
      for (key in intersect(c("min", "max"), names(message))) {
        n <- suppressWarnings(as.numeric(message[[key]]))
        if (length(n) == 1 && !is.na(n)) {
          changed[[key]] <- slider_value_from_number(
            n,
            spec$data_type %||% "number"
          )
        }
      }
      inst$bounds[[public_id]] <- changed
      invisible()
    },

    public_id = function(dom_id) {
      prefix <- private$ns_prefix
      if (!is.null(prefix) && startsWith(dom_id, paste0(prefix, "-"))) {
        substr(dom_id, nchar(prefix) + 2, nchar(dom_id))
      } else {
        dom_id
      }
    },

    set_inputs = function(inst, values, dedupe = FALSE, events = character()) {
      values <- private$dom_keys(values)
      if (dedupe && length(values)) {
        # An event (a click, say) counts even when it repeats the value.
        # Both are keyed by the ids on the page.
        same <- vapply(
          names(values),
          function(id) {
            !id %in% events &&
              identical(shiny::isolate(inst$session$input[[id]]), values[[id]])
          },
          logical(1)
        )
        values <- values[!same]
      }
      if (length(values) == 0) {
        return(invisible())
      }
      with_mock_context(
        inst$session,
        do.call(inst$session$setInputs, values, quote = TRUE)
      )
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
          if (
            is.null(current) || abs(current - value) > max(8, 0.05 * current)
          ) {
            inst$client[[key]] <- round(value)
          }
        }
      }
    },

    # The host's theme, display mode, and locale, as the page reports them.
    apply_host_context = function(inst, host) {
      if (!is.list(host) || length(host) == 0) {
        return(invisible())
      }
      allowed <- c("theme", "displayMode", "locale", "timeZone", "platform")
      value <- host[intersect(names(host), allowed)]
      value <- Filter(is_string, value)
      names(value) <- c(
        theme = "theme",
        displayMode = "display_mode",
        locale = "locale",
        timeZone = "time_zone",
        platform = "platform"
      )[names(value)]
      value <- value[order(names(value))]
      if (!identical(shiny::isolate(inst$host()), value)) {
        inst$host(value)
      }
      invisible()
    },

    # Flush reactives, run due timers, and apply input updates the server
    # sent (updateSelectInput() and friends) the way the browser would.
    # An unhandled error (in an observer, say) ends a Shiny session. The
    # view goes with it: the caller hears why, and the page's next change
    # starts a new session.
    crash_result = function(inst) {
      if (!inst$session$isClosed()) {
        return(NULL)
      }
      private$close_instance(inst)
      title <- self$title %||% self$app_name
      detail <- if (is.null(inst$crash)) {
        "its session ended"
      } else {
        paste0(
          "an error in its server function: ",
          session_error_message(inst$crash)
        )
      }
      wire_result(list(
        content = list(text_block(paste0(
          "The ",
          title,
          " app stopped after ",
          detail,
          if (!grepl("[.!?]$", detail)) "."
        ))),
        isError = TRUE
      ))
    },

    settle = function(inst) {
      # Callbacks that are due, such as a finished task's (ExtendedTask,
      # promises), run first, so the flush below sees their results.
      run_due_callbacks()
      now <- as.numeric(Sys.time())
      elapsed <- max(0, (now - inst$clock) * 1000)
      inst$clock <- now
      # Run the next timer that's due, not every one missed since the last
      # call: a clock that ticks each second shouldn't redraw sixty times
      # after a minute's pause.
      due <- inst$session$nextTimer()
      if (is.finite(due)) {
        elapsed <- min(elapsed, max(due, 0))
      }
      with_mock_context(inst$session, {
        if (elapsed > 0 || (is.finite(due) && due <= 0)) {
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
        with_mock_context(
          inst$session,
          do.call(inst$session$setInputs, echoed, quote = TRUE)
        )
      }
    },

    # Input values implied by messages the server sent since the last echo.
    echo_input_messages = function(inst) {
      pending <- inst$input_messages[
        seq_along(inst$input_messages) > (inst$echoed %||% 0)
      ]
      inst$echoed <- length(inst$input_messages)
      values <- list()
      for (msg in pending) {
        public_id <- private$public_id(msg$id)
        private$note_bounds(inst, public_id, msg$message)
        value <- implied_input_value(
          msg,
          private$instance_spec(inst, public_id),
          inst$session
        )
        if (!is.null(value)) {
          # `[<-` with list() keeps an input the update cleared, as NULL.
          values[msg$id] <- list(value$value)
        }
      }
      values
    },

    result = function(
      inst,
      context,
      model,
      all_outputs,
      restarted = FALSE,
      unknown = character(),
      continued = FALSE,
      lost_view = NULL
    ) {
      collected <- with_request_context(
        context,
        collect_runtime_outputs(
          inst,
          self$outputs,
          skip_deps = context$skip_deps %||% character()
        )
      )
      changed <- if (all_outputs) {
        names(collected)
      } else {
        names(collected)[vapply(
          names(collected),
          function(id) {
            !identical(inst$digests[[id]] %||% "", collected[[id]]$digest)
          },
          logical(1)
        )]
      }
      for (id in names(collected)) {
        inst$digests[[id]] <- collected[[id]]$digest
      }
      inst$in_progress <- any(vapply(
        collected,
        function(o) isTRUE(o$progress),
        logical(1)
      ))

      inst$revision <- (inst$revision %||% 0L) + 1L
      payloads <- lapply(collected[changed], function(o) o$payload)
      if (model) {
        payloads <- lapply(payloads, private$refer_large_deps)
      }
      view <- compact_list(list(
        instance = inst$id,
        revision = inst$revision,
        outputs = payloads,
        inputs = page_input_updates(inst, model),
        inputMessages = drain(inst, "input_messages", reset_echo = TRUE),
        notifications = drain(inst, "notifications"),
        modals = drain(inst, "modals"),
        uiChanges = drain(inst, "ui_changes"),
        customMessages = drain(inst, "custom_messages"),
        messages = drain(inst, "messages"),
        modelContext = runtime_model_context(
          inst,
          self,
          collected,
          publish = !model
        ),
        # When the page should check back: a timer (invalidateLater(),
        # reactivePoll()) is due then.
        nextTick = next_tick(inst),
        restarted = if (restarted) TRUE
      ))
      if (length(view$outputs) == 0) {
        view$outputs <- json_object()
      }

      content <- list(text_block(runtime_result_text(
        self,
        inst,
        collected,
        model,
        unknown = unknown,
        continued = continued,
        lost_view = lost_view
      )))
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
        outputs <- lapply(self$model_outputs, function(id) {
          json_safe(collected[[id]]$model)
        })
        names(outputs) <- self$model_outputs
        outputs <- compact_list(outputs)
        result$structuredContent <- list(
          view = inst$id,
          inputs = runtime_input_snapshot(self, inst),
          outputs = if (length(outputs)) outputs else json_object()
        )
      }
      result[["_meta"]] <- list(`shinymcp/view` = view)
      wire_result(result)
    },

    # The model's call result stays in the conversation, so large libraries
    # (plotly's is 3.5 MB) go in it by name. The page fetches them through
    # the view tool, whose calls the conversation doesn't keep.
    refer_large_deps = function(payload) {
      limit <- getOption("shinymcp.max_inline_dependency_bytes", 256 * 1024)
      if (length(payload$deps) == 0) {
        return(payload)
      }
      payload$deps <- lapply(payload$deps, function(dep) {
        if (nchar(dep$head %||% "", type = "bytes") <= limit) {
          return(dep)
        }
        private$dep_cache[[paste0(dep$name, "@", dep$version)]] <- dep
        list(name = dep$name, version = dep$version, fetch = TRUE)
      })
      payload
    },

    dependency_request = function(key) {
      dep <- if (is_string(key)) private$dep_cache[[key]]
      if (is.null(dep)) {
        return(wire_result(list(
          content = list(text_block(paste0(
            "No dependency '",
            key %||% "",
            "' here."
          ))),
          isError = TRUE
        )))
      }
      wire_result(list(
        content = list(text_block(paste0(dep$name, " ", dep$version))),
        `_meta` = list(`shinymcp/view` = list(dependency = dep))
      ))
    },

    # A request from a widget for data kept in R, such as the rows of a
    # server-side DT table (DT::renderDT(server = TRUE)). The page's request
    # body is handed to the filter function the widget registered, as Shiny
    # would hand it an HTTP request.
    data_request = function(inst, name, body, context) {
      if (is.null(inst)) {
        # The page asks again with its inputs, and the view is rebuilt.
        return(wire_result(list(
          content = list(text_block("This view's session is gone.")),
          isError = TRUE,
          `_meta` = list(`shinymcp/view` = list(gone = TRUE))
        )))
      }
      obj <- inst$data_objects[[name %||% ""]]
      if (is.null(obj)) {
        return(wire_result(list(
          content = list(text_block(paste0(
            "No data named '",
            name %||% "",
            "' in this view."
          ))),
          isError = TRUE
        )))
      }
      raw_body <- charToRaw(enc2utf8(if (is_string(body)) body else ""))
      req <- new.env(parent = emptyenv())
      req$REQUEST_METHOD <- "POST"
      req$PATH_INFO <- paste0("/dataobj/", name)
      # DT reads its parameters from the body; selectize's server-side
      # choices from the query string.
      req$QUERY_STRING <- if (is_string(body)) body else ""
      req$HTTP_CONTENT_TYPE <- "application/x-www-form-urlencoded; charset=UTF-8"
      req$rook.input <- list(
        read = function(...) raw_body,
        rewind = function() invisible(NULL)
      )
      response <- tryCatch(
        with_request_context(
          context,
          with_mock_context(inst$session, obj$filter(obj$data, req))
        ),
        error = function(e) e
      )
      if (inherits(response, "error")) {
        return(wire_result(tool_error_result(response)))
      }
      content <- response$content
      text <- if (is.raw(content)) {
        rawToChar(content)
      } else {
        paste(content, collapse = "\n")
      }
      Encoding(text) <- "UTF-8"
      wire_result(list(
        content = list(text_block(paste0("Data for ", name, "."))),
        `_meta` = list(`shinymcp/view` = list(instance = inst$id, data = text))
      ))
    },

    images_enabled = function(context) {
      !identical(context$caller, "app") && !isFALSE(context$images)
    },

    download = function(inst, output_id, context) {
      dom_id <- self$outputs[[output_id %||% ""]]$dom_id %||%
        private$namespaced(output_id %||% "")
      if (is.null(inst$downloads[[dom_id]])) {
        return(wire_result(list(
          content = list(text_block(paste0(
            "No download named '",
            output_id,
            "'."
          ))),
          isError = TRUE
        )))
      }
      path <- tryCatch(
        with_request_context(
          context,
          with_mock_context(inst$session, mock_output(inst$session, dom_id))
        ),
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
        `_meta` = list(
          `shinymcp/view` = list(
            instance = inst$id,
            download = list(
              output = output_id,
              filename = filename,
              mimeType = mime,
              data = base64_file(path)
            )
          )
        )
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
      action = list(
        type = "string",
        enum = I(c("update", "download", "data", "dependency", "close"))
      ),
      instance = list(type = "string"),
      inputs = list(type = "object"),
      changed = list(type = "array", items = list(type = "string")),
      events = list(type = "array", items = list(type = "string")),
      kinds = list(type = "object"),
      sizes = list(type = "object"),
      pixelRatio = list(type = "number"),
      revision = list(type = "integer"),
      host = list(type = "object"),
      output = list(type = "string"),
      body = list(type = "string"),
      all = list(type = "boolean"),
      sync = list(type = "boolean"),
      tick = list(type = "boolean"),
      dependency = list(type = "string")
    )
  )
}

#' @noRd
default_runtime_description <- function(runtime) {
  title <- runtime$title %||% runtime$app_name
  inputs <- runtime$model_inputs
  outputs <- runtime$model_outputs
  paste0(
    "Show the interactive ",
    title,
    " app in the conversation. ",
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
      paste0(
        "The result reports what the app shows (",
        paste(outputs, collapse = ", "),
        "). "
      )
    } else {
      ""
    },
    "The user can keep adjusting the app after it opens."
  )
}

#' Files the page uploaded, as Shiny gives them to the server
#'
#' The page sends each file's name, size, type and base64 contents; the
#' server function gets `input$<id>` as Shiny's data frame of `name`,
#' `size`, `type` and `datapath`.
#' @noRd
read_upload <- function(value) {
  files <- if (is.list(value) && !is.null(value$name)) list(value) else value
  if (!is.list(files) || length(files) == 0) {
    return(NULL)
  }
  limit <- getOption("shiny.maxRequestSize", 5 * 1024^2)
  dir <- tempfile("shinymcp-upload-")
  dir.create(dir, recursive = TRUE)
  # Until the files are handed over, a failure removes them.
  kept <- FALSE
  on.exit(if (!kept) unlink(dir, recursive = TRUE), add = TRUE)
  rows <- lapply(seq_along(files), function(i) {
    f <- files[[i]]
    if (!is.list(f)) {
      shinymcp_abort(
        "Each uploaded file must be an object with its {.field name} and {.field data}.",
        class = "shinymcp_error_arguments"
      )
    }
    bytes <- jsonlite::base64_dec(f$data %||% "")
    ext <- tools::file_ext(f$name %||% "")
    path <- file.path(dir, paste0(i - 1, if (nzchar(ext)) paste0(".", ext)))
    writeBin(bytes, path)
    data.frame(
      name = as.character(f$name %||% basename(path)),
      size = length(bytes),
      type = as.character(f$type %||% ""),
      datapath = path,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  if (sum(out$size) > limit) {
    shinymcp_abort(
      "Uploads are limited to {round(limit / 1024^2, 1)} MB (the {.code shiny.maxRequestSize} option).",
      class = "shinymcp_error_arguments"
    )
  }
  attr(out, "dir") <- dir
  kept <- TRUE
  out
}

#' Milliseconds until a view's next timer, for the page to check back
#' @noRd
next_tick <- function(inst) {
  due <- tryCatch(inst$session$nextTimer(), error = function(e) Inf)
  # An output waits on a task (ExtendedTask) that finishes in the
  # background: look again soon.
  if (isTRUE(inst$in_progress)) {
    due <- min(due, 500)
  }
  if (!is.finite(due) || due > 3600 * 1000) {
    return(NULL)
  }
  max(0, round(due))
}

#' Apply the input handler Shiny has registered for a type
#'
#' Packages register handlers with shiny::registerInputHandler() for the
#' values their own inputs send (shinyWidgets' "air.date", for one). Shiny
#' applies them as values arrive; so does the runtime.
#' @noRd
apply_input_handler <- function(value, type, name, session = NULL) {
  handler <- tryCatch(
    utils::getFromNamespace("inputHandlers", "shiny")$get(type),
    error = function(e) NULL
  )
  if (!is.function(handler)) {
    return(simplify_json_value(value))
  }
  tryCatch(
    handler(value, session, name),
    error = function(e) {
      cli::cli_warn(
        "The {.val {type}} input handler failed for {.field {name}}: {conditionMessage(e)}"
      )
      simplify_json_value(value)
    }
  )
}

# ---- App lifecycle ----

#' A Shiny app's start and stop hooks, and the directory it runs in
#'
#' shinyAppDir() apps change into their directory and source global.R when
#' they start. The runtime starts them the same way, once, but changes back
#' after each call, because other code shares the process.
#' @noRd
app_lifecycle <- function(on_start = NULL, on_stop = NULL) {
  state <- new.env(parent = emptyenv())
  state$started <- FALSE
  state$dir <- NULL

  start <- function() {
    if (state$started) {
      return(invisible())
    }
    state$started <- TRUE
    if (is.function(on_start)) {
      old <- getwd()
      on.exit(setwd(old), add = TRUE)
      on_start()
      if (!identical(normalizePath(getwd()), normalizePath(old))) {
        state$dir <- getwd()
      }
    }
    invisible()
  }

  within <- function(fn) {
    start()
    if (is.null(state$dir)) {
      return(fn())
    }
    old <- setwd(state$dir)
    on.exit(setwd(old), add = TRUE)
    fn()
  }

  stop <- function() {
    if (!state$started) {
      return(invisible())
    }
    dir <- state$dir
    state$started <- FALSE
    state$dir <- NULL
    if (is.function(on_stop)) {
      # Like the rest of the app's code, the hook runs in its directory.
      old <- getwd()
      on.exit(setwd(old), add = TRUE)
      if (!is.null(dir)) {
        setwd(dir)
      }
      on_stop()
    }
    invisible()
  }

  list(
    start = start,
    within = within,
    stop = stop,
    started = function() state$started,
    dir = function() state$dir
  )
}

# ---- Session plumbing ----

#' Check for what the live runtime needs
#'
#' Shiny, and later to run the event loop's callbacks and read outputs.
#' @noRd
check_live_runtime <- function() {
  rlang::check_installed(
    c("shiny", "later"),
    version = c(NA, "1.4.0"),
    reason = "to run a Shiny app as an MCP App."
  )
}

#' An output's value from a mock session
#'
#' MockShinySession$getOutput() resolves the output's promise by running the
#' event loop until it's empty, which never happens while anything else in
#' the process keeps a callback scheduled (a Shiny app's timers, a pending
#' request): the call would never return. Instead, the callbacks that are
#' due now run (a rendered output's promise resolves through them), and the
#' output is read on a loop of its own. One still waiting on async work
#' reads as NULL for now.
#' @noRd
mock_output <- function(session, dom_id) {
  run_due_callbacks()
  later::with_temp_loop(session$getOutput(dom_id))
}

#' Run the event loop's callbacks that are due, without waiting for others
#' @noRd
run_due_callbacks <- function(max_rounds = 100) {
  for (i in seq_len(max_rounds)) {
    if (later::loop_empty() || later::next_op_secs() > 0) {
      break
    }
    later::run_now(0)
  }
  invisible()
}

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
    push(
      "notifications",
      compact_list(list(
        type = type,
        message = runtime_html_message(message)
      ))
    )
  }
  session$sendModal <- function(type, message) {
    push(
      "modals",
      compact_list(list(type = type, message = runtime_html_message(message)))
    )
  }
  session$sendInsertUI <- function(selector, multiple, where, content) {
    push(
      "ui_changes",
      list(
        op = "insert",
        selector = selector,
        multiple = isTRUE(multiple),
        where = where,
        content = runtime_html_message(content)
      )
    )
  }
  session$sendRemoveUI <- function(selector, multiple) {
    push(
      "ui_changes",
      list(op = "remove", selector = selector, multiple = isTRUE(multiple))
    )
  }
  session$sendCustomMessage <- function(type, message) {
    push("custom_messages", list(type = type, message = message))
  }
  session$sendChangeTabVisibility <- function(inputId, target, type) {
    push(
      "ui_changes",
      list(op = "tab-visibility", id = inputId, target = target, type = type)
    )
  }
  session$sendInsertTab <- function(
    inputId,
    liTag,
    divTag,
    menuName,
    target,
    position,
    select
  ) {
    push(
      "ui_changes",
      compact_list(list(
        op = "insert-tab",
        id = inputId,
        li = runtime_html_message(liTag),
        div = runtime_html_message(divTag),
        menu = menuName,
        target = target,
        position = position,
        select = isTRUE(select)
      ))
    )
  }
  session$sendRemoveTab <- function(inputId, target) {
    push("ui_changes", list(op = "remove-tab", id = inputId, target = target))
  }
  # Widgets that keep data in R (DT's server-side tables) register it here
  # and fetch it from the returned URL; the page routes that URL to the view
  # tool.
  # The URL has Shiny's own form, which widgets such as DT look for before
  # they set up their requests.
  session$registerDataObj <- function(name, data, filterFunc) {
    inst$data_objects[[name]] <- list(data = data, filter = filterFunc)
    paste0(
      "session/",
      gsub("[^a-z0-9]", "", tolower(inst$id)),
      "/dataobj/",
      utils::URLencode(name, reserved = TRUE),
      "?w=&nonce=",
      gsub("[^a-z0-9]", "", unique_id("n"))
    )
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
        # A real session's root namespace is empty; the mock's prefixes
        # "mock-session-", which hideTab() and friends would send the page.
        ns = function(id) {
          shiny::NS(NULL, id)
        },
        # Milliseconds until the next invalidateLater() or reactivePoll()
        # check is due, or Inf.
        nextTimer = function() {
          private$timer$timeToNextEvent()
        },
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
          # A real session takes a function without arguments as an output
          # too (`output$ready <- reactive(...)`); the mock calls every
          # output with the session and the name.
          if (is.function(func) && length(formals(func)) == 0) {
            value <- func
            func <- function(...) value()
          }
          super$defineOutput(name, func, label)
        },
        registerDownload = function(name, filename, contentType, content) {
          inst <- self$userData$.shinymcp
          if (!is.null(inst)) {
            inst$downloads[[name]] <- list(
              content_type = contentType,
              filename = if (is.function(filename)) {
                filename
              } else {
                function() filename
              }
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
  if (!is.null(message[["html"]])) {
    message[["html"]] <- as.character(message[["html"]])
  }
  if (length(message[["deps"]])) {
    message[["deps"]] <- payload_dependencies(message[["deps"]])
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
  value <- tryCatch(inst$client[[name]], error = function(e) {
    shiny::isolate(inst$client[[name]])
  })
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
  ui <- resolve_tag_functions(ui)
  specs <- list()
  walk_tag_tree(ui, function(tag) {
    mcp_id <- htmltools::tagGetAttribute(tag, "data-shinymcp-output")
    role <- detect_mcp_role(tag)
    if (is.null(mcp_id) && (role$role != "output" || is.null(role$id))) {
      if (
        !has_class(tag, "shiny-download-link") ||
          is.null(htmltools::tagGetAttribute(tag, "id"))
      ) {
        return()
      }
      role <- list(
        role = "output",
        id = htmltools::tagGetAttribute(tag, "id"),
        type = "download"
      )
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
  cls %in%
    strsplit(htmltools::tagGetAttribute(tag, "class") %||% "", "\\s+")[[1]]
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
    m <- regmatches(
      style,
      regexec(paste0(prop, "\\s*:\\s*([0-9.]+)px"), style, perl = TRUE)
    )[[1]]
    if (length(m) == 2) as.numeric(m[[2]]) else NULL
  }
  compact_list(list(
    width = px("(?<![a-z-])width"),
    height = px("(?<![a-z-])height")
  ))
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
collect_runtime_outputs <- function(inst, specs, skip_deps = character()) {
  dom_to_public <- stats::setNames(
    vapply(specs, function(s) s$id, character(1)),
    vapply(specs, function(s) s$dom_id %||% s$id, character(1))
  )
  ids <- unique(c(names(dom_to_public), inst$outputs))
  out <- list()
  # Each library once per result: an output skips what earlier ones brought.
  sent <- function(entry) {
    vapply(entry$payload$deps %||% list(), function(d) d$name, character(1))
  }
  for (dom_id in ids) {
    if (!dom_id %in% inst$outputs) {
      next
    }
    public_id <- if (dom_id %in% names(dom_to_public)) {
      dom_to_public[[dom_id]]
    } else {
      dom_id
    }
    spec <- specs[[public_id]] %||%
      list(id = public_id, dom_id = dom_id, type = NULL)
    if (!is.null(inst$downloads[[dom_id]])) {
      filename <- tryCatch(
        with_mock_context(
          inst$session,
          as.character(inst$downloads[[dom_id]]$filename())
        ),
        error = function(e) NULL
      )
      payload <- list(
        kind = "download",
        dom = dom_id,
        value = list(filename = filename)
      )
      out[[public_id]] <- list(
        payload = payload,
        model = paste0(
          "A file (",
          filename %||% "download",
          ") the user can download from the app."
        ),
        text = NULL,
        digest = rlang::hash(payload)
      )
      next
    }
    value <- tryCatch(
      with_mock_context(inst$session, mock_output(inst$session, dom_id)),
      error = function(e) e
    )
    out[[public_id]] <- runtime_output_entry(
      value,
      spec,
      dom_id,
      skip_deps,
      data = inst$data_objects[[dom_id]]$data
    )
    skip_deps <- c(skip_deps, sent(out[[public_id]]))
  }
  out
}

#' The HTML dependencies of a rendered htmlwidget
#'
#' A widget's render function lists its dependencies in the JSON it returns.
#' @noRd
widget_dependencies <- function(json) {
  parsed <- tryCatch(
    jsonlite::fromJSON(as.character(json), simplifyVector = FALSE),
    error = function(e) NULL
  )
  local_dependencies(parsed$deps)
}

#' Dependencies Shiny would serve by URL, as ones the page can inline
#'
#' Render functions hand the browser dependencies at paths Shiny serves
#' (shiny::createWebDependency()). The page can't fetch those, so each is
#' rebuilt from its directory among Shiny's resource paths. Libraries the
#' bridge replaces with its own controls are left out.
#' @noRd
local_dependencies <- function(deps) {
  if (length(deps) == 0) {
    return(list())
  }
  if (inherits(deps, "html_dependency")) {
    deps <- list(deps)
  }
  paths <- shiny::resourcePaths()
  deps <- lapply(deps, function(d) {
    if (
      !is.list(d) || !is_string(d$name) || d$name %in% SHINYMCP_REPLACED_DEPS
    ) {
      return(NULL)
    }
    if (is_string(d$src$file)) {
      return(d)
    }
    href <- d$src$href
    if (!is_string(href)) {
      return(NULL)
    }
    prefix <- sub("/.*$", "", href)
    dir <- paths[prefix]
    if (is.na(dir)) {
      return(NULL)
    }
    rest <- sub("^[^/]*/?", "", href)
    scripts <- d$script
    if (is.list(scripts) && all(vapply(scripts, is.character, logical(1)))) {
      scripts <- unlist(scripts)
    }
    htmltools::htmlDependency(
      name = d$name,
      version = d$version,
      src = c(file = if (nzchar(rest)) file.path(dir[[1]], rest) else dir[[1]]),
      script = scripts,
      stylesheet = unlist(d$stylesheet),
      head = d$head,
      all_files = FALSE
    )
  })
  Filter(Negate(is.null), deps)
}

#' Dependencies as payloads for the page, minus those it has
#' @noRd
payload_dependencies <- function(deps, skip_deps = character()) {
  deps <- local_dependencies(deps)
  deps <- Filter(function(d) !dependency_loaded(d, skip_deps), deps)
  if (length(deps) == 0) {
    return(NULL)
  }
  lapply(deps, dependency_payload)
}

#' Turn a render function's value into a page payload and a model value
#'
#' `data` is what the output registered with `session$registerDataObj()`, if
#' anything: DT's server-side tables keep their data frame there.
#' @noRd
runtime_output_entry <- function(
  value,
  spec,
  dom_id,
  skip_deps = character(),
  data = NULL
) {
  type <- spec$type
  entry <- if (inherits(value, "error")) {
    runtime_error_entry(value)
  } else if (is.null(value)) {
    list(payload = list(kind = "clear"), model = NULL, text = "")
  } else if (inherits(value, "json")) {
    # htmlwidgets: the widget's JSON, whose dependencies the page may not
    # have yet (plotly's library, for one, arrives with the first plot).
    deps <- widget_dependencies(value)
    deps <- Filter(function(d) !dependency_loaded(d, skip_deps), deps)
    c(
      list(
        payload = compact_list(list(
          kind = "widget",
          value = as.character(value),
          deps = if (length(deps)) lapply(deps, dependency_payload)
        )),
        digest = rlang::hash(as.character(value))
      ),
      widget_model_entry(data)
    )
  } else if (is.list(value) && !is.null(value$src)) {
    alt <- value$alt
    if (is.null(alt) || identical(alt, "Plot object")) {
      alt <- sprintf(
        "A plot (%s x %s).",
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
          class = value$class,
          # Where the plot's panels are, for clicks and brushes.
          coordmap = value$coordmap
        ))
      ),
      model = alt,
      text = alt,
      image = image
    )
  } else if (is.list(value) && !is.null(value$html)) {
    html <- as.character(value$html)
    text <- html_to_text(html)
    list(
      payload = compact_list(list(
        kind = "html",
        value = html,
        deps = payload_dependencies(value$deps, skip_deps)
      )),
      model = text,
      text = text
    )
  } else if (is.character(value)) {
    text_output <- identical(type, "text") ||
      identical(type, "verbatimText") ||
      (is.null(type) && !grepl("<[a-zA-Z][^>]*>", value[[1]]))
    text <- if (text_output) {
      paste(value, collapse = "\n")
    } else {
      html_to_text(value)
    }
    list(
      payload = list(
        kind = if (text_output) "text" else "html",
        value = paste(value, collapse = "\n")
      ),
      model = text,
      text = text
    )
  } else {
    # A value from something other than a render function, such as
    # `output$ready <- reactive(TRUE)` for a conditionalPanel() to read.
    text <- paste(utils::capture.output(print(value)), collapse = "\n")
    raw <- if (is.atomic(value) && length(value) <= 1000) {
      if (is.factor(value) || inherits(value, c("Date", "POSIXt"))) {
        format(value)
      } else {
        unclass(value)
      }
    }
    list(
      payload = compact_list(list(kind = "text", value = text, raw = raw)),
      model = text,
      text = text
    )
  }
  entry$payload$dom <- dom_id
  # Widgets hash their JSON only, so whether their dependencies were sent
  # doesn't count as a change.
  entry$digest <- entry$digest %||% rlang::hash(entry$payload)
  entry
}

#' What the model reads for an htmlwidget
#'
#' A widget that keeps a data frame in R, as DT's server-side tables do, is
#' described by that data, the way a table output is. Other widgets hold
#' their data in the page, so the model only learns that there is one.
#' @noRd
widget_model_entry <- function(data = NULL) {
  if (!is.data.frame(data)) {
    return(list(
      model = "An interactive widget.",
      text = "An interactive widget."
    ))
  }
  list(
    model = table_records(data),
    text = paste0(
      "A table with ",
      nrow(data),
      if (nrow(data) == 1) " row" else " rows",
      ":\n",
      table_text(data)
    )
  )
}

#' An error's message as a Shiny app would show it
#'
#' With the `shiny.sanitize.errors` option set, Shiny shows a generic
#' message in place of any error not made with `safeError()`.
#' @noRd
session_error_message <- function(e) {
  if (
    isTRUE(getOption("shiny.sanitize.errors")) &&
      !inherits(e, "shiny.custom.error")
  ) {
    return(
      "An error has occurred. Check your logs or contact the app author for clarification."
    )
  }
  cli::ansi_strip(conditionMessage(e))
}

#' @noRd
runtime_error_entry <- function(e) {
  message <- cli::ansi_strip(conditionMessage(e))
  # ExtendedTask$result() while the task runs: the output keeps what it
  # shows, looks busy, and the page comes back for the result.
  if (inherits(e, "shiny.output.progress")) {
    return(list(
      payload = list(kind = "progress"),
      model = NULL,
      text = "",
      progress = TRUE
    ))
  }
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
  message <- session_error_message(e)
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
    function(id) {
      id %in% names(from_page) && identical(sent[[id]], from_page[[id]])
    },
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

  # `[[` and not `$`: bslib's accordion sends `values`, which `$value`
  # would match.
  if (!is.null(message[["value"]])) {
    value <- message[["value"]]
    # updateDateRangeInput() sends only the ends it changes.
    if (is.list(value) && any(c("start", "end") %in% names(value))) {
      now <- if (length(current) == 2) as.character(current) else c(NA, NA)
      value <- c(value$start %||% now[[1]], value$end %||% now[[2]])
    }
    new <- coerce_input_value(
      value,
      spec %||% list(id = id, kind = kind),
      previous = current
    )
    return(if (identical(new, current)) NULL else list(value = new))
  }
  if (!is.null(message[["options"]]) && kind %in% c("select", "radio")) {
    values <- option_values(message[["options"]])
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
  if (
    !is.null(message[["options"]]) &&
      kind %in% c("select-multiple", "checkbox-group")
  ) {
    # New options replace the old ones, selection included, so only the
    # values they mark as selected remain.
    selected <- attr(option_values(message[["options"]]), "selected")
    new <- if (length(selected)) selected
    return(if (identical(new, current)) NULL else list(value = new))
  }
  NULL
}

#' @noRd
guess_kind_from_message <- function(message, current) {
  if (!is.null(message[["options"]])) {
    return(if (length(current) > 1) "select-multiple" else "select")
  }
  if (is.logical(current)) {
    "checkbox"
  } else if (is.numeric(current)) {
    "number"
  } else {
    "text"
  }
}

#' Values (and selected values) in an HTML options fragment
#' @noRd
option_values <- function(html) {
  html <- paste(as.character(html), collapse = "")
  tags <- regmatches(
    html,
    gregexpr("<(option|input)\\b[^>]*>", html, ignore.case = TRUE)
  )[[1]]
  values <- character()
  selected <- character()
  for (tag in tags) {
    attrs <- parse_html_attributes(sub("^<[a-zA-Z]+|/?>$", "", tag))
    is_input <- grepl("^<input", tag, ignore.case = TRUE)
    if (is_input && !tolower(attrs["type"]) %in% c("radio", "checkbox")) {
      next
    }
    if (!"value" %in% names(attrs)) {
      next
    }
    value <- attrs[["value"]]
    values <- c(values, value)
    if (any(c("selected", "checked") %in% names(attrs))) {
      selected <- c(selected, value)
    }
  }
  structure(values, selected = selected)
}

#' Text the model reads after opening or updating the app
#' @noRd
runtime_result_text <- function(
  runtime,
  inst,
  collected,
  model,
  unknown = character(),
  continued = FALSE,
  lost_view = NULL
) {
  title <- runtime$title %||% runtime$app_name
  limit <- getOption("shinymcp.max_text_chars", 4000)
  lines <- if (!model) {
    paste0(title, " updated.")
  } else if (continued) {
    paste0("Updated the ", title, " app (view ", inst$id, ").")
  } else {
    c(
      paste0(
        "The ",
        title,
        " app is open in the conversation (view ",
        inst$id,
        ")."
      ),
      if (!is.null(lost_view)) {
        paste0(
          "View ",
          lost_view,
          " is no longer running, so this is a new view; ",
          "inputs you didn't set are back to their defaults."
        )
      }
    )
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
              function(id) {
                paste0(id, " = ", format_snapshot_value(snapshot[[id]]))
              },
              character(1)
            ),
            collapse = "; "
          ),
          "."
        )
      )
    }
    if (length(unknown)) {
      lines <- c(
        lines,
        paste0(
          "Ignored unknown arguments: ",
          paste(unknown, collapse = ", "),
          "."
        )
      )
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
      if (grepl("\n", text, fixed = TRUE)) {
        paste0(id, ":\n", text)
      } else {
        paste0(id, ": ", text)
      }
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
  paste(as.character(unlist(x)), collapse = ", ")
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
    inputs_text <- if (length(snapshot)) {
      paste(
        vapply(
          names(snapshot),
          function(id) paste0(id, " = ", format_snapshot_value(snapshot[[id]])),
          character(1)
        ),
        collapse = "; "
      )
    }
    text <- paste0(
      "In the ",
      runtime$title %||% runtime$app_name,
      " app (view ",
      inst$id,
      ")",
      if (!is.null(inputs_text)) paste0(", the user has set ", inputs_text),
      ".",
      if (length(summary)) {
        paste0(
          " It shows: ",
          paste(names(summary), unlist(summary), sep = ": ", collapse = "; "),
          if (!grepl("[.!?]$", summary[[length(summary)]])) "."
        )
      }
    )
    context <- list(
      text = text,
      data = compact_list(list(
        app = runtime$app_name,
        view = inst$id,
        inputs = snapshot,
        outputs = if (length(summary)) summary
      ))
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
#' @inheritSection as_mcp_app Shiny's own MCP support
#' @param text Text for the model (or the chat message).
#' @param data A named list of structured data for the model.
#' @param session The Shiny session. The default works inside a server
#'   function and in modules.
#' @return `mcp_model_context()` and `mcp_send_message()` invisibly return
#'   `TRUE` when the message will be delivered, `FALSE` otherwise.
#'   `is_mcp_session()` returns a logical.
#' @family server function helpers
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
mcp_send_message <- function(
  text,
  session = shiny::getDefaultReactiveDomain()
) {
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

#' The chat client around a Shiny app served with shinymcp
#'
#' @description
#' `mcp_host_context()` reports what the chat client showing the app has
#' told it: the color theme, whether the app is inline or full screen, and
#' the user's locale and time zone. Reading it inside a reactive expression,
#' observer, or render function makes that code run again when it changes,
#' so a plot can switch to dark colors when the user switches the chat to
#' dark mode.
#'
#' The values arrive with the app's first request from the page, so the
#' first render, for the model's call that opened the app, sees an empty
#' list.
#'
#' @inheritSection as_mcp_app Shiny's own MCP support
#' @inheritParams mcp_model_context
#' @return A named list with any of `theme` (`"light"` or `"dark"`),
#'   `display_mode` (`"inline"`, `"fullscreen"`, or `"pip"`), `locale`,
#'   `time_zone`, and `platform`. An empty list before the page has reported
#'   them, and `NULL` outside shinymcp's runtime.
#' @family server function helpers
#' @export
#' @examples
#' server <- function(input, output, session) {
#'   output$plot <- shiny::renderPlot({
#'     dark <- identical(mcp_host_context()$theme, "dark")
#'     par(bg = if (dark) "#1f1f1e" else "white", fg = if (dark) "grey90" else "black")
#'     plot(mtcars$wt, mtcars$mpg, col.axis = par("fg"), col.lab = par("fg"))
#'   })
#' }
mcp_host_context <- function(session = shiny::getDefaultReactiveDomain()) {
  inst <- runtime_instance(session)
  if (is.null(inst)) {
    return(NULL)
  }
  inst$host()
}

#' @noRd
runtime_instance <- function(session) {
  # Without Shiny there's no session, and the helpers' default for it,
  # shiny::getDefaultReactiveDomain(), can't be evaluated: check first.
  if (!rlang::is_installed("shiny") || is.null(session)) {
    return(NULL)
  }
  inst <- tryCatch(session$userData$.shinymcp, error = function(e) NULL)
  if (is.environment(inst)) inst else NULL
}
