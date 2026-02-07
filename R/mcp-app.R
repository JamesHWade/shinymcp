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
    #' @param ui An htmltools tag or tagList defining the UI
    #' @param tools A list of tool definitions (ellmer tool objects or named list)
    #' @param name App name (used in resource URIs)
    #' @param version App version string
    initialize = function(
      ui,
      tools = list(),
      name = "shinymcp-app",
      version = "0.1.0"
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

      self$name <- name
      self$version <- version
      private$.ui <- ui
      private$.tools <- tools

      invisible(self)
    },

    #' @description Generate the full HTML resource
    #' Returns a character string of the complete HTML page including
    #' UI components, bridge script, and config.
    html_resource = function() {
      tool_names <- private$get_tool_names()

      bridge_config <- to_json(list(
        appName = self$name,
        version = self$version,
        tools = tool_names
      ))

      config_tag <- htmltools::tags$script(
        id = "shinymcp-config",
        type = "application/json",
        htmltools::HTML(bridge_config)
      )

      bridge_js <- private$read_bridge_js()
      bridge_tag <- htmltools::tags$script(htmltools::HTML(bridge_js))

      page <- htmltools::tags$html(
        lang = "en",
        htmltools::tags$head(
          htmltools::tags$meta(charset = "UTF-8"),
          htmltools::tags$meta(
            name = "viewport",
            content = "width=device-width, initial-scale=1.0"
          ),
          htmltools::tags$title(self$name),
          htmltools::tags$style(htmltools::HTML(private$default_css()))
        ),
        htmltools::tags$body(
          htmltools::tags$div(
            id = "shinymcp-app",
            class = "shinymcp-container",
            private$.ui
          ),
          config_tag,
          bridge_tag
        )
      )

      rendered <- htmltools::renderTags(page)
      paste0("<!DOCTYPE html>\n", rendered$html)
    },

    #' @description Get tools annotated with MCP metadata
    #' Returns the tools list with _meta.ui.resourceUri added to each tool.
    mcp_tools = function() {
      uri <- self$resource_uri()
      lapply(private$.tools, function(tool) {
        if (inherits(tool, "ToolDef")) {
          tool$extra <- c(
            tool$extra,
            list(
              `_meta` = list(ui = list(resourceUri = uri))
            )
          )
        } else if (is.list(tool)) {
          tool[["_meta"]] <- list(ui = list(resourceUri = uri))
        }
        tool
      })
    },

    #' @description Get tool definitions for MCP tools/list responses
    #' Returns a list of tool definition objects suitable for JSON-RPC.
    tool_definitions = function() {
      lapply(private$.tools, function(tool) {
        if (inherits(tool, "ToolDef")) {
          list(
            name = tool$name,
            description = tool$description %||% "",
            inputSchema = tool$schema %||%
              list(type = "object", properties = list())
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
        name <- if (inherits(t, "ToolDef")) t$name else t$name
        if (identical(name, tool_name)) {
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
      if (inherits(tool, "ToolDef")) {
        do.call(tool$fun, arguments)
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
        function(tool) {
          if (inherits(tool, "ToolDef")) {
            tool$name %||% "unnamed"
          } else if (is.list(tool) && !is.null(tool$name)) {
            tool$name
          } else {
            "unnamed"
          }
        },
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
#' @param ui UI definition (htmltools tags)
#' @param tools List of tools
#' @param name App name
#' @param version App version
#' @param ... Additional arguments passed to `McpApp$new()`
#' @return An [McpApp] object
#' @export
mcp_app <- function(
  ui,
  tools = list(),
  name = "shinymcp-app",
  version = "0.1.0",
  ...
) {
  McpApp$new(ui = ui, tools = tools, name = name, version = version, ...)
}
