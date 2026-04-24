library(shinymcp)
library(htmltools)
library(ellmer)

as_number <- function(x, default = 0) {
  if (is.null(x) || identical(x, "")) {
    return(default)
  }
  value <- suppressWarnings(as.numeric(x))
  if (is.na(value)) default else value
}

as_flag <- function(x) {
  isTRUE(x) || identical(x, "true") || identical(x, "1") || identical(x, 1)
}

money <- function(x) {
  paste0("$", format(round(x), big.mark = ",", trim = TRUE))
}

pct <- function(x) {
  paste0(round(100 * x, 1), "%")
}

intent_input <- function() {
  tags$input(
    type = "hidden",
    id = "_intent",
    `data-shinymcp-input` = "_intent",
    `data-shinymcp-type` = "text",
    value = ""
  )
}

use_case_styles <- function() {
  tags$style(HTML(
    "
    *, *::before, *::after { box-sizing: border-box; }
    body {
      margin: 0;
      background: #fff;
      color: #172033;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      font-size: 13px;
      line-height: 1.35;
    }
    .shinymcp-use-case {
      display: grid;
      gap: 10px;
      padding: 12px;
      max-width: 760px;
      margin: 0 auto;
    }
    .shinymcp-use-case-header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 10px;
      border-bottom: 1px solid #e2e8f0;
      padding-bottom: 8px;
    }
    .shinymcp-use-case-eyebrow {
      color: #64748b;
      font-size: 0.68rem;
      font-weight: 700;
      letter-spacing: 0;
      text-transform: uppercase;
    }
    .shinymcp-use-case-title {
      margin: 1px 0 0;
      font-size: 1rem;
      font-weight: 700;
      line-height: 1.2;
    }
    .shinymcp-use-case-subtitle {
      margin: 2px 0 0;
      color: #64748b;
      font-size: 0.78rem;
    }
    .shinymcp-controls {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(132px, 1fr));
      gap: 8px 10px;
    }
    .shinymcp-input-group {
      min-width: 0;
      display: grid;
      gap: 2px;
    }
    .shinymcp-input-group label {
      color: #334155;
      font-size: 0.72rem;
      font-weight: 650;
    }
    .shinymcp-input-group select,
    .shinymcp-input-group input:not([type='checkbox']) {
      width: 100%;
      min-height: 30px;
      border: 1px solid #cbd5e1;
      border-radius: 6px;
      padding: 3px 7px;
      color: #0f172a;
      background: #fff;
      font-size: 0.78rem;
    }
    .shinymcp-input-group input[type='range'] {
      padding: 0;
    }
    .shinymcp-input-group input[type='checkbox'] {
      margin-right: 5px;
    }
    .shinymcp-output-grid {
      display: grid;
      grid-template-columns: minmax(0, 0.9fr) minmax(0, 1.1fr);
      gap: 9px;
      align-items: start;
    }
    .shinymcp-output-pane {
      min-width: 0;
      border-top: 1px solid #e2e8f0;
      padding-top: 8px;
    }
    .shinymcp-output-pane-wide {
      grid-column: 1 / -1;
    }
    .shinymcp-output-label {
      margin-bottom: 4px;
      color: #64748b;
      font-size: 0.68rem;
      font-weight: 700;
      letter-spacing: 0;
      text-transform: uppercase;
    }
    .shinymcp-use-case pre.shinymcp-output {
      white-space: normal !important;
      overflow: visible !important;
      color: #172033;
      font-family: inherit !important;
      font-size: 0.82rem !important;
      line-height: 1.4;
    }
    .shinymcp-use-case [data-shinymcp-output-type='plot'] {
      height: auto !important;
      overflow: visible !important;
    }
    .shinymcp-use-case [data-shinymcp-output-type='plot'] img {
      display: block;
      width: 100%;
      max-height: 220px;
      object-fit: contain;
    }
    .shinymcp-use-case table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.74rem;
    }
    .shinymcp-use-case th,
    .shinymcp-use-case td {
      border-bottom: 1px solid #e2e8f0;
      padding: 4px 5px;
      text-align: left;
      vertical-align: top;
    }
    .shinymcp-use-case th {
      color: #334155;
      font-weight: 700;
      background: #f8fafc;
    }
    .shinymcp-output-details {
      min-width: 0;
      border-top: 1px solid #e2e8f0;
      padding-top: 8px;
    }
    .shinymcp-output-details > summary {
      cursor: pointer;
      color: #334155;
      font-size: 0.76rem;
      font-weight: 700;
    }
    .shinymcp-status-strip {
      min-height: 44px;
    }
    @media (max-width: 560px) {
      .shinymcp-use-case {
        padding: 10px;
      }
      .shinymcp-output-grid {
        grid-template-columns: 1fr;
      }
      .shinymcp-output-pane-wide {
        grid-column: auto;
      }
    }
  "
  ))
}

use_case_page <- function(title, subtitle, controls, ...) {
  tags$main(
    class = "shinymcp-use-case",
    use_case_styles(),
    tags$header(
      class = "shinymcp-use-case-header",
      tags$div(
        tags$div(class = "shinymcp-use-case-eyebrow", "shinymcp card"),
        tags$h1(class = "shinymcp-use-case-title", title),
        tags$p(class = "shinymcp-use-case-subtitle", subtitle)
      )
    ),
    tags$section(class = "shinymcp-controls", controls),
    ...,
    intent_input()
  )
}

output_pane <- function(label, output, wide = FALSE) {
  tags$section(
    class = paste(
      "shinymcp-output-pane",
      if (isTRUE(wide)) "shinymcp-output-pane-wide" else ""
    ),
    tags$div(class = "shinymcp-output-label", label),
    output
  )
}

output_details <- function(label, output, open = FALSE) {
  tags$details(
    class = "shinymcp-output-details",
    open = if (isTRUE(open)) NA else NULL,
    tags$summary(label),
    output
  )
}

shinymcp_revenue_forecaster <- function() {
  ui <- use_case_page(
    title = "Revenue Scenario Board",
    subtitle = "Tune the funnel, then inspect the ARR ramp.",
    controls = tagList(
      mcp_select(
        "segment",
        "Segment",
        choices = c("SMB", "Mid-market", "Enterprise")
      ),
      mcp_numeric_input(
        "visitors",
        "Qualified visitors",
        value = 18000,
        min = 1000,
        step = 500
      ),
      mcp_slider(
        "trial_rate",
        "Trial rate",
        min = 1,
        max = 25,
        value = 8
      ),
      mcp_slider(
        "win_rate",
        "Win rate",
        min = 1,
        max = 40,
        value = 18
      ),
      mcp_numeric_input(
        "contract_value",
        "ACV",
        value = 4200,
        min = 250,
        step = 250
      ),
      mcp_slider(
        "monthly_churn",
        "Churn",
        min = 0,
        max = 12,
        value = 3
      )
    ),
    output_pane("Decision summary", mcp_text("summary"), wide = TRUE),
    tags$section(
      class = "shinymcp-output-grid",
      output_pane("ARR ramp", mcp_plot("arr_plot", height = "220px")),
      output_details("Monthly forecast", mcp_table("forecast"))
    )
  )

  tool <- ellmer::tool(
    fun = function(
      segment = "SMB",
      visitors = 18000,
      trial_rate = 8,
      win_rate = 18,
      contract_value = 4200,
      monthly_churn = 3,
      `_intent` = NULL
    ) {
      visitors <- as_number(visitors, 18000)
      trial_rate <- as_number(trial_rate, 8) / 100
      win_rate <- as_number(win_rate, 18) / 100
      contract_value <- as_number(contract_value, 4200)
      monthly_churn <- as_number(monthly_churn, 3) / 100

      months <- seq_len(12)
      new_trials <- visitors * trial_rate
      new_customers <- new_trials * win_rate
      active_customers <- numeric(length(months))
      for (month in months) {
        retained <- if (month == 1) {
          0
        } else {
          active_customers[[month - 1]] *
            (1 - monthly_churn)
        }
        active_customers[[month]] <- retained + new_customers
      }

      mrr <- active_customers * contract_value / 12
      arr <- mrr * 12
      forecast <- data.frame(
        month = months,
        new_customers = round(new_customers, 1),
        active_customers = round(active_customers, 1),
        mrr = money(mrr),
        arr = money(arr),
        check.names = FALSE
      )

      final_arr <- utils::tail(arr, 1)
      summary <- paste(
        segment,
        "scenario:",
        money(final_arr),
        "ARR by month 12 from",
        round(new_customers, 1),
        "new customers per month.",
        "The break-even watch item is",
        pct(monthly_churn),
        "monthly churn against",
        money(contract_value),
        "ACV."
      )

      list(
        summary = mcp_result_text(
          summary,
          model_value = list(
            segment = segment,
            month_12_arr = final_arr,
            new_customers_per_month = new_customers,
            monthly_churn = monthly_churn
          )
        ),
        forecast = mcp_result_table(
          forecast,
          text = "Twelve-month revenue forecast."
        ),
        arr_plot = mcp_result_plot(
          function() {
            plot(
              months,
              arr / 1000,
              type = "o",
              pch = 19,
              col = "#1a8a9e",
              xlab = "Month",
              ylab = "ARR ($000s)",
              main = paste(segment, "ARR forecast")
            )
            grid(col = "#d9e3e6")
          },
          model_value = list(month = months, arr = arr),
          text = "Line chart showing the ARR ramp over twelve months."
        )
      )
    },
    name = "forecast_revenue",
    description = paste(
      "Forecast revenue from a go-to-market funnel and return the scenario",
      "summary, monthly table, and ARR plot."
    ),
    arguments = list(
      segment = type_string("Customer segment."),
      visitors = type_number("Monthly qualified visitors."),
      trial_rate = type_number("Visitor-to-trial conversion percentage."),
      win_rate = type_number("Trial-to-customer conversion percentage."),
      contract_value = type_number("Average annual contract value in dollars."),
      monthly_churn = type_number("Monthly churn percentage."),
      `_intent` = type_string(
        "Short reason this forecast is being prepared for display."
      )
    )
  )

  mcp_app(ui, list(tool), name = "revenue-scenario-board")
}

shinymcp_experiment_planner <- function() {
  ui <- use_case_page(
    title = "Experiment Planner",
    subtitle = "Estimate sample size and runtime for an A/B test.",
    controls = tagList(
      mcp_slider(
        "baseline_rate",
        "Baseline conversion",
        min = 1,
        max = 80,
        value = 12
      ),
      mcp_slider(
        "minimum_effect",
        "Minimum lift",
        min = 1,
        max = 60,
        value = 15
      ),
      mcp_select(
        "target_power",
        "Target power",
        choices = c("80%" = 0.8, "90%" = 0.9, "95%" = 0.95)
      ),
      mcp_numeric_input(
        "traffic_per_day",
        "Users/day",
        value = 6000,
        min = 100,
        step = 100
      )
    ),
    output_pane("Recommended design", mcp_text("summary"), wide = TRUE),
    tags$section(
      class = "shinymcp-output-grid",
      output_pane("Power curve", mcp_plot("power_plot", height = "220px")),
      output_details("Design inputs", mcp_table("design"))
    )
  )

  tool <- ellmer::tool(
    fun = function(
      baseline_rate = 12,
      minimum_effect = 15,
      target_power = 0.8,
      traffic_per_day = 6000,
      `_intent` = NULL
    ) {
      baseline <- as_number(baseline_rate, 12) / 100
      lift <- as_number(minimum_effect, 15) / 100
      target_power <- as_number(target_power, 0.8)
      traffic_per_day <- as_number(traffic_per_day, 6000)
      treatment <- min(baseline * (1 + lift), 0.99)

      design_calc <- stats::power.prop.test(
        p1 = baseline,
        p2 = treatment,
        sig.level = 0.05,
        power = target_power,
        alternative = "two.sided"
      )
      n_per_arm <- ceiling(design_calc$n)
      total_n <- 2 * n_per_arm
      days <- ceiling(total_n / traffic_per_day)

      power_n <- unique(round(seq(
        n_per_arm * 0.35,
        n_per_arm * 1.35,
        length.out = 20
      )))
      power_values <- vapply(
        power_n,
        function(n) {
          stats::power.prop.test(
            n = max(n, 2),
            p1 = baseline,
            p2 = treatment,
            sig.level = 0.05,
            alternative = "two.sided"
          )$power
        },
        numeric(1)
      )

      design <- data.frame(
        metric = c(
          "Baseline conversion",
          "Detectable treatment conversion",
          "Relative lift",
          "Power",
          "Sample per arm",
          "Total sample",
          "Estimated runtime"
        ),
        value = c(
          pct(baseline),
          pct(treatment),
          pct(lift),
          pct(target_power),
          format(n_per_arm, big.mark = ","),
          format(total_n, big.mark = ","),
          paste(days, "days")
        ),
        check.names = FALSE
      )

      summary <- paste(
        "Run for about",
        days,
        "days to detect a lift from",
        pct(baseline),
        "to",
        pct(treatment),
        "with",
        pct(target_power),
        "power.",
        "Plan on",
        format(n_per_arm, big.mark = ","),
        "users per arm."
      )

      list(
        summary = mcp_result_text(
          summary,
          model_value = list(
            baseline = baseline,
            treatment = treatment,
            target_power = target_power,
            sample_per_arm = n_per_arm,
            total_sample = total_n,
            runtime_days = days
          )
        ),
        design = mcp_result_table(design, text = "Experiment design table."),
        power_plot = mcp_result_plot(
          function() {
            plot(
              power_n,
              power_values,
              type = "l",
              lwd = 2,
              col = "#16697a",
              ylim = c(0, 1),
              xlab = "Sample per arm",
              ylab = "Power",
              main = "Power by sample size"
            )
            abline(h = target_power, lty = 2, col = "#db6c28")
            abline(v = n_per_arm, lty = 2, col = "#db6c28")
            grid(col = "#d9e3e6")
          },
          model_value = list(sample_per_arm = power_n, power = power_values),
          text = "Line chart showing statistical power by sample size."
        )
      )
    },
    name = "plan_experiment",
    description = paste(
      "Plan an A/B test by estimating required sample size, runtime,",
      "and a power curve."
    ),
    arguments = list(
      baseline_rate = type_number("Baseline conversion percentage."),
      minimum_effect = type_number("Minimum detectable relative lift percent."),
      target_power = type_number("Target statistical power as a decimal."),
      traffic_per_day = type_number("Eligible users per day."),
      `_intent` = type_string(
        "Short reason this experiment design is being prepared for display."
      )
    )
  )

  mcp_app(ui, list(tool), name = "experiment-planner")
}

shinymcp_incident_triage <- function() {
  ui <- use_case_page(
    title = "Incident Triage Console",
    subtitle = "Classify impact and build the next-step runbook.",
    controls = tagList(
      mcp_select(
        "service",
        "Service",
        choices = c("Payments", "Login", "API", "Data export")
      ),
      mcp_select(
        "severity",
        "Impact",
        choices = c("Minor", "Degraded", "Outage")
      ),
      mcp_numeric_input(
        "affected_users",
        "Affected users",
        value = 250,
        min = 0,
        step = 25
      ),
      mcp_numeric_input(
        "minutes_open",
        "Minutes open",
        value = 18,
        min = 0,
        step = 5
      ),
      mcp_checkbox("regulated_data", "Regulated data involved")
    ),
    output_pane(
      "Status",
      tags$div(class = "shinymcp-status-strip", mcp_html("status")),
      wide = TRUE
    ),
    tags$section(
      class = "shinymcp-output-grid",
      output_pane("Briefing", mcp_text("briefing")),
      output_details("Runbook", mcp_table("runbook"))
    )
  )

  tool <- ellmer::tool(
    fun = function(
      service = "Payments",
      severity = "Minor",
      affected_users = 250,
      minutes_open = 18,
      regulated_data = FALSE,
      `_intent` = NULL
    ) {
      affected_users <- as_number(affected_users, 250)
      minutes_open <- as_number(minutes_open, 18)
      regulated <- as_flag(regulated_data)
      impact <- tolower(severity)
      priority <- if (impact == "outage" || affected_users >= 5000) {
        "P1"
      } else if (impact == "degraded" || affected_users >= 500 || regulated) {
        "P2"
      } else {
        "P3"
      }

      owner <- switch(
        tolower(service),
        payments = "Payments on-call",
        login = "Identity on-call",
        api = "Platform on-call",
        "data export" = "Data platform on-call",
        "Primary on-call"
      )

      eta <- switch(priority, P1 = "15 minutes", P2 = "30 minutes", "1 hour")
      comms <- switch(
        priority,
        P1 = "Open status page incident and executive channel.",
        P2 = "Post status page update if impact is customer-visible.",
        "Track internally unless customer reports increase."
      )
      if (regulated) {
        comms <- paste(comms, "Notify privacy/legal duty lead.")
      }

      runbook <- data.frame(
        step = c(
          "Assign owner",
          "Stabilize",
          "Communicate",
          "Verify recovery"
        ),
        action = c(
          owner,
          paste("Mitigate", service, "within", eta),
          comms,
          "Confirm error budget, support volume, and synthetic checks recover."
        ),
        check.names = FALSE
      )

      briefing <- paste(
        priority,
        service,
        "incident:",
        severity,
        "impact for",
        format(affected_users, big.mark = ","),
        "users and open for",
        minutes_open,
        "minutes.",
        "Next owner:",
        owner
      )

      color <- switch(priority, P1 = "#b42318", P2 = "#b54708", "#027a48")
      status <- tags$div(
        style = paste(
          "border-left: 6px solid",
          color,
          "; padding: 0.75rem 1rem; background: #f8fafc;"
        ),
        tags$strong(priority),
        tags$span(paste(" -", service, severity)),
        tags$p(
          style = "margin: 0.5rem 0 0;",
          paste("Response target:", eta)
        )
      )

      list(
        status = mcp_result_html(
          status,
          text = paste(priority, service, "response target", eta)
        ),
        briefing = mcp_result_text(
          briefing,
          model_value = list(
            priority = priority,
            service = service,
            severity = severity,
            affected_users = affected_users,
            minutes_open = minutes_open,
            regulated_data = regulated,
            owner = owner
          )
        ),
        runbook = mcp_result_table(runbook, text = "Incident response runbook.")
      )
    },
    name = "triage_incident",
    description = paste(
      "Turn incident facts into a priority, concise briefing, and",
      "next-step runbook."
    ),
    arguments = list(
      service = type_string("Impacted service name."),
      severity = type_string("Impact: Minor, Degraded, or Outage."),
      affected_users = type_number("Estimated affected users."),
      minutes_open = type_number("Minutes since the first alert."),
      regulated_data = type_boolean("Whether regulated data is involved."),
      `_intent` = type_string(
        "Short reason this triage card is being prepared for display."
      )
    )
  )

  mcp_app(ui, list(tool), name = "incident-triage-console")
}

shinymcp_use_cases <- function() {
  list(
    revenue = shinymcp_revenue_forecaster(),
    experiment = shinymcp_experiment_planner(),
    incident = shinymcp_incident_triage()
  )
}

shinymcp_use_case <- function(name = "revenue") {
  apps <- shinymcp_use_cases()
  if (!name %in% names(apps)) {
    stop(
      "Unknown use case '",
      name,
      "'. Expected one of: ",
      paste(names(apps), collapse = ", "),
      call. = FALSE
    )
  }
  apps[[name]]
}
