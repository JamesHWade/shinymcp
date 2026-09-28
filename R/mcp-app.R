# McpApp: a UI plus the tools behind it, servable as an MCP App.

#' MCP App object
#'
#' @description
#' An `McpApp` bundles a user interface with the tools it calls. It knows how
#' to render itself as the self-contained HTML page an MCP host shows (the
#' app's `ui://` resource), how to describe its tools to a client, and how to
#' run them. Create one with [mcp_app()] or [as_mcp_app()] rather than
#' calling `McpApp$new()` directly; the arguments are the same.
#'
#' Most code only needs `$call_tool()` (run a tool and get its R value
#' back, as in tests) and `$html_resource()` (the page a host renders).
#'
#' @family apps
#' @export
McpApp <- R6::R6Class(
  "McpApp",
  public = list(
    #' @field name App name; the UI resource is `ui://<name>`, with any
    #'   characters a URI can't carry percent-encoded.
    name = NULL,
    #' @field version App version string.
    version = NULL,
    #' @field title Human-readable title, or `NULL`.
    title = NULL,
    #' @field description What the app is for, or `NULL`.
    description = NULL,

    #' @description Create an app. See [mcp_app()] for the arguments.
    #' @param ui,tools,name,version,title,description,theme,csp,permissions,prefers_border,domain,tool_visibility,tool_outputs,trigger,debounce_ms,resources,host_styles,model_context,images,www See [mcp_app()].
    #' @param runtime Internal: the live Shiny runtime for apps created by
    #'   [as_mcp_app()] from a Shiny app.
    initialize = function(
      ui,
      tools = list(),
      name = "shinymcp-app",
      version = "0.1.0",
      title = NULL,
      description = NULL,
      theme = NULL,
      csp = NULL,
      permissions = NULL,
      prefers_border = NULL,
      domain = NULL,
      tool_visibility = NULL,
      tool_outputs = NULL,
      trigger = NULL,
      debounce_ms = NULL,
      resources = NULL,
      host_styles = TRUE,
      model_context = TRUE,
      images = TRUE,
      www = NULL,
      runtime = NULL
    ) {
      if (!inherits(ui, c("shiny.tag", "shiny.tag.list", "html"))) {
        shinymcp_abort(
          "{.arg ui} must be an htmltools tag or tag list, not {.cls {class(ui)}}.",
          class = "shinymcp_error_validation"
        )
      }
      if (inherits(tools, "shinymcp_tool") || is_ellmer_tool(tools)) {
        tools <- list(tools)
      }
      if (!is.list(tools)) {
        shinymcp_abort(
          "{.arg tools} must be a list of tools.",
          class = "shinymcp_error_validation"
        )
      }
      if (!is_string(name)) {
        shinymcp_abort(
          "{.arg name} must be a single non-empty string.",
          class = "shinymcp_error_validation"
        )
      }
      if (!is.null(theme)) {
        rlang::check_installed("bslib", reason = "to theme an MCP App.")
        if (is_page(ui)) {
          shinymcp_abort(
            c(
              "{.arg theme} applies only to a UI that isn't already a page.",
              "i" = "Give the theme to your page function instead, as in {.code bslib::page_fluid(theme = ...)}."
            ),
            class = "shinymcp_error_validation"
          )
        }
        ui <- bslib::page(theme = theme, ui)
      }
      if (!is.null(trigger)) {
        trigger <- rlang::arg_match0(
          trigger,
          c("debounce", "change", "submit", "manual")
        )
      }
      if (
        !is.null(debounce_ms) &&
          !(is.numeric(debounce_ms) &&
            length(debounce_ms) == 1 &&
            !is.na(debounce_ms) &&
            debounce_ms >= 0)
      ) {
        shinymcp_abort(
          "{.arg debounce_ms} must be a single non-negative number of milliseconds.",
          class = "shinymcp_error_validation"
        )
      }

      self$name <- name
      self$version <- version
      self$title <- title
      self$description <- description

      normalized <- lapply(seq_along(tools), function(i) {
        as_mcp_tool(tools[[i]], index = i)
      })
      names(normalized) <- vapply(normalized, `[[`, character(1), "name")
      dupes <- unique(names(normalized)[duplicated(names(normalized))])
      if (length(dupes)) {
        shinymcp_abort(
          "Tool names must be unique; {.val {dupes}} appear more than once.",
          class = "shinymcp_error_validation"
        )
      }
      normalized <- apply_tool_visibility(normalized, tool_visibility)
      normalized <- apply_tool_outputs(normalized, tool_outputs)

      private$.ui <- ui
      private$.tools <- normalized
      private$.csp <- csp_to_meta(csp)
      private$.permissions <- permissions_to_meta(permissions)
      private$.prefers_border <- prefers_border
      private$.domain <- domain
      private$.trigger <- trigger
      private$.debounce_ms <- debounce_ms
      private$.resources <- normalize_extra_resources(resources)
      private$.host_styles <- isTRUE(host_styles)
      private$.model_context <- isTRUE(model_context)
      private$.images <- isTRUE(images)
      if (!is.null(www) && !(is_string(www) && dir.exists(www))) {
        shinymcp_abort(
          "{.arg www} must be the path of a directory.",
          class = "shinymcp_error_validation"
        )
      }
      private$.www <- www
      private$.runtime <- runtime
      invisible(self)
    },

    #' @description The HTML page an MCP host renders for this app.
    #'   Dependencies (Bootstrap, bslib components, htmlwidgets) are inlined
    #'   so the page works under a host's default Content Security Policy.
    #' @param config Named list merged into the bridge configuration. Hosts
    #'   use it to pass their own settings; apps rarely need it.
    html_resource = function(config = NULL) {
      build_app_html(self, private, config)
    },

    #' @description The app's `ui://` resource URI.
    resource_uri = function() {
      paste0("ui://", utils::URLencode(self$name, reserved = TRUE))
    },

    #' @description The `_meta` published with the app's `ui://` resource
    #'   (CSP, permissions, border preference), or `NULL`.
    resource_meta = function() {
      ui <- compact_list(list(
        csp = private$.csp,
        permissions = private$.permissions,
        domain = private$.domain,
        prefersBorder = private$.prefers_border
      ))
      if (length(ui) == 0) NULL else list(ui = ui)
    },

    #' @description Resource records for `resources/list`: the app's UI and
    #'   any extra resources.
    resources = function() {
      main <- compact_list(list(
        uri = self$resource_uri(),
        name = self$name,
        title = self$title,
        description = self$description %||% paste("MCP App:", self$name),
        mimeType = SHINYMCP_UI_MIME_TYPE,
        `_meta` = self$resource_meta()
      ))
      extra <- lapply(unname(private$.resources), function(res) {
        compact_list(list(
          uri = res$uri,
          name = res$name,
          description = res$description,
          mimeType = res$mime_type,
          `_meta` = res$meta
        ))
      })
      c(list(main), extra)
    },

    #' @description Read one of the app's resources.
    #' @param uri Resource URI.
    #' @return A `resources/read` contents entry (`uri`, `mimeType`, `text`,
    #'   optional `_meta`).
    read_resource = function(uri) {
      if (identical(uri, self$resource_uri())) {
        return(compact_list(list(
          uri = uri,
          mimeType = SHINYMCP_UI_MIME_TYPE,
          text = self$html_resource(),
          `_meta` = self$resource_meta()
        )))
      }
      spec <- private$.resources[[uri]]
      if (is.null(spec)) {
        shinymcp_error_resource("Resource not found: {.val {uri}}", uri = uri)
      }
      compact_list(list(
        uri = spec$uri,
        mimeType = spec$mime_type,
        text = coerce_resource_text(spec$content_fn()),
        `_meta` = spec$meta
      ))
    },

    #' @description Does the app serve this resource URI?
    #' @param uri Resource URI.
    has_resource = function(uri) {
      identical(uri, self$resource_uri()) || !is.null(private$.resources[[uri]])
    },

    #' @description The app's tools, normalized.
    #' @param audience `NULL` for all tools, or `"model"` / `"app"` for the
    #'   tools that audience may call.
    tools = function(audience = NULL) {
      tools <- private$.tools
      if (!is.null(audience)) {
        tools <- Filter(function(t) tool_visible_to(t, audience), tools)
      }
      tools
    },

    #' @description Tool definitions for an MCP `tools/list` response.
    #' @param include_ui_meta Include the nested `_meta.ui` block. `FALSE`
    #'   for clients that did not declare MCP Apps support.
    #' @param include_app_only Include tools only the app's UI can call.
    tool_definitions = function(
      include_ui_meta = TRUE,
      include_app_only = TRUE
    ) {
      tools <- private$.tools
      if (!include_app_only) {
        tools <- Filter(function(t) tool_visible_to(t, "model"), tools)
      }
      ui_outputs <- private$ui_outputs()
      unname(lapply(tools, function(tool) {
        output_schema <- if (
          is.null(tool$output_schema) && length(tool$outputs)
        ) {
          build_output_schema(tool$outputs, ui_outputs)
        }
        tool_wire_definition(
          tool,
          resource_uri = self$resource_uri(),
          include_ui_meta = include_ui_meta,
          output_schema = output_schema
        )
      }))
    },

    #' @description Run a tool and return its R value, as the tool function
    #'   returned it. Useful in tests.
    #' @param name Tool name.
    #' @param arguments Named list of arguments, as a client would send them.
    #' @param context Request context; see [mcp_request()].
    call_tool = function(name, arguments = list(), context = list()) {
      tool <- private$find_tool(name)
      context <- utils::modifyList(
        list(caller = "model", transport = "in-process"),
        context %||% list()
      )
      with_request_context(
        context,
        tool$handler(arguments %||% list(), context)
      )
    },

    #' @description Run a tool and return an MCP `tools/call` result.
    #' @param name Tool name.
    #' @param arguments Named list of arguments.
    #' @param context Request context. `caller = "app"` marks calls from the
    #'   app's own UI, and `images = FALSE` asks for a result without image
    #'   blocks for the model.
    #' @param raw If `TRUE`, return a list with the `result` and the `raw`
    #'   value the tool function returned (`NULL` if it failed).
    run_tool = function(
      name,
      arguments = list(),
      context = list(),
      raw = FALSE
    ) {
      result <- private$run_tool_parts(name, arguments, context)
      if (raw) result else result$result
    },

    #' @description Does the app have a tool with this name?
    #' @param name Tool name.
    has_tool = function(name) {
      !is.null(private$.tools[[name]])
    },

    #' @description The app's declared interaction defaults (`trigger`,
    #'   `debounce_ms`), each possibly `NULL`.
    interaction_defaults = function() {
      list(trigger = private$.trigger, debounce_ms = private$.debounce_ms)
    },

    #' @description The live Shiny runtime behind an app made from a Shiny
    #'   app, or `NULL`.
    runtime = function() {
      private$.runtime
    },

    #' @description Close the app's open views and stop the Shiny app
    #'   behind it, if any, running its `onStop` hook. [serve()] and
    #'   [mcp_endpoint()] call this when they stop.
    close = function() {
      if (!is.null(private$.runtime)) {
        private$.runtime$close_all()
      }
      invisible(self)
    },

    #' @description Output ids and types found in the UI.
    output_types = function() {
      private$ui_outputs()
    },

    #' @description Print a summary.
    #' @param ... Ignored.
    print = function(...) {
      tools <- private$.tools
      lines <- c(
        paste0("<McpApp> ", self$name, " ", self$version),
        if (!is.null(self$title)) paste0("Title: ", self$title),
        if (!is.null(self$description)) {
          strwrap(self$description, width = getOption("width", 80))
        },
        paste0("UI resource: ", self$resource_uri()),
        if (!is.null(private$.runtime)) {
          "Runs the Shiny app's server function, one session per view."
        },
        if (length(tools) == 0) {
          "No tools."
        } else {
          c(
            "Tools:",
            vapply(
              tools,
              function(t) {
                scope <- if (
                  !is.null(t$visibility) && !"model" %in% t$visibility
                ) {
                  " (app only)"
                } else {
                  ""
                }
                paste0("* ", t$name, scope)
              },
              character(1)
            )
          )
        }
      )
      cli::cat_line(lines)
      invisible(self)
    }
  ),

  private = list(
    # Run a tool: its MCP result, and the R value its function returned.
    run_tool_parts = function(name, arguments, context) {
      tool <- private$find_tool(name)
      context <- utils::modifyList(
        list(caller = "model", transport = "in-process"),
        context %||% list()
      )
      images <- private$.images &&
        !isFALSE(context$images) &&
        !identical(context$caller, "app")
      if (!images) {
        context$images <- FALSE
      }
      # Results never carry a library the page was built with.
      context$skip_deps <- union(
        as.character(unlist(context$skip_deps)),
        private$page_dep_names()
      )
      raw <- tryCatch(
        with_request_context(
          context,
          tool$handler(arguments %||% list(), context)
        ),
        error = function(e) e
      )
      if (inherits(raw, "error")) {
        return(list(result = tool_error_result(raw), raw = NULL))
      }
      if (inherits(raw, "shinymcp_wire_result")) {
        return(list(result = unclass(raw), raw = raw))
      }
      result <- tryCatch(
        build_tool_result(
          raw,
          images = images,
          skip_deps = context$skip_deps %||% character(),
          view = list(tool = name),
          output_types = private$ui_outputs(),
          sizes = context$sizes,
          pixel_ratio = context$pixel_ratio
        ),
        error = tool_error_result
      )
      list(result = result, raw = raw)
    },

    .ui = NULL,
    .tools = list(),
    .csp = NULL,
    .permissions = NULL,
    .prefers_border = NULL,
    .domain = NULL,
    .trigger = NULL,
    .debounce_ms = NULL,
    .resources = list(),
    .host_styles = TRUE,
    .model_context = TRUE,
    .images = TRUE,
    .www = NULL,
    .runtime = NULL,
    .ui_outputs = NULL,
    .rendered = NULL,
    .page_deps = NULL,

    find_tool = function(name) {
      tool <- private$.tools[[name %||% ""]]
      if (is.null(tool)) {
        shinymcp_abort(
          "Tool {.val {name}} not found in app {.val {self$name}}.",
          class = "shinymcp_error_tool_not_found"
        )
      }
      tool
    },

    # Render the UI once; the tag tree doesn't change after construction.
    rendered = function() {
      if (is.null(private$.rendered)) {
        private$.rendered <- htmltools::renderTags(private$.ui)
      }
      private$.rendered
    },

    page_dep_names = function() {
      if (is.null(private$.page_deps)) {
        private$.page_deps <- vapply(
          app_page_dependencies(private$rendered()),
          function(d) d$name,
          character(1)
        )
      }
      private$.page_deps
    },

    ui_outputs = function() {
      if (is.null(private$.ui_outputs)) {
        outputs <- extract_outputs_from_tags(private$.ui, selective = FALSE)
        types <- vapply(outputs, function(o) o$type %||% "html", character(1))
        names(types) <- vapply(outputs, `[[`, character(1), "id")
        private$.ui_outputs <- types
      }
      private$.ui_outputs
    }
  )
)

#' Create an MCP App
#'
#' @description
#' An MCP App is an interactive page that an AI chat client (Claude, ChatGPT,
#' VS Code, Goose) shows inside the conversation, next to the tools that feed
#' it. `mcp_app()` pairs a UI with those tools:
#'
#' * The **UI** is ordinary htmltools: Shiny or bslib inputs, outputs, and
#'   layouts, or shinymcp's own components such as [mcp_select()] and
#'   [mcp_plot()].
#' * The **tools** are R functions, usually written with [ellmer::tool()].
#'   A tool's argument names match input ids, and the names of the list it
#'   returns match output ids. When the user changes an input, the app calls
#'   the tools that take that input and fills in their outputs.
#'
#' The model can call the same tools. When it does, the host shows the app
#' and the app fills in from the result. Tools keep nothing between calls,
#' so any R process can answer any call.
#'
#' To make one from a Shiny app you already have, see
#' `vignette("rewriting-as-tools")`.
#'
#' @param ui The app's UI: an htmltools tag or tag list, or a full page such
#'   as [bslib::page_sidebar()].
#' @param tools A list of tools: [ellmer::tool()] objects, or plain lists
#'   with `name`, `description`, `fun`, and optionally `inputSchema`,
#'   `outputSchema`, `annotations`, and `visibility`.
#' @param name App name, used for the `ui://<name>` resource. Letters,
#'   digits, `-` and `_` work everywhere.
#' @param version App version string.
#' @param title Human-readable title, shown by some hosts.
#' @param description What the app does. Hosts and models read it when
#'   deciding whether to use it.
#' @param theme A [bslib::bs_theme()] to wrap a UI that isn't already a page.
#' @param csp External domains the page needs, as a named list with any of
#'   `connect_domains` (fetch and WebSocket), `resource_domains` (scripts,
#'   styles, images, fonts), `frame_domains` (nested iframes), and
#'   `base_uri_domains`. Hosts block everything not declared. shinymcp
#'   inlines its own dependencies, so most apps need none.
#' @param permissions Browser permissions the page asks for: a character
#'   vector drawn from `"camera"`, `"microphone"`, `"geolocation"`, and
#'   `"clipboard_write"`. Hosts may refuse.
#' @param prefers_border `TRUE` or `FALSE` to ask the host for (or not for)
#'   a border and background around the app. `NULL` leaves it to the host.
#' @param domain A dedicated origin for the app's sandbox, in the format the
#'   host documents. Rarely needed.
#' @param tool_visibility Who may call each tool: a named list mapping tool
#'   names to `"model"`, `"app"`, or both. Tools only the app calls (`"app"`)
#'   are hidden from the model; use them for controls that must stay in the
#'   user's hands, such as an approval button.
#' @param tool_outputs The output ids each tool returns, as a named list
#'   (`list(explore = c("scatter", "stats"))`). Declared tools get an
#'   `outputSchema`.
#' @param trigger When the app calls tools as inputs change: `"debounce"`
#'   (after a pause, the default), `"change"` (on every change), or
#'   `"submit"` (when the user presses an apply button; add one with
#'   [mcp_submit_button()]).
#' @param debounce_ms The pause for `trigger = "debounce"`, in milliseconds
#'   (default 250).
#' @param resources Extra resources the page can load on demand with
#'   `window.shinymcp.readResource(uri)`, as a named list from URI to a
#'   string, a function returning a string, or a list with `content`,
#'   `mime_type`, `name`, `description`, and `meta`. Use this to keep large
#'   data out of the page.
#' @param host_styles If `TRUE` (the default) the app takes the host's
#'   colors and fonts when the host provides them, so it looks native in
#'   each client. Set `FALSE` to keep your own theme.
#' @param model_context If `TRUE` (the default) the app tells the model what
#'   the user has changed in it, so the model can take it into account on
#'   its next turn.
#' @param images If `TRUE` (the default) plots and images in a result
#'   returned to the model are also sent as image content the model can
#'   see. Set `FALSE` to save tokens.
#' @param www A directory of files the UI refers to by relative path, like
#'   a Shiny app's `www/` folder: scripts, stylesheets, and images. They are
#'   written into the page, since a host's frame can't fetch them. Paths
#'   added with [shiny::addResourcePath()] are found without it.
#' @param ... Passed to `McpApp$new()`.
#' @return An [McpApp] object.
#' @family apps
#' @export
#' @examplesIf rlang::is_installed("ellmer")
#' app <- mcp_app(
#'   ui = htmltools::tagList(
#'     mcp_text_input("name", "Your name", value = "world"),
#'     mcp_text("greeting")
#'   ),
#'   tools = list(
#'     ellmer::tool(
#'       function(name = "world") list(greeting = paste0("Hello, ", name, "!")),
#'       name = "greet",
#'       description = "Greet someone by name.",
#'       arguments = list(name = ellmer::type_string("Name to greet"))
#'     )
#'   ),
#'   name = "greeter"
#' )
#' app
#' app$call_tool("greet", list(name = "Ada"))
#'
#' \dontrun{
#' preview_app(app) # try it in a browser
#' serve(app)       # serve it to an MCP client over stdio
#' }
mcp_app <- function(
  ui,
  tools = list(),
  name = "shinymcp-app",
  version = "0.1.0",
  title = NULL,
  description = NULL,
  theme = NULL,
  csp = NULL,
  permissions = NULL,
  prefers_border = NULL,
  domain = NULL,
  tool_visibility = NULL,
  tool_outputs = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  resources = NULL,
  host_styles = TRUE,
  model_context = TRUE,
  images = TRUE,
  www = NULL,
  ...
) {
  McpApp$new(
    ui = ui,
    tools = tools,
    name = name,
    version = version,
    title = title,
    description = description,
    theme = theme,
    csp = csp,
    permissions = permissions,
    prefers_border = prefers_border,
    domain = domain,
    tool_visibility = tool_visibility,
    tool_outputs = tool_outputs,
    trigger = trigger,
    debounce_ms = debounce_ms,
    resources = resources,
    host_styles = host_styles,
    model_context = model_context,
    images = images,
    www = www,
    ...
  )
}

# ---- Construction helpers ----

#' @noRd
apply_tool_visibility <- function(
  tools,
  tool_visibility,
  call = rlang::caller_env()
) {
  if (is.null(tool_visibility)) {
    return(tools)
  }
  if (!is.list(tool_visibility) || is.null(names(tool_visibility))) {
    shinymcp_abort(
      "{.arg tool_visibility} must be a named list (tool name -> visibility).",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  unknown <- setdiff(names(tool_visibility), names(tools))
  if (length(unknown)) {
    cli::cli_warn(
      "{.arg tool_visibility} names {.val {unknown}}, which match no tool (tools: {.val {names(tools)}})."
    )
  }
  for (nm in intersect(names(tool_visibility), names(tools))) {
    tools[[nm]]$visibility <- validate_visibility(
      tool_visibility[[nm]],
      nm,
      call = call
    )
  }
  tools
}

#' @noRd
apply_tool_outputs <- function(
  tools,
  tool_outputs,
  call = rlang::caller_env()
) {
  if (is.null(tool_outputs)) {
    return(tools)
  }
  if (
    !is.list(tool_outputs) ||
      is.null(names(tool_outputs)) ||
      !all(vapply(tool_outputs, is.character, logical(1)))
  ) {
    shinymcp_abort(
      "{.arg tool_outputs} must be a named list of character vectors (tool name -> output ids).",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  unknown <- setdiff(names(tool_outputs), names(tools))
  if (length(unknown)) {
    cli::cli_warn(
      "{.arg tool_outputs} names {.val {unknown}}, which match no tool (tools: {.val {names(tools)}})."
    )
  }
  for (nm in intersect(names(tool_outputs), names(tools))) {
    tools[[nm]]$outputs <- tool_outputs[[nm]]
  }
  tools
}

#' Convert CSP declarations to the spec's `_meta.ui.csp` keys
#' @noRd
csp_to_meta <- function(csp, call = rlang::caller_env()) {
  if (is.null(csp)) {
    return(NULL)
  }
  if (!is.list(csp) || is.null(names(csp)) || any(!nzchar(names(csp)))) {
    shinymcp_abort(
      "{.arg csp} must be a named list of domain declarations.",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  key_map <- c(
    connect_domains = "connectDomains",
    resource_domains = "resourceDomains",
    frame_domains = "frameDomains",
    base_uri_domains = "baseUriDomains"
  )
  allowed <- unique(c(names(key_map), unname(key_map)))
  out <- list()
  for (nm in names(csp)) {
    if (!nm %in% allowed) {
      shinymcp_abort(
        "Unknown {.arg csp} field {.val {nm}}. Use {.or {.val {names(key_map)}}}.",
        class = "shinymcp_error_validation",
        call = call
      )
    }
    key <- if (nm %in% names(key_map)) key_map[[nm]] else nm
    out[[key]] <- I(as.character(unlist(csp[[nm]])))
  }
  out
}

#' Convert permission requests to the spec's `_meta.ui.permissions`
#' @noRd
permissions_to_meta <- function(permissions, call = rlang::caller_env()) {
  if (is.null(permissions)) {
    return(NULL)
  }
  key_map <- c(
    camera = "camera",
    microphone = "microphone",
    geolocation = "geolocation",
    clipboard_write = "clipboardWrite",
    clipboardWrite = "clipboardWrite"
  )
  # Accept the older list(camera = list()) form as well as a character vector.
  requested <- if (is.character(permissions)) {
    permissions
  } else {
    names(permissions)
  }
  unknown <- setdiff(requested, names(key_map))
  if (length(unknown) || length(requested) == 0) {
    shinymcp_abort(
      "{.arg permissions} must name permissions from {.val {c('camera', 'microphone', 'geolocation', 'clipboard_write')}}.",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  out <- lapply(requested, function(x) json_object())
  names(out) <- unname(key_map[requested])
  out
}

#' Normalize extra resources declared with `mcp_app(resources = )`
#' @noRd
normalize_extra_resources <- function(resources, call = rlang::caller_env()) {
  if (is.null(resources)) {
    return(list())
  }
  if (
    !is.list(resources) ||
      is.null(names(resources)) ||
      any(!nzchar(names(resources)))
  ) {
    shinymcp_abort(
      "{.arg resources} must be a named list (URI -> content).",
      class = "shinymcp_error_validation",
      call = call
    )
  }
  out <- list()
  for (uri in names(resources)) {
    spec <- resources[[uri]]
    if (is.function(spec) || (is.character(spec) && length(spec) == 1)) {
      spec <- list(content = spec)
    } else if (!is.list(spec)) {
      shinymcp_abort(
        "Resource {.val {uri}} must be a string, a function, or a list with a {.field content} field.",
        class = "shinymcp_error_validation",
        call = call
      )
    }
    content <- spec$content
    content_fn <- if (is.function(content)) {
      content
    } else if (is.character(content) && length(content) == 1) {
      local({
        static <- content
        function() static
      })
    } else {
      shinymcp_abort(
        "Resource {.val {uri}} needs {.field content}: a single string or a function returning one.",
        class = "shinymcp_error_validation",
        call = call
      )
    }
    out[[uri]] <- list(
      uri = uri,
      name = spec$name %||% uri,
      description = spec$description %||% "",
      mime_type = spec$mime_type %||% "text/plain",
      content_fn = content_fn,
      meta = spec$meta
    )
  }
  out
}

#' Coerce resource content to a plain string
#'
#' `jsonlite::toJSON()` returns a `json`-classed object that serializers
#' would inline as raw JSON; strip classes and collapse vectors.
#' @noRd
coerce_resource_text <- function(content) {
  content <- as.character(content)
  if (length(content) != 1) {
    content <- paste(content, collapse = "\n")
  }
  content
}

#' A tool error as an MCP result the model can read
#' @noRd
tool_error_result <- function(e) {
  message <- if (inherits(e, "rlang_error")) {
    rlang::cnd_message(e)
  } else {
    conditionMessage(e)
  }
  message <- cli::ansi_strip(message)
  list(
    content = list(text_block(paste("Error:", message))),
    isError = TRUE
  )
}
