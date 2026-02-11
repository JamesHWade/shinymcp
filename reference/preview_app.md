# Preview an MCP App in a web browser

Starts a local HTTP server and opens the MCP App in a browser. A
lightweight host page emulates the MCP Apps postMessage protocol so that
tools are fully functional — inputs trigger tool calls, and outputs
update in real time, just like they would inside Claude Desktop.

## Usage

``` r
preview_app(app, port = NULL, launch = TRUE)
```

## Arguments

- app:

  An [McpApp](https://jameshwade.github.io/shinymcp/reference/McpApp.md)
  object, or a path to a directory containing an MCP App `app.R` (which
  will be [`source()`](https://rdrr.io/r/base/source.html)d to obtain
  the app object).

- port:

  Port for the local server. `NULL` (the default) picks a random
  available port.

- launch:

  Whether to open the browser automatically (default `TRUE`).

## Value

Invisibly, a list with `url` (the preview URL) and
[`stop()`](https://rdrr.io/r/base/stop.html) (a function to shut down
the server).

## Examples

``` r
if (FALSE) { # \dontrun{
app <- mcp_app(
  ui = htmltools::tags$div(
    mcp_text_input("name", "Your name"),
    mcp_text("greeting")
  ),
  tools = list(
    list(
      name = "greet",
      fun = function(name = "world") {
        list(greeting = paste0("Hello, ", name, "!"))
      }
    )
  )
)

# Opens in browser with working inputs/outputs
srv <- preview_app(app)

# Stop when done
srv$stop()
} # }
```
