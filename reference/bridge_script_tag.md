# The bridge script as an HTML tag

`bridge_script_tag()` and `bridge_config_tag()` are for pages built by
hand: include both, the config first, at the end of `<body>`.
[`mcp_app()`](https://jameshwade.github.io/shinymcp/reference/mcp_app.md)
adds them for you, so most apps never need these.

## Usage

``` r
bridge_script_tag()

bridge_config_tag(config)
```

## Arguments

- config:

  A named list: the bridge configuration. At minimum `app` (a name) and
  `tools`, a list of `list(name =, args =)` records.

## Value

An htmltools `<script>` tag.
