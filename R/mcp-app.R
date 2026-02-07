# McpApp R6 class - bundles UI + tools into a servable MCP App

#' MCP App
#'
#' An R6 class that bundles UI components and tools into a servable MCP App.
#' The app generates HTML with an embedded JS bridge and provides tools
#' annotated with resource URIs for MCP consumption.
#'
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
    initialize = function(
      ui,
      tools = list(),
      name = "shinymcp-app",
      version = "0.1.0",
      theme = NULL
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

      self$name <- name
      self$version <- version
      private$.ui <- ui
      private$.tools <- tools

      invisible(self)
    },

    #' @description Generate the full HTML resource
    #' Returns a character string of the complete HTML page including
    #' UI components, bridge script, and config. HTML dependencies from
    #' bslib or other htmltools-based packages are inlined automatically.
    html_resource = function() {
      tool_names <- private$get_tool_names()

      config_json <- to_json(list(
        appName = self$name,
        version = self$version,
        tools = tool_names
      ))

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
        "<head>\n", head_content, "\n</head>\n",
        "<body>\n",
        body_content, "\n",
        '<script id="shinymcp-config" type="application/json">',
        config_json, "</script>\n",
        "<script>\n", bridge_js, "\n</script>\n",
        "</body>\n</html>"
      )
    },

    #' @description Get tools annotated with MCP metadata
    #' Returns the tools list with _meta.ui.resourceUri added to each tool.
    mcp_tools = function() {
      uri <- self$resource_uri()
      lapply(private$.tools, function(tool) {
        if (is.list(tool)) {
          tool[["_meta"]] <- list(ui = list(resourceUri = uri))
        }
        tool
      })
    },

    #' @description Get tool definitions for MCP tools/list responses
    #' Returns a list of tool definition objects suitable for JSON-RPC.
    tool_definitions = function() {
      lapply(private$.tools, function(tool) {
        if (is_ellmer_tool(tool)) {
          list(
            name = tool@name,
            description = tool@description %||% "",
            inputSchema = type_object_to_schema(tool@arguments)
          )
        } else if (is.list(tool)) {
          list(
            name = tool$name %||% "unnamed",
            description = tool$description %||% "",
            inputSchema = tool$inputSchema %||%
              list(type = "object", properties = list())
          )
        } else {
          list(
            name = "unnamed",
            description = "",
            inputSchema = list(type = "object", properties = list())
          )
        }
      })
    },

    #' @description Call a tool by name
    #' @param tool_name Name of the tool to call
    #' @param arguments Named list of arguments to pass to the tool
    call_tool = function(tool_name, arguments = list()) {
      tool <- NULL
      for (t in private$.tools) {
        if (identical(tool_name(t), tool_name)) {
          tool <- t
          break
        }
      }
      if (is.null(tool)) {
        rlang::abort(
          cli::format_inline("Tool {.val {tool_name}} not found."),
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
            "Tool {.val {tool_name}} does not have a callable function."
          ),
          class = "shinymcp_error_tool_not_callable"
        )
      }
    },

    #' @description Get the ui:// resource URI for this app
    resource_uri = function() {
      paste0("ui://", self$name)
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

    #' Inline HTML dependencies as <style> and <script> tags
    #' @param deps List of htmlDependency objects
    #' @return Character string of inlined CSS and JS tags
    inline_dependencies = function(deps) {
      parts <- character(0)
      for (dep in deps) {
        base_path <- dep$src$file
        if (is.null(base_path) || !nzchar(base_path)) next

        # Inline stylesheets
        for (css in dep$stylesheet) {
          css_path <- file.path(base_path, css)
          if (file.exists(css_path)) {
            content <- paste(readLines(css_path, warn = FALSE), collapse = "\n")
            parts <- c(parts, paste0(
              "<style>/* ", dep$name, ": ", css, " */\n", content, "\n</style>"
            ))
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
            parts <- c(parts, paste0(
              "<script", type_attr, ">/* ", dep$name, ": ", js_file,
              " */\n", content, "\n</script>"
            ))
          }
        }
      }
      paste(parts, collapse = "\n")
    },

    #' Read the bridge JS file
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

    #' Extract tool names from the tools list
    get_tool_names = function() {
      vapply(
        private$.tools,
        tool_name,
        character(1),
        USE.NAMES = FALSE
      )
    },

    #' Default CSS for shinymcp components
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
#' @param ... Additional arguments passed to `McpApp$new()`
#' @return An [McpApp] object
#' @export
mcp_app <- function(
  ui,
  tools = list(),
  name = "shinymcp-app",
  version = "0.1.0",
  theme = NULL,
  ...
) {
  McpApp$new(
    ui = ui, tools = tools, name = name, version = version,
    theme = theme, ...
  )
}
