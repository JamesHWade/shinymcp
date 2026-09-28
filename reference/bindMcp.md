# Choose what the model sees of a Shiny app

In a Shiny app served with
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
every input becomes an argument of the app's tool and every output is
reported to the model. Mark some of them with `bindMcp()` and only the
marked ones are: the model gets a smaller tool that is easier to use
well. The person using the app still sees all of it.

    ui <- fluidPage(
      selectInput("species", "Species", species) |> bindMcp(),
      sliderInput("alpha", "Point opacity", 0, 1, 0.7),
      plotOutput("scatter") |> bindMcp(),
      verbatimTextOutput("debug")
    )

Here the model can set the species and reads the plot; the opacity
slider and the debug output stay between the app and its user. Action
buttons are only pressed by the model when marked.

In a UI for
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md),
`bindMcp()` marks an element as an input or an output of the app's tools
when shinymcp can't tell on its own.

`bindMcp()` recognizes Shiny's and bslib's inputs and outputs, and
htmlwidget outputs. For anything else, give `type`. Marking an element
twice does nothing.

## Usage

``` r
bindMcp(tag, ...)

# S3 method for class 'shiny.tag'
bindMcp(tag, id = NULL, type = NULL, ...)

# S3 method for class 'shiny.tag.list'
bindMcp(tag, id = NULL, type = NULL, ...)

# Default S3 method
bindMcp(tag, ...)
```

## Arguments

- tag:

  A tag or tag list from a Shiny input or output function.

- ...:

  Unused.

- id:

  The id to use, when it isn't the element's own.

- type:

  For outputs: `"text"`, `"html"`, `"plot"`, `"table"`, `"image"`, or
  `"widget"`. Usually detected; required to mark an element shinymcp
  doesn't recognize.

## Value

`tag`, marked.

## Shiny's own MCP support

Shiny is gaining MCP support of its own
(<https://github.com/rstudio/shiny/pull/4407>). Once it is released, it
will be the way to put a live Shiny app in a chat, and shinymcp will
stop serving live apps.
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
[`mcp_endpoint()`](https://jameshwade.github.io/shinymcp/reference/mcp_endpoint.md),
and
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)
will take only apps built from tools, and `bindMcp()` and the helpers
for server functions
([`mcp_model_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_model_context.md),
[`mcp_host_context()`](https://jameshwade.github.io/shinymcp/reference/mcp_host_context.md),
and the rest) will be removed. For something the model should be able to
use on its own, rewrite that part of the app as tools with
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md);
see
[`vignette("rewriting-as-tools")`](https://jameshwade.github.io/shinymcp/articles/rewriting-as-tools.md).

## See also

Other apps:
[`McpApp`](https://jameshwade.github.io/shinymcp/reference/McpApp.md),
[`as_mcp_app()`](https://jameshwade.github.io/shinymcp/reference/as_mcp_app.md),
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md),
[`mcp_tool_module()`](https://jameshwade.github.io/shinymcp/reference/mcp_tool_module.md)

## Examples

``` r
shiny::selectInput("species", "Species", c("Adelie", "Gentoo")) |>
  bindMcp()
#> <div class="form-group shiny-input-container">
#>   <label class="control-label" id="species-label" for="species">Species</label>
#>   <div>
#>     <select id="species" class="shiny-input-select" data-shinymcp-input="species"><option value="Adelie" selected>Adelie</option>
#> <option value="Gentoo">Gentoo</option></select>
#>     <script type="application/json" data-for="species" data-nonempty="">{"plugins":["selectize-plugin-a11y"]}</script>
#>   </div>
#> </div>
```
