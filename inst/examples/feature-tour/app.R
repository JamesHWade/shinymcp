# Feature Tour - MCP Apps protocol features in one app
#
# This is "level 4" of the shinymcp example ladder (see vignette("use-cases")).
# It demonstrates the protocol features beyond inputs-and-outputs:
#
#   1. tool_visibility  - an app-only tool the model never sees
#   2. resources        - lazy-loaded data via window.shinymcp.readResource()
#   3. tool_outputs     - a declared outputSchema for the analysis tool
#   4. prefers_border   - resource _meta hints for the host
#   5. window.shinymcp  - sendMessage / openLink / requestDisplayMode
#   6. theme syncing    - the card follows the host's light/dark mode
#
# Run it locally with a reference host:
#   source(system.file("examples", "feature-tour", "app.R", package = "shinymcp"))
#   # interactive sessions open preview_app(); watch the protocol log
#   # (bottom-right toggle) while you interact
#
# Or serve it to Claude Desktop: Rscript this file.

library(shinymcp)
library(bslib)
library(htmltools)

# ---- Synthetic data ---------------------------------------------------------

set.seed(42)
regions <- c("North", "South", "East", "West")
sales <- expand.grid(region = regions, month = month.abb, stringsAsFactors = FALSE)
sales$units <- round(runif(nrow(sales), 80, 240))
sales$revenue <- round(sales$units * runif(nrow(sales), 90, 140))

region_notes <- list(
  North = "Mature region; renewals dominate.",
  South = "Fast-growing; two new distributors onboarded this year.",
  East = "Seasonal demand peaks in Q4.",
  West = "Pilot pricing experiment running since March."
)

# ---- UI ---------------------------------------------------------------------

# Custom JS for the window.shinymcp API. Inline scripts in the body run
# before the bridge script (which shinymcp appends at the end of <body>),
# so anything that talks to the bridge waits for it to appear.
tour_js <- HTML(
  "
  function whenBridgeReady(cb) {
    if (window.shinymcp) return cb();
    setTimeout(function () { whenBridgeReady(cb); }, 50);
  }

  // 2. Lazy resources: fetch the region catalog through the host instead of
  //    inlining it into this HTML. Works in Claude, preview_app(), and the
  //    Shiny host alike - the request is proxied to the same R process.
  whenBridgeReady(function () {
    window.shinymcp
      .readResource('ui://feature-tour/region-notes')
      .then(function (result) {
        var notes = JSON.parse(result.contents[0].text);
        var list = document.getElementById('region-notes');
        list.innerHTML = '';
        Object.keys(notes).forEach(function (region) {
          var li = document.createElement('li');
          li.textContent = region + ' - ' + notes[region];
          list.appendChild(li);
        });
      })
      .catch(function (err) {
        document.getElementById('region-notes').textContent =
          'readResource failed: ' + err.message;
      });

    // 6. Theme syncing: the bridge sets data-bs-theme from the host's theme.
    //    Show the live value so the effect is visible.
    var badge = document.getElementById('theme-badge');
    function refreshTheme() {
      badge.textContent =
        'host theme: ' +
        (document.documentElement.getAttribute('data-bs-theme') || 'light');
    }
    refreshTheme();
    new MutationObserver(refreshTheme).observe(document.documentElement, {
      attributes: true, attributeFilter: ['data-bs-theme']
    });
  });

  // 1. App-only tool: this button calls a tool that is hidden from the
  //    model (visibility 'app'). Row-level detail stays available to the
  //    user without ever appearing in the model's tool list.
  //    The argument is named detail_region (not region) on purpose: the
  //    bridge auto-wires tool args whose names match input ids, and this
  //    tool should only run when the user asks for it.
  function loadDetail() {
    var region = document.getElementById('region').value;
    window.shinymcp
      .callTool('fetch_region_detail', { detail_region: region })
      .then(function (result) {
        document.getElementById('detail').innerHTML =
          result.structuredContent.detail;
      })
      .catch(function (err) {
        document.getElementById('detail').textContent = err.message;
      });
  }

  // 5. Host interactions: chat, links, and display mode through the spec
  //    methods. Hosts that don't implement one reject the Promise.
  function askAssistant() {
    var region = document.getElementById('region').value;
    window.shinymcp.sendMessage(
      'Please summarize the ' + region + ' region and suggest one action.'
    );
  }
  function openDocs() {
    window.shinymcp.openLink('https://jameshwade.github.io/shinymcp/');
  }
  function goFullscreen() {
    window.shinymcp.requestDisplayMode('fullscreen');
  }
  "
)

ui <- page_sidebar(
  theme = bs_theme(preset = "shiny"),
  title = "shinymcp Feature Tour",
  sidebar = sidebar(
    width = 280,
    # Native input, auto-detected: id "region" matches the tool argument
    shiny::selectInput("region", "Region", regions),
    shiny::selectInput("metric", "Metric", c("units", "revenue")),
    tags$small(
      id = "theme-badge",
      class = "text-muted",
      "host theme: light"
    ),
    tags$hr(),
    # window.shinymcp host interactions
    tags$button(
      class = "btn btn-sm btn-outline-primary w-100 mb-1",
      onclick = "askAssistant()",
      "Ask assistant about this region"
    ),
    tags$button(
      class = "btn btn-sm btn-outline-secondary w-100 mb-1",
      onclick = "openDocs()",
      "Open shinymcp docs"
    ),
    tags$button(
      class = "btn btn-sm btn-outline-secondary w-100",
      onclick = "goFullscreen()",
      "Fullscreen"
    )
  ),
  card(
    card_header("Monthly trend"),
    mcp_plot("trend", height = "300px")
  ),
  layout_columns(
    card(
      card_header("Summary (model-facing tool)"),
      mcp_text("summary")
    ),
    card(
      card_header("Detail rows (app-only tool)"),
      tags$div(id = "detail", class = "text-muted", "Press the button below."),
      tags$button(
        class = "btn btn-sm btn-outline-primary mt-2",
        onclick = "loadDetail()",
        "Load region detail"
      )
    )
  ),
  card(
    card_header("Region catalog (lazy resource)"),
    tags$ul(id = "region-notes", tags$li(class = "text-muted", "Loading..."))
  ),
  tags$script(tour_js)
)

# ---- Tools ------------------------------------------------------------------

tools <- list(
  # Model-facing analysis tool: plot + text keyed by output ids.
  ellmer::tool(
    fun = function(region = "North", metric = "units") {
      slice <- sales[sales$region == region, ]
      values <- slice[[metric]]

      tmp <- tempfile(fileext = ".png")
      grDevices::png(tmp, width = 800, height = 360)
      par(mar = c(4, 4, 1, 1))
      plot(
        seq_along(values),
        values,
        type = "b",
        pch = 19,
        col = "#0f766e",
        xaxt = "n",
        xlab = "Month",
        ylab = metric
      )
      axis(1, at = seq_along(values), labels = month.abb)
      grid()
      grDevices::dev.off()
      on.exit(unlink(tmp))

      list(
        trend = base64enc::base64encode(tmp),
        summary = sprintf(
          "%s region, %s: total %s, monthly mean %.0f, best month %s.",
          region,
          metric,
          format(sum(values), big.mark = ","),
          mean(values),
          month.abb[which.max(values)]
        )
      )
    },
    name = "summarize_region",
    description = "Summarize monthly sales for a region with a trend plot.",
    arguments = list(
      region = ellmer::type_string("Region: North, South, East, or West"),
      metric = ellmer::type_string("Metric: units or revenue")
    )
  ),

  # App-only tool: callable from the iframe via window.shinymcp.callTool(),
  # but hidden from the model's tool list (visibility "app" below). Use this
  # pattern for UI plumbing or detail views the model shouldn't reach for.
  list(
    name = "fetch_region_detail",
    description = "Return month-by-month rows for one region as an HTML table.",
    inputSchema = list(
      type = "object",
      properties = list(
        detail_region = list(type = "string", description = "Region name")
      )
    ),
    fun = function(detail_region = "North") {
      slice <- sales[
        sales$region == detail_region,
        c("month", "units", "revenue")
      ]
      rows <- apply(slice, 1, function(r) {
        sprintf("<tr><td>%s</td><td>%s</td><td>%s</td></tr>", r[1], r[2], r[3])
      })
      list(detail = paste0(
        "<table class='table table-sm'><thead><tr>",
        "<th>Month</th><th>Units</th><th>Revenue</th></tr></thead><tbody>",
        paste(rows, collapse = ""),
        "</tbody></table>"
      ))
    }
  )
)

# ---- App --------------------------------------------------------------------

app <- mcp_app(
  ui,
  tools,
  name = "feature-tour",

  # 1. Visibility scoping: the detail tool is for the UI only. Run
  #    app$tool_definitions() and compare the two tools' _meta.ui.visibility.
  tool_visibility = list(fetch_region_detail = "app"),

  # 2. Lazy resource: served via resources/read instead of inlined. Function
  #    content is re-evaluated on every read.
  resources = list(
    "ui://feature-tour/region-notes" = list(
      content = function() jsonlite::toJSON(region_notes, auto_unbox = TRUE),
      mime_type = "application/json",
      description = "Qualitative notes per region for the catalog panel"
    )
  ),

  # 3. Declared result shape: generates an outputSchema for the analysis
  #    tool. Descriptions are derived from the UI output types (plot/text).
  tool_outputs = list(summarize_region = c("trend", "summary")),

  # 4. Resource _meta hint: ask the host to draw a border around the card.
  prefers_border = TRUE
)

if (interactive()) {
  preview_app(app)
} else {
  serve(app)
}
