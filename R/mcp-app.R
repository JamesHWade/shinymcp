# McpApp R6 class - bundles UI + tools into a servable MCP App

#' MCP App
#'
#' An R6 class that bundles UI components and tools into a servable MCP App.
#' The app generates HTML with an embedded JS bridge and provides tools
#' annotated with resource URIs for MCP consumption.
#'
#' @param bridge_config Optional named list of bridge config overrides used by
#'   `$html_resource()`.
#' @export
McpApp <- R6::R6Class(
  "McpApp",
  public = list(
    #' @field name App name
    name = NULL,
    #' @field version App version
    version = NULL,

    #' @description Create a new McpApp
    #' @param ui An htmltools tag or tagList defining the UI. Can be a simple
    #'   tagList of shinymcp components, or a full [bslib::page()] with theme.
    #' @param tools A list of tool definitions (ellmer tool objects or named list)
    #' @param name App name (used in resource URIs)
    #' @param version App version string
    #' @param theme Optional bslib theme (a [bslib::bs_theme()] object). If
    #'   provided, the UI will be wrapped in a themed page. Not needed if `ui`
    #'   is already a [bslib::page()].
    #' @param csp Optional named list of Content Security Policy domain
    #'   declarations for the app's `ui://` resource, per the MCP Apps spec.
    #'   Hosts block undeclared external domains. Fields: `connect_domains`
    #'   (fetch/XHR/WebSocket origins), `resource_domains` (scripts, styles,
    #'   images, fonts), `frame_domains` (nested iframes), `base_uri_domains`.
    #'   Apps with fully inlined assets (the shinymcp default) don't need this.
    #' @param permissions Optional named list of sandbox permissions the app
    #'   needs (e.g. `list(camera = list())`). Most apps don't need this.
    #' @param prefers_border Optional logical; hint that the host should draw
    #'   a border around the embedded app.
    #' @param tool_visibility Optional named list mapping tool names to
    #'   visibility scopes per the MCP Apps spec. Each entry is a character
    #'   vector drawn from `c("model", "app")`. Use `"app"` for tools only the
    #'   UI should call (hidden from the model), `"model"` for tools the UI
    #'   should not call. Default (unset) is both.
    #' @param trigger When the UI calls tools as inputs change: `"debounce"`
    #'   (default, batches rapid changes) or `"change"` (immediate). The
    #'   `"submit"` and `"manual"` modes only apply inside shinymcp's own
    #'   Shiny host, which provides Apply/Run buttons.
    #' @param debounce_ms Debounce interval in milliseconds (default 250).
    #' @param resources Optional named list of extra resources served
    #'   alongside the app. Names are URIs; values are a string (static
    #'   content), a function returning a string (evaluated on each read,
    #'   useful for lazy-loading data into the UI via
    #'   `window.shinymcp.readResource()`), or a list with fields `content`
    #'   (string or function), `mime_type`, `name`, `description`, `meta`.
    #' @param tool_outputs Optional named list mapping tool names to the
    #'   output ids they return (e.g. `list(explore = c("scatter", "stats"))`).
    #'   Used to generate an `outputSchema` for each tool. Only declare this
    #'   for tools that return a named list keyed by those output ids.
    initialize = function(
      ui,
      tools = list(),
      name = "shinymcp-app",
      version = "0.1.0",
      theme = NULL,
      csp = NULL,
      permissions = NULL,
      prefers_border = NULL,
      tool_visibility = NULL,
      trigger = NULL,
      debounce_ms = NULL,
      resources = NULL,
      tool_outputs = NULL
    ) {
      if (!inherits(ui, c("shiny.tag", "shiny.tag.list"))) {
        rlang::abort(
          cli::format_inline(
            "{.arg ui} must be an {.cls htmltools} tag or tagList."
          ),
          class = "shinymcp_error_validation"
        )
      }
      if (!is.list(tools)) {
        rlang::abort(
          cli::format_inline("{.arg tools} must be a list."),
          class = "shinymcp_error_validation"
        )
      }

      # If a theme is provided, wrap the UI in a bslib page
      if (!is.null(theme)) {
        rlang::check_installed("bslib", reason = "for themed MCP Apps")
        ui <- bslib::page(theme = theme, ui)
      }

      if (!is.null(trigger)) {
        trigger <- rlang::arg_match0(
          trigger,
          c("debounce", "change", "submit", "manual")
        )
      }
      if (!is.null(tool_visibility)) {
        if (!is.list(tool_visibility) || is.null(names(tool_visibility))) {
          rlang::abort(
            "`tool_visibility` must be a named list (tool name -> scopes).",
            class = "shinymcp_error_validation"
          )
        }
        for (nm in names(tool_visibility)) {
          scopes <- tool_visibility[[nm]]
          if (!is.character(scopes) || !all(scopes %in% c("model", "app"))) {
            rlang::abort(
              cli::format_inline(
                "Visibility for tool {.val {nm}} must be a character vector drawn from {.val {c('model', 'app')}}."
              ),
              class = "shinymcp_error_validation"
            )
          }
        }
      }

      if (!is.null(tool_outputs)) {
        if (
          !is.list(tool_outputs) ||
            is.null(names(tool_outputs)) ||
            !all(vapply(tool_outputs, is.character, logical(1)))
        ) {
          rlang::abort(
            "`tool_outputs` must be a named list of character vectors (tool name -> output ids).",
            class = "shinymcp_error_validation"
          )
        }
      }

      self$name <- name
      self$version <- version
      private$.ui <- ui
      private$.tools <- tools
      private$.csp_meta <- csp_to_meta(csp)
      private$.permissions <- permissions
      private$.prefers_border <- prefers_border
      private$.tool_visibility <- tool_visibility
      private$.trigger <- trigger
      private$.debounce_ms <- debounce_ms
      private$.resources <- normalize_extra_resources(resources)
      private$.tool_outputs <- tool_outputs

      # A tool_visibility/tool_outputs entry naming no actual tool is a
      # silent no-op (no schema, no scoping), so surface likely typos.
      known <- private$get_tool_names()
      for (arg in c("tool_visibility", "tool_outputs")) {
        declared <- names(get(arg) %||% list())
        unknown <- setdiff(declared, known)
        if (length(unknown) > 0) {
          cli::cli_warn(
            "{.arg {arg}} names {.val {unknown}} match no tool in this app (tools: {.val {known}})."
          )
        }
      }

      invisible(self)
    },

    #' @description Generate the full HTML resource
    #' Returns a character string of the complete HTML page including
    #' UI components, bridge script, and config. HTML dependencies from
    #' bslib or other htmltools-based packages are inlined automatically.
    html_resource = function(bridge_config = NULL) {
      tool_names <- private$get_tool_names()
      tool_args <- private$get_tool_arg_names()

      config <- compact_list(list(
        appName = self$name,
        version = self$version,
        tools = I(tool_names),
        toolArgs = tool_args,
        trigger = private$.trigger,
        debounceMs = private$.debounce_ms
      ))
      if (!is.null(bridge_config)) {
        config <- utils::modifyList(config, bridge_config, keep.null = TRUE)
      }
      config_json <- to_json(config)

      bridge_js <- private$read_bridge_js()

      # Render UI to extract HTML and any dependencies (bslib, etc.)
      rendered_ui <- htmltools::renderTags(private$.ui)
      has_deps <- length(rendered_ui$dependencies) > 0

      if (has_deps) {
        # bslib/themed UI: inline all CSS/JS dependencies
        head_content <- paste(
          '<meta charset="UTF-8">',
          '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
          paste0("<title>", htmltools::htmlEscape(self$name), "</title>"),
          private$inline_dependencies(rendered_ui$dependencies),
          rendered_ui$head,
          sep = "\n"
        )
        body_content <- rendered_ui$html
      } else {
        # Simple UI: use default CSS, wrap in container
        body_tag <- htmltools::tags$div(
          id = "shinymcp-app",
          class = "shinymcp-container",
          private$.ui
        )
        rendered_body <- htmltools::renderTags(body_tag)
        head_content <- paste(
          '<meta charset="UTF-8">',
          '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
          paste0("<title>", htmltools::htmlEscape(self$name), "</title>"),
          paste0("<style>\n", private$default_css(), "\n</style>"),
          sep = "\n"
        )
        body_content <- rendered_body$html
      }

      # Assemble final HTML (built as string to avoid renderTags
      # stripping <head> content)
      paste0(
        "<!DOCTYPE html>\n",
        '<html lang="en">\n',
        "<head>\n",
        head_content,
        "\n</head>\n",
        "<body>\n",
        body_content,
        "\n",
        '<script id="shinymcp-config" type="application/json">',
        config_json,
        "</script>\n",
        "<script>\n",
        bridge_js,
        "\n</script>\n",
        "</body>\n</html>"
      )
    },

    #' @description Get tools annotated with MCP metadata
    #' Returns the tools list with `_meta.ui` added to each plain-list tool,
    #' excluding tools whose `visibility` does not include `"model"` (those
    #' are app-only: callable from the rendered UI, hidden from the model).
    #' Used by the shinychat/mcptools registration paths.
    mcp_tools = function() {
      uri <- self$resource_uri()
      tools <- Filter(
        function(tool) {
          visibility <- private$tool_visibility_for(tool)
          is.null(visibility) || "model" %in% visibility
        },
        private$.tools
      )
      lapply(tools, function(tool) {
        if (is.list(tool) && !is_ellmer_tool(tool)) {
          ui_meta <- list(resourceUri = uri)
          visibility <- private$tool_visibility_for(tool)
          if (!is.null(visibility)) {
            ui_meta$visibility <- I(visibility)
          }
          tool[["_meta"]] <- list(
            ui = ui_meta,
            `ui/resourceUri` = uri
          )
        }
        tool
      })
    },

    #' @description Get tool definitions for MCP tools/list responses
    #' Returns a list of tool definition objects suitable for JSON-RPC.
    #' Each tool includes `_meta.ui.resourceUri` linking it to the app's
    #' UI resource, which tells MCP Apps-capable hosts to render the UI.
    #' @param include_ui_meta Whether to attach the nested `_meta.ui` block
    #'   to each tool. Set to `FALSE` for clients that did not advertise the
    #'   MCP Apps extension capability. The deprecated flat
    #'   `_meta["ui/resourceUri"]` key is kept in both cases so hosts that
    #'   predate capability negotiation (SEP-1865 draft era) keep rendering;
    #'   text-only clients ignore unknown `_meta` keys per the MCP spec.
    tool_definitions = function(include_ui_meta = TRUE) {
      uri <- self$resource_uri()

      lapply(private$.tools, function(tool) {
        def <- if (is_ellmer_tool(tool)) {
          list(
            name = tool@name,
            description = tool@description %||% "",
            inputSchema = type_object_to_schema(tool@arguments)
          )
        } else if (is.list(tool)) {
          compact_list(list(
            name = tool$name %||% "unnamed",
            description = tool$description %||% "",
            inputSchema = tool$inputSchema %||%
              list(type = "object", properties = list()),
            outputSchema = tool$outputSchema
          ))
        } else {
          list(
            name = "unnamed",
            description = "",
            inputSchema = list(type = "object", properties = list())
          )
        }

        # Generate an outputSchema from declared tool_outputs. Only declared
        # tools get one: per the MCP spec a tool with an outputSchema MUST
        # return conforming structuredContent, and we can't verify that for
        # arbitrary tools (e.g. ones returning bare strings).
        if (is.null(def$outputSchema)) {
          declared_outputs <- private$.tool_outputs[[def$name]]
          if (!is.null(declared_outputs)) {
            def$outputSchema <- build_output_schema(
              declared_outputs,
              private$scan_ui_outputs()
            )
          }
        }

        if (!include_ui_meta) {
          # Client did not advertise the MCP Apps extension. Withhold the
          # nested _meta.ui block, but keep the deprecated flat key so
          # draft-era hosts (which never advertise) keep finding the UI.
          def[["_meta"]] <- list(`ui/resourceUri` = uri)
          return(def)
        }

        ui_meta <- list(resourceUri = uri)
        visibility <- private$tool_visibility_for(tool)
        if (!is.null(visibility)) {
          ui_meta$visibility <- I(visibility)
        }

        # Include both new and legacy _meta formats for compatibility.
        # The flat "ui/resourceUri" key is deprecated in the 2026-01-26 spec
        # but some hosts still normalize it.
        def[["_meta"]] <- list(
          ui = ui_meta,
          `ui/resourceUri` = uri
        )
        def
      })
    },

    #' @description Get the extra resources declared for this app
    #' Returns a named list (URI -> normalized spec with `uri`, `name`,
    #' `description`, `mime_type`, `content_fn`, `meta`) for registration
    #' alongside the app's main ui:// resource.
    extra_resources = function() {
      private$.resources
    },

    #' @description Read one extra resource by URI
    #' Returns a `resources/read` contents entry (`uri`, `mimeType`, `text`,
    #' optional `_meta`). Errors with class `shinymcp_error_resource` when
    #' the URI is not a declared extra resource.
    #' @param uri The resource URI to read
    read_extra_resource = function(uri) {
      spec <- private$.resources[[uri]]
      if (is.null(spec)) {
        shinymcp_error_resource(
          cli::format_inline("Resource not found: {.val {uri}}"),
          uri = uri
        )
      }
      compact_list(list(
        uri = spec$uri,
        mimeType = spec$mime_type,
        text = coerce_resource_text(spec$content_fn()),
        `_meta` = spec$meta
      ))
    },

    #' @description Get the `_meta` for this app's ui:// resource
    #' Returns the `_meta` list (CSP domains, permissions, prefersBorder)
    #' to attach to the resource in `resources/list` and `resources/read`
    #' responses, or `NULL` when nothing was declared.
    resource_meta = function() {
      ui_meta <- compact_list(list(
        csp = private$.csp_meta,
        permissions = private$.permissions,
        prefersBorder = private$.prefers_border
      ))
      if (length(ui_meta) == 0) {
        return(NULL)
      }
      list(ui = ui_meta)
    },

    #' @description Call a tool by name
    #' @param name Name of the tool to call
    #' @param arguments Named list of arguments to pass to the tool
    call_tool = function(name, arguments = list()) {
      tool <- NULL
      for (t in private$.tools) {
        if (identical(tool_name(t), name)) {
          tool <- t
          break
        }
      }
      if (is.null(tool)) {
        rlang::abort(
          cli::format_inline("Tool {.val {name}} not found."),
          class = "shinymcp_error_tool_not_found"
        )
      }
      if (is_ellmer_tool(tool) || is.function(tool)) {
        do.call(tool, arguments)
      } else if (is.list(tool) && is.function(tool$fun)) {
        do.call(tool$fun, arguments)
      } else {
        rlang::abort(
          cli::format_inline(
            "Tool {.val {name}} does not have a callable function."
          ),
          class = "shinymcp_error_tool_not_callable"
        )
      }
    },

    #' @description Get the ui:// resource URI for this app
    resource_uri = function() {
      paste0("ui://", self$name)
    },

    #' @description Get the app's declared interaction defaults
    #' Returns a list with `trigger` and `debounce_ms` as declared at
    #' construction (either may be `NULL` when unset). Hosts use this to
    #' defer to the app's declaration when the embedder didn't specify.
    interaction_defaults = function() {
      list(
        trigger = private$.trigger,
        debounce_ms = private$.debounce_ms
      )
    },

    #' @description Print method
    #' @param ... Ignored.
    print = function(...) {
      cli::cli_h1("McpApp: {self$name}")
      cli::cli_text("Version: {self$version}")
      cli::cli_text("Resource URI: {self$resource_uri()}")
      n_tools <- length(private$.tools)
      cli::cli_text("Tools: {n_tools}")
      invisible(self)
    }
  ),
  private = list(
    .ui = NULL,
    .tools = list(),
    .csp_meta = NULL,
    .permissions = NULL,
    .prefers_border = NULL,
    .tool_visibility = NULL,
    .trigger = NULL,
    .debounce_ms = NULL,
    .resources = list(),
    .tool_outputs = NULL,
    .ui_outputs = NULL,

    # Resolve a tool's visibility: app-level tool_visibility wins, then a
    # plain-list tool's own `visibility` field. NULL means default (both).
    tool_visibility_for = function(tool) {
      private$.tool_visibility[[tool_name(tool)]] %||%
        (if (!is_ellmer_tool(tool) && is.list(tool)) tool$visibility)
    },

    # Scan the rendered UI for output elements and their declared types.
    # Returns a named character vector: output id -> type. Cached.
    scan_ui_outputs = function() {
      if (!is.null(private$.ui_outputs)) {
        return(private$.ui_outputs)
      }
      html <- htmltools::renderTags(private$.ui)$html
      result <- character(0)
      # Match each element carrying data-shinymcp-output, then pull the
      # type attribute out of the same tag.
      starts <- gregexpr("<[^>]*data-shinymcp-output=\"[^\"]*\"[^>]*>", html)[[1]]
      if (starts[1] != -1) {
        lengths <- attr(starts, "match.length")
        for (i in seq_along(starts)) {
          tag <- substr(html, starts[i], starts[i] + lengths[i] - 1)
          id <- sub(
            '.*data-shinymcp-output="([^"]*)".*',
            "\\1",
            tag
          )
          type <- if (grepl('data-shinymcp-output-type="', tag, fixed = TRUE)) {
            sub('.*data-shinymcp-output-type="([^"]*)".*', "\\1", tag)
          } else {
            "text"
          }
          result[[id]] <- type
        }
      }
      private$.ui_outputs <- result
      result
    },

    # Inline HTML dependencies as <style> and <script> tags.
    inline_dependencies = function(deps) {
      parts <- character(0)
      for (dep in deps) {
        base_path <- dep$src$file
        if (is.null(base_path) || !nzchar(base_path)) {
          next
        }

        # Inline stylesheets
        for (css in dep$stylesheet) {
          css_path <- file.path(base_path, css)
          if (file.exists(css_path)) {
            content <- paste(readLines(css_path, warn = FALSE), collapse = "\n")
            parts <- c(
              parts,
              paste0(
                "<style>/* ",
                dep$name,
                ": ",
                css,
                " */\n",
                content,
                "\n</style>"
              )
            )
          }
        }

        # Inline scripts
        for (js_entry in dep$script) {
          js_file <- if (is.list(js_entry)) js_entry$src else js_entry
          js_path <- file.path(base_path, js_file)
          if (file.exists(js_path)) {
            content <- paste(readLines(js_path, warn = FALSE), collapse = "\n")
            # Preserve type="module" if specified
            type_attr <- ""
            if (is.list(js_entry) && !is.null(js_entry$type)) {
              type_attr <- paste0(' type="', js_entry$type, '"')
            }
            parts <- c(
              parts,
              paste0(
                "<script",
                type_attr,
                ">/* ",
                dep$name,
                ": ",
                js_file,
                " */\n",
                content,
                "\n</script>"
              )
            )
          }
        }
      }
      paste(parts, collapse = "\n")
    },

    # Read the bridge JS file.
    read_bridge_js = function() {
      js_path <- system.file(
        "js",
        "shinymcp-bridge.js",
        package = "shinymcp",
        mustWork = FALSE
      )
      if (nzchar(js_path) && file.exists(js_path)) {
        paste(readLines(js_path, warn = FALSE), collapse = "\n")
      } else {
        cli::cli_warn(
          "Bridge JS file not found. The MCP App will not have bridge functionality."
        )
        "/* shinymcp-bridge.js not found */"
      }
    },

    # Extract tool names from the tools list.
    get_tool_names = function() {
      vapply(
        private$.tools,
        tool_name,
        character(1),
        USE.NAMES = FALSE
      )
    },

    # Extract argument names from each tool.
    # Returns a named list: tool_name -> character vector of arg names.
    get_tool_arg_names = function() {
      result <- list()
      for (tool in private$.tools) {
        name <- tool_name(tool)
        args <- if (is_ellmer_tool(tool)) {
          names(tool@arguments@properties)
        } else if (is.list(tool) && !is.null(tool$inputSchema$properties)) {
          names(tool$inputSchema$properties)
        } else if (is.list(tool) && is.function(tool$fun)) {
          names(formals(tool$fun))
        } else if (is.function(tool)) {
          names(formals(tool))
        } else {
          character(0)
        }
        result[[name]] <- I(args)
      }
      result
    },

    # Default CSS for shinymcp components.
    default_css = function() {
      paste(
        "*, *::before, *::after { box-sizing: border-box; }",
        "body { margin: 0; padding: 16px; font-family: system-ui, -apple-system, sans-serif; font-size: 14px; line-height: 1.5; color: #1a1a1a; }",
        ".shinymcp-container { display: flex; flex-direction: column; gap: 16px; max-width: 800px; margin: 0 auto; }",
        ".shinymcp-input-group { display: flex; flex-direction: column; gap: 4px; }",
        ".shinymcp-input-group label { font-weight: 600; font-size: 13px; }",
        ".shinymcp-input-group select, .shinymcp-input-group input[type='text'], .shinymcp-input-group input[type='number'] { padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px; }",
        ".shinymcp-input-group input[type='range'] { width: 100%; }",
        ".shinymcp-input-group button { padding: 8px 16px; border: none; border-radius: 4px; background: #0066cc; color: white; font-size: 14px; cursor: pointer; }",
        ".shinymcp-input-group button:hover { background: #0052a3; }",
        ".shinymcp-output { border: 1px solid #e0e0e0; border-radius: 4px; padding: 12px; min-height: 40px; background: #fafafa; }",
        # Dark mode: the bridge sets data-bs-theme from the host's theme
        ":root[data-bs-theme='dark'] body { color: #e6e6e6; background: #212529; }",
        ":root[data-bs-theme='dark'] .shinymcp-input-group select, :root[data-bs-theme='dark'] .shinymcp-input-group input[type='text'], :root[data-bs-theme='dark'] .shinymcp-input-group input[type='number'] { background: #2b3035; color: #e6e6e6; border-color: #495057; }",
        ":root[data-bs-theme='dark'] .shinymcp-output { background: #2b3035; border-color: #495057; }",
        sep = "\n"
      )
    }
  )
)


#' Create an MCP App
#'
#' Convenience function to create an [McpApp] object.
#'
#' @param ui UI definition (htmltools tags). Can be a simple
#'   [htmltools::tagList()] of shinymcp components, or a full
#'   [bslib::page()] with theme.
#' @param tools List of tools
#' @param name App name
#' @param version App version
#' @param theme Optional [bslib::bs_theme()] object. Supports
#'   `brand` for [brand.yml](https://posit-dev.github.io/brand-yml/) theming.
#'   Not needed if `ui` is already a [bslib::page()].
#' @param csp Optional named list of Content Security Policy domain
#'   declarations for the app's `ui://` resource, per the MCP Apps spec.
#'   MCP hosts apply a restrictive default policy that blocks all external
#'   network access and assets, so any domain your app loads from at runtime
#'   must be declared here. Fields (snake_case or spec camelCase):
#'   * `connect_domains`: origins for fetch/XHR/WebSocket requests
#'   * `resource_domains`: origins for scripts, styles, images, fonts
#'   * `frame_domains`: origins for nested iframes
#'   * `base_uri_domains`: allowed `base-uri` values
#'
#'   Apps with fully inlined assets (the shinymcp default) don't need this.
#' @param permissions Optional named list of iframe permissions the app
#'   needs, e.g. `list(camera = list())`. Most apps don't need this.
#' @param prefers_border Optional logical hint that the host should draw a
#'   border around the embedded app.
#' @param tool_visibility Optional named list mapping tool names to MCP Apps
#'   visibility scopes (character vectors drawn from `c("model", "app")`).
#'   Use `"app"` for tools only the rendered UI should call (hidden from the
#'   model's tool list), `"model"` for tools the UI must not call. Unset
#'   tools are visible to both.
#' @param trigger When the UI calls tools as inputs change: `"debounce"`
#'   (default) or `"change"`. `"submit"`/`"manual"` only apply inside
#'   shinymcp's own Shiny host.
#' @param debounce_ms Debounce interval in milliseconds (default 250).
#' @param resources Optional named list of extra resources served alongside
#'   the app, readable from the UI via `window.shinymcp.readResource(uri)`.
#'   Names are URIs; values are a string (static content), a function
#'   returning a string (evaluated on each read --- useful for lazy-loading
#'   data instead of inlining it into the app HTML), or a list with fields
#'   `content`, `mime_type` (default `"text/plain"`), `name`, `description`,
#'   and `meta`. For example:
#'   `resources = list("ui://my-app/data" = list(content = function() jsonlite::toJSON(mtcars), mime_type = "application/json"))`
#' @param tool_outputs Optional named list mapping tool names to the output
#'   ids they return, e.g. `list(explore = c("scatter", "stats"))`. Declared
#'   tools get an auto-generated `outputSchema` (all properties are strings,
#'   with descriptions derived from the matching UI output types). Only
#'   declare tools that return a named list keyed by those output ids.
#' @param ... Additional arguments passed to `McpApp$new()`
#' @return An [McpApp] object
#' @export
mcp_app <- function(
  ui,
  tools = list(),
  name = "shinymcp-app",
  version = "0.1.0",
  theme = NULL,
  csp = NULL,
  permissions = NULL,
  prefers_border = NULL,
  tool_visibility = NULL,
  trigger = NULL,
  debounce_ms = NULL,
  resources = NULL,
  tool_outputs = NULL,
  ...
) {
  McpApp$new(
    ui = ui,
    tools = tools,
    name = name,
    version = version,
    theme = theme,
    csp = csp,
    permissions = permissions,
    prefers_border = prefers_border,
    tool_visibility = tool_visibility,
    trigger = trigger,
    debounce_ms = debounce_ms,
    resources = resources,
    tool_outputs = tool_outputs,
    ...
  )
}
