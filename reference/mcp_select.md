# Create an MCP select input

Generates a dropdown select element with MCP data attributes.

## Usage

``` r
mcp_select(id, label, choices, selected = choices[[1]])
```

## Arguments

- id:

  Input ID

- label:

  Display label

- choices:

  Character vector of choices. If named, names are used as display
  labels and values as the option values.

- selected:

  The initially selected value. Defaults to the first choice.

## Value

An
[htmltools::tag](https://rstudio.github.io/htmltools/reference/builder.html)
object
