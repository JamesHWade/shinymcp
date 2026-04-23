library(shinymcp)
library(shiny)
library(bslib)
library(htmltools)
library(ellmer)

use_case_theme <- function() {
  bs_theme(
    preset = "shiny",
    primary = "#1a8a9e"
  )
}

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

shinymcp_revenue_forecaster <- function() {
  ui <- page_sidebar(
    theme = use_case_theme(),
    title = "Revenue Scenario Board",
    sidebar = sidebar(
      width = 300,
      selectInput(
        "segment",
        "Segment",
        choices = c("SMB", "Mid-market", "Enterprise")
      ),
      numericInput(
        "visitors",
        "Monthly qualified visitors",
        value = 18000,
        min = 1000,
        step = 500
      ),
      sliderInput(
        "trial_rate",
        "Visitor to trial rate",
        min = 1,
        max = 25,
        value = 8,
        post = "%"
      ),
      sliderInput(
        "win_rate",
        "Trial to customer rate",
        min = 1,
        max = 40,
        value = 18,
        post = "%"
      ),
      numericInput(
        "contract_value",
        "Average contract value",
        value = 4200,
        min = 250,
        step = 250
      ),
      sliderInput(
        "monthly_churn",
        "Monthly churn",
        min = 0,
        max = 12,
        value = 3,
        post = "%"
      )
    ),
    layout_columns(
      col_widths = c(5, 7),
      card(
        card_header("Decision summary"),
        mcp_text("summary")
      ),
      card(
        card_header("ARR ramp"),
        mcp_plot("arr_plot", height = "280px")
      )
    ),
    card(
      card_header("Monthly forecast"),
      mcp_table("forecast")
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
  ui <- page_sidebar(
    theme = use_case_theme(),
    title = "Experiment Planner",
    sidebar = sidebar(
      width = 300,
      sliderInput(
        "baseline_rate",
        "Baseline conversion",
        min = 1,
        max = 80,
        value = 12,
        post = "%"
      ),
      sliderInput(
        "minimum_effect",
        "Minimum relative lift",
        min = 1,
        max = 60,
        value = 15,
        post = "%"
      ),
      selectInput(
        "target_power",
        "Target power",
        choices = c("80%" = 0.8, "90%" = 0.9, "95%" = 0.95)
      ),
      numericInput(
        "traffic_per_day",
        "Eligible users per day",
        value = 6000,
        min = 100,
        step = 100
      )
    ),
    layout_columns(
      col_widths = c(5, 7),
      card(
        card_header("Recommended design"),
        mcp_text("summary")
      ),
      card(
        card_header("Power curve"),
        mcp_plot("power_plot", height = "280px")
      )
    ),
    card(
      card_header("Design inputs"),
      mcp_table("design")
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
  ui <- page_sidebar(
    theme = use_case_theme(),
    title = "Incident Triage Console",
    sidebar = sidebar(
      width = 300,
      selectInput(
        "service",
        "Service",
        choices = c("Payments", "Login", "API", "Data export")
      ),
      selectInput(
        "severity",
        "Current impact",
        choices = c("Minor", "Degraded", "Outage")
      ),
      numericInput(
        "affected_users",
        "Affected users",
        value = 250,
        min = 0,
        step = 25
      ),
      numericInput(
        "minutes_open",
        "Minutes since first alert",
        value = 18,
        min = 0,
        step = 5
      ),
      checkboxInput("regulated_data", "Regulated data involved")
    ),
    card(
      card_header("Status"),
      mcp_html("status")
    ),
    layout_columns(
      col_widths = c(5, 7),
      card(
        card_header("Briefing"),
        mcp_text("briefing")
      ),
      card(
        card_header("Runbook"),
        mcp_table("runbook")
      )
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
