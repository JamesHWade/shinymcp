# A tool first, with a UI on top.
#
# `sample_size` is an ordinary typed tool: any MCP client can call it and
# read the answer, with or without MCP Apps support. Clients that do
# support apps also show the calculator, and the person can try other
# designs in it without another round trip through the model.
#
# The result has three parts, each for a different reader:
#   - text, for the model and for clients that can't show the app;
#   - `data`, the structured answer the model works with;
#   - the outputs (text, plot, table) that fill the app's placeholders.
#
# Preview it:
#   shinymcp::preview_app(system.file("examples", "sample-size", "app.R", package = "shinymcp"))

library(shiny)
library(bslib)
library(shinymcp)

ui <- page_fillable(
  layout_columns(
    col_widths = c(4, 8),
    card(
      card_header("Design"),
      numericInput(
        "delta",
        "Difference to detect",
        0.5,
        min = 0.01,
        step = 0.05
      ),
      numericInput("sd", "Standard deviation", 1, min = 0.01, step = 0.1),
      sliderInput(
        "power",
        "Power",
        min = 0.5,
        max = 0.99,
        value = 0.8,
        step = 0.01
      ),
      radioButtons(
        "alpha",
        "Significance level",
        c("0.01", "0.05", "0.1"),
        selected = "0.05",
        inline = TRUE
      )
    ),
    card(
      card_header("Sample size"),
      mcp_text("answer"),
      mcp_plot("curve", height = 300),
      mcp_table("options")
    )
  )
)

sample_size <- ellmer::tool(
  function(delta, sd, power = 0.8, alpha = 0.05) {
    n <- ceiling(
      stats::power.t.test(
        delta = delta,
        sd = sd,
        power = power,
        sig.level = alpha
      )$n
    )
    sizes <- unique(round(seq(2, max(2 * n, 10), length.out = 60)))
    curve <- stats::power.t.test(
      n = sizes,
      delta = delta,
      sd = sd,
      sig.level = alpha
    )$power
    targets <- c(0.7, 0.8, 0.9, 0.95)
    options <- data.frame(
      Power = sprintf("%.0f%%", 100 * targets),
      `Per group` = vapply(
        targets,
        function(p) {
          ceiling(
            stats::power.t.test(
              delta = delta,
              sd = sd,
              power = p,
              sig.level = alpha
            )$n
          )
        },
        numeric(1)
      ),
      check.names = FALSE
    )
    options$Total <- 2 * options$`Per group`

    mcp_tool_result(
      answer = sprintf(
        "%d per group, %d in total, to detect a difference of %s (SD %s) with %s power at a %s significance level.",
        n,
        2 * n,
        delta,
        sd,
        sprintf("%.0f%%", 100 * power),
        alpha
      ),
      curve = mcp_result_plot(
        function() {
          par(mar = c(4, 4, 1, 1))
          plot(
            sizes,
            curve,
            type = "l",
            lwd = 2,
            col = "#2f6f9f",
            xlab = "Participants per group",
            ylab = "Power",
            ylim = c(0, 1),
            las = 1
          )
          abline(h = power, v = n, lty = 2, col = "grey55")
        },
        text = "Power curve against participants per group."
      ),
      options = options,
      data = list(
        n_per_group = n,
        total = 2 * n,
        delta = delta,
        sd = sd,
        power = power,
        alpha = alpha
      )
    )
  },
  name = "sample_size",
  description = paste(
    "Participants needed per group for a two-sample t-test",
    "to detect a difference in means with the given power."
  ),
  arguments = list(
    delta = ellmer::type_number(
      "Difference in means to detect, in the outcome's units."
    ),
    sd = ellmer::type_number(
      "Standard deviation of the outcome, assumed equal in both groups."
    ),
    power = ellmer::type_number(
      "Chance of detecting the difference, between 0 and 1. Default 0.8.",
      required = FALSE
    ),
    alpha = ellmer::type_number(
      "Two-sided significance level. Default 0.05.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    title = "Sample size",
    read_only_hint = TRUE,
    idempotent_hint = TRUE,
    open_world_hint = FALSE
  )
)

app <- mcp_app(
  ui,
  tools = list(sample_size),
  name = "sample-size",
  title = "Sample size calculator"
)

if (interactive()) {
  preview_app(app)
} else {
  serve(app)
}
