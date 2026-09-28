# Set a tool result's text and data explicitly

By default the text a model reads from a tool result is assembled from
the outputs, and the structured content is each output's model value.
Wrap a tool's outputs in `mcp_tool_result()` to write those yourself,
for example to lead with record identifiers the model should quote back:

## Usage

``` r
mcp_tool_result(..., text = NULL, data = NULL, error = FALSE)
```

## Arguments

- ...:

  Outputs, named by output id, as in a tool's usual return list.

- text:

  Text for the model and for hosts that only show text. Replaces the
  text assembled from the outputs.

- data:

  A named list sent as the result's structured content. Replaces the
  default of one entry per output.

- error:

  If `TRUE`, the result is marked as a tool error. Use it for failures
  the model should see and react to.

## Value

An object a tool can return.

## Details

    mcp_tool_result(
      proposal = mcp_result_table(batches),
      text = "Proposal P-3 drafted for campaign C-014: six batches.",
      data = list(campaign = "C-014", proposal = "P-3", revision = 47)
    )

## See also

Other writing tools:
[`mcp_request()`](https://jameshwade.github.io/shinymcp/reference/mcp_request.md),
[`mcp_result`](https://jameshwade.github.io/shinymcp/reference/mcp_result.md)
