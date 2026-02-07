# Parse a Shiny app into intermediate representation

Reads a Shiny app's R source files and extracts a structured
representation of UI inputs, outputs, and server logic.

## Usage

``` r
parse_shiny_app(path)
```

## Arguments

- path:

  Path to a Shiny app directory (containing app.R or ui.R/server.R)

## Value

A `ShinyAppIR` list with components: `inputs`, `outputs`, `server_body`,
`reactives`, `observers`, `complexity`
