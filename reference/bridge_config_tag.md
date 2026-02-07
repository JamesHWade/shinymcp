# Bridge config tag

Returns an
[htmltools::tags](https://rstudio.github.io/htmltools/reference/builder.html)
`<script>` element containing the JSON configuration for the shinymcp
bridge. The element has `id="shinymcp-config"` and
`type="application/json"` so the bridge JavaScript can read it on
initialization.

## Usage

``` r
bridge_config_tag(config)
```

## Arguments

- config:

  A list as returned by `bridge_config()`, or any named list that should
  be serialized as the bridge configuration.

## Value

An `htmltools::tags$script` HTML tag.
