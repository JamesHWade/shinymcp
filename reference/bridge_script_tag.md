# Bridge script tag

Returns an
[htmltools::tags](https://rstudio.github.io/htmltools/reference/builder.html)
`<script>` element that inlines the shinymcp JavaScript bridge. Include
this in your HTML page to enable the MCP Apps postMessage/JSON-RPC
protocol.

## Usage

``` r
bridge_script_tag()
```

## Value

An `htmltools::tags$script` HTML tag.
