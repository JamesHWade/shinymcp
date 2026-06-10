library(shiny)
library(bslib)
library(htmltools)
library(ellmer)
library(shinychat)
library(shinymcp)

make_trial_data <- function() {
  set.seed(616)
  n <- 384
  cohort <- sample(
    c("Lung", "Breast", "Colorectal"),
    n,
    replace = TRUE,
    prob = c(0.42, 0.34, 0.24)
  )
  arm <- sample(c("Control", "Investigational"), n, replace = TRUE)
  site <- sample(sprintf("Site %02d", 1:16), n, replace = TRUE)

  response_base <- c(Lung = 0.31, Breast = 0.38, Colorectal = 0.27)
  response_lift <- ifelse(arm == "Investigational", 0.09, 0)
  response_rate <- pmin(response_base[cohort] + response_lift, 0.85)
  response <- stats::rbinom(n, size = 1, prob = response_rate)

  data.frame(
    usubjid = sprintf("SUBJ-%04d", seq_len(n)),
    cohort = cohort,
    arm = arm,
    site = site,
    response = response,
    screen_failure = stats::rbinom(n, size = 1, prob = 0.16),
    query_open = stats::rbinom(n, size = 1, prob = 0.18),
    missing_visit = stats::rbinom(n, size = 1, prob = 0.11),
    neutropenia_grade = pmin(
      stats::rpois(n, lambda = ifelse(arm == "Investigational", 1.35, 0.85)),
      4
    ),
    fatigue_grade = pmin(stats::rpois(n, lambda = 0.9), 4),
    nausea_grade = pmin(stats::rpois(n, lambda = 0.65), 4),
    rash_grade = pmin(
      stats::rpois(n, lambda = ifelse(cohort == "Breast", 0.72, 0.45)),
      4
    ),
    alt_grade = pmin(
      stats::rpois(n, lambda = ifelse(arm == "Investigational", 0.55, 0.38)),
      4
    ),
    check.names = FALSE
  )
}

trial_data <- make_trial_data()

trial_css <- function() {
  tags$style(HTML(
    "
    .rp-shell {
      min-height: 100vh;
      background:
        linear-gradient(180deg, #edf3f9 0, #f7f9fb 270px, #f6f8fb 100%);
      color: #172033;
    }
    .bslib-page-navbar {
      background:
        linear-gradient(180deg, #edf3f9 0, #f7f9fb 270px, #f6f8fb 100%);
      color: #172033;
    }
    .bslib-page-navbar > .container-fluid {
      padding-right: 0;
      padding-left: 0;
    }
    .bslib-page-navbar > .navbar {
      margin-bottom: 0;
      border-top: 6px solid #39729e;
      border-bottom: 1px solid rgba(57, 114, 158, 0.22);
      background: rgba(255, 255, 255, 0.94);
    }
    .bslib-page-navbar .navbar-brand {
      color: #39729e;
      font-weight: 820;
    }
    .bslib-page-navbar .navbar-nav > li > a,
    .bslib-page-navbar .nav-link {
      color: #344054;
      font-weight: 700;
    }
    .bslib-page-navbar .navbar-nav > li.active > a,
    .bslib-page-navbar .nav-link.active {
      color: #39729e;
    }
    .rp-navbar-brand {
      display: inline-flex;
      align-items: center;
      gap: 0.4rem;
    }
    .rp-navbar-mark {
      display: inline-grid;
      place-items: center;
      width: 1.55rem;
      height: 1.55rem;
      border-radius: 50%;
      background: #39729e;
      color: #ffffff;
      font-size: 0.78rem;
      font-weight: 820;
      box-shadow: inset -0.28rem 0 0 #ff7518;
    }
    .rp-band {
      position: relative;
      overflow: hidden;
      display: grid;
      gap: 1rem;
      padding: 1rem 1.2rem 1.15rem;
      border-bottom: 1px solid rgba(57, 114, 158, 0.22);
      background:
        linear-gradient(135deg, rgba(255, 255, 255, 0.96), rgba(237, 243, 249, 0.92)),
        repeating-linear-gradient(
          90deg,
          rgba(57, 114, 158, 0.08) 0,
          rgba(57, 114, 158, 0.08) 1px,
          transparent 1px,
          transparent 46px
        );
    }
    .rp-band::after {
      content: '';
      position: absolute;
      right: 1.25rem;
      top: 0.85rem;
      width: 180px;
      height: 74px;
      border: 1px solid rgba(57, 114, 158, 0.18);
      border-radius: 999px;
      background:
        linear-gradient(90deg, rgba(255, 117, 24, 0.18) 0 50%, rgba(57, 114, 158, 0.16) 50% 100%);
      transform: rotate(-10deg);
      pointer-events: none;
    }
    .rp-brand-row {
      position: relative;
      z-index: 1;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.75rem;
    }
    .rp-brand-lockup {
      display: inline-flex;
      align-items: center;
      gap: 0.55rem;
      min-width: 0;
    }
    .rp-brand-mark {
      display: inline-grid;
      place-items: center;
      width: 2.35rem;
      height: 2.35rem;
      border-radius: 50%;
      background: #39729e;
      color: #ffffff;
      font-weight: 820;
      box-shadow: inset -0.42rem 0 0 #ff7518;
    }
    .rp-wordmark {
      color: #39729e;
      font-size: 1.08rem;
      font-weight: 820;
      letter-spacing: 0;
      white-space: nowrap;
    }
    .rp-wordmark-slash {
      color: #ff7518;
      padding: 0 0.05rem;
    }
    .rp-event-pill {
      display: inline-flex;
      align-items: center;
      min-height: 1.9rem;
      padding: 0.25rem 0.65rem;
      border: 1px solid rgba(255, 117, 24, 0.35);
      border-radius: 999px;
      background: #fff7ed;
      color: #78430d;
      font-size: 0.72rem;
      font-weight: 760;
      white-space: nowrap;
    }
    .rp-hero-content {
      position: relative;
      z-index: 1;
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(250px, 0.33fr);
      gap: 1.2rem;
      align-items: end;
    }
    .rp-eyebrow {
      color: #39729e;
      font-size: 0.74rem;
      font-weight: 760;
      text-transform: uppercase;
      letter-spacing: 0;
    }
    .rp-title {
      margin: 0;
      color: #172033;
      font-size: 1.65rem;
      line-height: 1.15;
      font-weight: 820;
    }
    .rp-subtitle {
      max-width: 920px;
      margin: 0.35rem 0 0;
      color: #455468;
      font-size: 0.92rem;
    }
    .rp-hero-card {
      min-width: 0;
      padding: 0.8rem 0.9rem;
      border: 1px solid rgba(57, 114, 158, 0.2);
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.82);
      box-shadow: 0 10px 30px rgba(23, 32, 51, 0.06);
    }
    .rp-hero-card-label {
      color: #667085;
      font-size: 0.68rem;
      font-weight: 760;
      text-transform: uppercase;
      letter-spacing: 0;
    }
    .rp-hero-card-value {
      margin-top: 0.2rem;
      color: #39729e;
      font-size: 1rem;
      font-weight: 820;
      line-height: 1.18;
    }
    .rp-hero-card-note {
      margin-top: 0.25rem;
      color: #455468;
      font-size: 0.78rem;
      line-height: 1.35;
    }
    .rp-layout {
      padding: 1rem;
    }
    .rp-assistant-page {
      padding: 1rem;
    }
    .rp-assistant-page .rp-chat-section {
      max-width: 1040px;
      margin: 0 auto 0.9rem;
    }
    .rp-metrics {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(155px, 1fr));
      gap: 0.65rem;
      margin-bottom: 0.9rem;
    }
    .rp-metric {
      min-height: 88px;
      padding: 0.8rem;
      border: 1px solid #dbe4ee;
      border-radius: 8px;
      background: #ffffff;
    }
    .rp-metric-label {
      color: #616f7d;
      font-size: 0.72rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0;
    }
    .rp-metric-value {
      margin-top: 0.35rem;
      color: #39729e;
      font-size: 1.55rem;
      line-height: 1;
      font-weight: 780;
    }
    .rp-metric-note {
      margin-top: 0.25rem;
      color: #556575;
      font-size: 0.76rem;
    }
    .rp-dashboard {
      display: grid;
      grid-template-columns: minmax(0, 1.05fr) minmax(280px, 0.95fr);
      gap: 0.85rem;
      align-items: start;
    }
    .rp-panel {
      min-width: 0;
      padding: 0.95rem;
      border: 1px solid #dbe4ee;
      border-radius: 8px;
      background: #ffffff;
    }
    .rp-panel h2 {
      margin: 0 0 0.75rem;
      color: #172033;
      font-size: 1rem;
      font-weight: 740;
    }
    .rp-note {
      padding: 0.75rem;
      border-left: 5px solid #ff7518;
      background: #fff7ed;
      color: #3b2a1f;
      font-size: 0.84rem;
    }
    .rp-widget-copy {
      display: grid;
      gap: 0.35rem;
      margin-bottom: 0.75rem;
      color: #455468;
      font-size: 0.86rem;
    }
    .rp-host-strip {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 0.45rem;
      margin-bottom: 0.75rem;
    }
    .rp-host-chip {
      min-width: 0;
      padding: 0.55rem;
      border: 1px solid #d8e0ea;
      border-radius: 8px;
      background: #f8fafc;
    }
    .rp-host-chip strong {
      display: block;
      color: #172033;
      font-size: 0.76rem;
    }
    .rp-host-chip span {
      display: block;
      margin-top: 0.18rem;
      color: #5d6b7a;
      font-size: 0.7rem;
      overflow-wrap: anywhere;
    }
    .rp-explain-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 0.85rem;
      margin: 0.85rem 0;
    }
    .rp-compare {
      min-width: 0;
      padding: 0.95rem;
      border: 1px solid #dbe4ee;
      border-radius: 8px;
      background: #ffffff;
    }
    .rp-compare[data-kind='mcp'] {
      border-left: 5px solid #087443;
    }
    .rp-compare[data-kind='shiny'] {
      border-left: 5px solid #ff7518;
    }
    .rp-compare h2 {
      margin: 0 0 0.55rem;
      color: #172033;
      font-size: 0.98rem;
      font-weight: 740;
    }
    .rp-compare ul {
      display: grid;
      gap: 0.35rem;
      margin: 0;
      padding-left: 1rem;
      color: #455468;
      font-size: 0.84rem;
    }
    .rp-benefit-grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 0.65rem;
      margin: 0.85rem 0;
    }
    .rp-benefit-card {
      min-width: 0;
      padding: 0.85rem;
      border: 1px solid #dbe4ee;
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.95);
    }
    .rp-benefit-card[data-live='true'] {
      border-color: #a6d8b6;
      background: #f6fef9;
    }
    .rp-benefit-step {
      color: #667085;
      font-size: 0.68rem;
      font-weight: 760;
      text-transform: uppercase;
      letter-spacing: 0;
    }
    .rp-benefit-title {
      margin-top: 0.22rem;
      color: #172033;
      font-size: 0.92rem;
      font-weight: 760;
      line-height: 1.2;
    }
    .rp-benefit-body {
      margin-top: 0.35rem;
      color: #455468;
      font-size: 0.78rem;
      line-height: 1.35;
    }
    .rp-benefit-value {
      display: block;
      margin-top: 0.4rem;
      padding: 0.35rem 0.45rem;
      border-radius: 6px;
      background: #f1f5f9;
      color: #243b53;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
        'Liberation Mono', monospace;
      font-size: 0.72rem;
      overflow-wrap: anywhere;
    }
    .rp-chat-section {
      margin: 0.85rem 0;
    }
    .rp-chat-card {
      border: 1px solid rgba(57, 114, 158, 0.24);
      border-radius: 8px;
      overflow: hidden;
      background: #ffffff;
      box-shadow: 0 10px 28px rgba(23, 32, 51, 0.06);
    }
    .rp-chat-card > .card-header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 0.8rem;
      border-bottom: 1px solid rgba(57, 114, 158, 0.18);
      background: #edf3f9;
    }
    .rp-chat-heading {
      color: #172033;
      font-size: 0.98rem;
      font-weight: 780;
      line-height: 1.2;
    }
    .rp-chat-subtitle {
      margin-top: 0.2rem;
      color: #455468;
      font-size: 0.78rem;
      line-height: 1.35;
    }
    .rp-chat-mode {
      flex: 0 0 auto;
      padding: 0.2rem 0.55rem;
      border: 1px solid rgba(8, 116, 67, 0.25);
      border-radius: 999px;
      background: #f0fdf4;
      color: #087443;
      font-size: 0.68rem;
      font-weight: 780;
      text-transform: uppercase;
      white-space: nowrap;
    }
    .rp-chat-body {
      padding: 0;
    }
    .rp-chat-body shiny-chat-container {
      --shiny-chat-max-width: 100%;
      --shiny-chat-footer-color: #455468;
      --shiny-chat-footer-font-size: 0.76rem;
    }
    .rp-chat-body shiny-chat-footer,
    .rp-chat-body .shiny-chat-footer {
      border-top: 1px solid rgba(57, 114, 158, 0.18);
      padding: 0.65rem 0.75rem;
      background: #f8fafc;
    }
    .rp-chat-footer {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 0.55rem;
      color: #455468;
      font-size: 0.76rem;
      line-height: 1.35;
    }
    .rp-chat-footer-copy {
      min-width: 220px;
      flex: 1 1 360px;
    }
    .rp-chat-footer-copy strong {
      color: #172033;
    }
    .rp-chat-footer-chips {
      display: flex;
      flex: 0 1 auto;
      flex-wrap: wrap;
      gap: 0.35rem;
    }
    .rp-chat-footer-chip {
      display: inline-flex;
      align-items: center;
      min-height: 1.45rem;
      padding: 0.1rem 0.45rem;
      border: 1px solid rgba(57, 114, 158, 0.2);
      border-radius: 999px;
      background: #ffffff;
      color: #39729e;
      font-size: 0.68rem;
      font-weight: 760;
      white-space: nowrap;
    }
    .rp-chat-welcome {
      display: grid;
      gap: 0.65rem;
      color: #344054;
      font-size: 0.9rem;
      line-height: 1.38;
    }
    .rp-chat-welcome strong {
      color: #172033;
    }
    .rp-chat-suggestion-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 0.55rem;
    }
    .rp-chat-suggestion {
      display: block;
      min-width: 0;
      padding: 0.72rem;
      border: 1px solid #dbe4ee;
      border-left: 5px solid #39729e;
      border-radius: 8px;
      background: #ffffff;
      color: #172033;
      cursor: pointer;
    }
    .rp-chat-suggestion.suggestion {
      text-decoration: none;
      padding-inline: 0.72rem;
    }
    .rp-chat-suggestion.suggestion::after {
      content: 'Run';
      display: inline-flex;
      align-items: center;
      min-height: 1.35rem;
      margin-top: 0.45rem;
      padding: 0 0.45rem;
      border-radius: 999px;
      background: #edf3f9;
      color: #39729e;
      font-size: 0.65rem;
      font-weight: 780;
      text-decoration: none;
    }
    .rp-chat-suggestion:hover {
      border-color: rgba(255, 117, 24, 0.45);
      background: #fffaf5;
    }
    .rp-chat-suggestion-title {
      display: block;
      color: #39729e;
      font-size: 0.78rem;
      font-weight: 780;
      line-height: 1.2;
    }
    .rp-chat-suggestion-body {
      display: block;
      margin-top: 0.25rem;
      color: #455468;
      font-size: 0.72rem;
      line-height: 1.3;
    }
    .rp-handoff {
      display: grid;
      gap: 0.45rem;
      color: #344054;
      font-size: 0.86rem;
    }
    .rp-pill-row {
      display: flex;
      flex-wrap: wrap;
      gap: 0.35rem;
    }
    .rp-pill {
      display: inline-flex;
      align-items: center;
      min-height: 1.6rem;
      padding: 0.15rem 0.45rem;
      border-radius: 999px;
      background: #edf3f9;
      color: #39729e;
      font-size: 0.72rem;
      font-weight: 700;
    }
    .rp-contract {
      display: grid;
      gap: 0.55rem;
      color: #344054;
      font-size: 0.82rem;
    }
    .rp-contract-title {
      color: #172033;
      font-weight: 760;
    }
    .rp-code {
      display: block;
      margin-top: 0.18rem;
      padding: 0.35rem 0.45rem;
      border-radius: 6px;
      background: #f8fafc;
      color: #243b53;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
        'Liberation Mono', monospace;
      font-size: 0.72rem;
      overflow-wrap: anywhere;
    }
    .rp-callout {
      display: grid;
      gap: 0.35rem;
      padding: 0.65rem;
      border-left: 5px solid #39729e;
      border-radius: 6px;
      background: #eef7fb;
      color: #243b53;
      font-size: 0.8rem;
    }
    .rp-callout strong {
      color: #172033;
    }
    .rp-key-table td:first-child {
      width: 42%;
      color: #667085;
      font-weight: 760;
    }
    .rp-meeting-note {
      display: grid;
      gap: 0.45rem;
      padding: 0.75rem;
      border-left: 5px solid #087443;
      border-radius: 6px;
      background: #f0fdf4;
      color: #253b2d;
      font-size: 0.84rem;
    }
    .rp-meeting-note strong {
      color: #172033;
    }
    .rp-skill-card {
      display: grid;
      gap: 0.65rem;
      padding: 0.8rem;
      color: #172033;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI',
        sans-serif;
      font-size: 13px;
      line-height: 1.35;
      background: #ffffff;
    }
    .rp-skill-header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 0.65rem;
      border-bottom: 1px solid #e4e7ec;
      padding-bottom: 0.6rem;
    }
    .rp-skill-title {
      margin: 0;
      font-size: 1rem;
      line-height: 1.18;
      font-weight: 760;
    }
    .rp-skill-subtitle {
      margin: 0.15rem 0 0;
      color: #667085;
      font-size: 0.78rem;
    }
    .rp-badge {
      flex: 0 0 auto;
      border-radius: 999px;
      padding: 0.22rem 0.55rem;
      background: #edf3f9;
      color: #39729e;
      font-size: 0.7rem;
      font-weight: 760;
    }
    .rp-controls {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(135px, 1fr));
      gap: 0.55rem;
    }
    .rp-skill-card label {
      display: block;
      margin-bottom: 0.18rem;
      color: #344054;
      font-size: 0.72rem;
      font-weight: 700;
    }
    .rp-skill-card select,
    .rp-skill-card input:not([type='checkbox']) {
      width: 100%;
      min-height: 31px;
      border: 1px solid #cfd6df;
      border-radius: 6px;
      padding: 0.25rem 0.45rem;
      background: #ffffff;
      color: #172033;
      font-size: 0.8rem;
    }
    .rp-output-grid {
      display: grid;
      grid-template-columns: minmax(0, 0.9fr) minmax(0, 1.1fr);
      gap: 0.65rem;
      align-items: start;
    }
    .rp-output {
      min-width: 0;
      border-top: 1px solid #e4e7ec;
      padding-top: 0.55rem;
    }
    .rp-output-wide {
      grid-column: 1 / -1;
    }
    .rp-output-label {
      margin-bottom: 0.35rem;
      color: #667085;
      font-size: 0.68rem;
      font-weight: 760;
      text-transform: uppercase;
      letter-spacing: 0;
    }
    .rp-skill-card pre.shinymcp-output {
      white-space: normal !important;
      overflow: visible !important;
      color: #172033;
      font-family: inherit !important;
      font-size: 0.82rem !important;
      line-height: 1.4;
    }
    .rp-skill-card [data-shinymcp-output-type='plot'] img {
      display: block;
      width: 100%;
      max-height: 230px;
      object-fit: contain;
    }
    .rp-skill-card table,
    .rp-panel table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.76rem;
    }
    .rp-skill-card th,
    .rp-skill-card td,
    .rp-panel th,
    .rp-panel td {
      border-bottom: 1px solid #e4e7ec;
      padding: 0.32rem 0.38rem;
      text-align: left;
      vertical-align: top;
    }
    .rp-skill-card th,
    .rp-panel th {
      color: #344054;
      background: #f8fafc;
      font-weight: 760;
    }
    .rp-audit {
      display: grid;
      gap: 0.45rem;
      border-left: 5px solid #39729e;
      padding: 0.65rem;
      background: #edf3f9;
      color: #243b53;
      font-size: 0.8rem;
    }
    .rp-audit strong {
      color: #172033;
    }
    @media (max-width: 900px) {
      .rp-band::after {
        opacity: 0.28;
        right: -4.5rem;
      }
      .rp-hero-content {
        grid-template-columns: 1fr;
      }
      .rp-dashboard,
      .rp-output-grid,
      .rp-explain-grid,
      .rp-host-strip,
      .rp-benefit-grid,
      .rp-chat-suggestion-grid {
        grid-template-columns: 1fr;
      }
      .rp-chat-footer {
        align-items: flex-start;
      }
      .rp-output-wide {
        grid-column: auto;
      }
    }
  "
  ))
}

pct <- function(x, digits = 1) {
  paste0(round(100 * x, digits), "%")
}

fmt_int <- function(x) {
  format(round(x), big.mark = ",", trim = TRUE)
}

as_num <- function(x, default = 0) {
  if (is.null(x) || identical(x, "")) {
    return(default)
  }
  value <- suppressWarnings(as.numeric(x))
  if (is.na(value)) default else value
}

ae_column <- function(ae_term) {
  switch(
    ae_term,
    "Neutropenia" = "neutropenia_grade",
    "Fatigue" = "fatigue_grade",
    "Nausea" = "nausea_grade",
    "Rash" = "rash_grade",
    "ALT increased" = "alt_grade",
    "neutropenia_grade"
  )
}

cohort_choices <- c("All cohorts", sort(unique(trial_data$cohort)))
ae_terms <- c("Neutropenia", "Fatigue", "Nausea", "Rash", "ALT increased")

skill_shell <- function(title, subtitle, controls, ...) {
  tags$main(
    class = "rp-skill-card",
    trial_css(),
    tags$header(
      class = "rp-skill-header",
      tags$div(
        tags$h1(class = "rp-skill-title", title),
        tags$p(class = "rp-skill-subtitle", subtitle)
      ),
      tags$span(class = "rp-badge", "MCP skill")
    ),
    tags$section(class = "rp-controls", controls),
    ...
  )
}

output_pane <- function(label, output, wide = FALSE) {
  tags$section(
    class = paste(
      "rp-output",
      if (isTRUE(wide)) "rp-output-wide" else ""
    ),
    tags$div(class = "rp-output-label", label),
    output
  )
}

safety_signal_app <- function(data = trial_data) {
  ui <- skill_shell(
    "Safety Signal Scout",
    "A deterministic clinical AI skill: screen aggregate AE risk before sending a review memo.",
    tagList(
      mcp_select("cohort", "Cohort", cohort_choices),
      mcp_select("ae_term", "AE term", ae_terms),
      mcp_numeric_input(
        "grade_threshold",
        "Minimum grade",
        value = 3,
        min = 1,
        max = 4,
        step = 1
      ),
      mcp_numeric_input(
        "risk_limit",
        "RR watch limit",
        value = 1.8,
        min = 1,
        max = 5,
        step = 0.1
      )
    ),
    output_pane("Review memo", mcp_text("memo"), wide = TRUE),
    tags$section(
      class = "rp-output-grid",
      output_pane("Evidence table", mcp_table("evidence")),
      output_pane("Event-rate view", mcp_plot("risk_plot", height = "220px")),
      output_pane("Audit and guardrails", mcp_html("audit"), wide = TRUE)
    )
  )

  tool <- ellmer::tool(
    fun = function(
      cohort = "All cohorts",
      ae_term = "Neutropenia",
      grade_threshold = 3,
      risk_limit = 1.8
    ) {
      grade_threshold <- as_num(grade_threshold, 3)
      risk_limit <- as_num(risk_limit, 1.8)
      source_data <- data
      if (!identical(cohort, "All cohorts")) {
        source_data <- source_data[source_data$cohort == cohort, , drop = FALSE]
      }

      grade_col <- ae_column(ae_term)
      source_data$event <- source_data[[grade_col]] >= grade_threshold
      by_arm <- split(source_data, source_data$arm)
      arms <- c("Control", "Investigational")
      counts <- lapply(arms, function(arm) {
        arm_data <- by_arm[[arm]]
        n <- if (is.null(arm_data)) 0 else nrow(arm_data)
        events <- if (is.null(arm_data)) 0 else sum(arm_data$event)
        list(
          arm = arm,
          n = n,
          events = events,
          rate = if (n == 0) 0 else events / n
        )
      })
      names(counts) <- arms

      control <- counts$Control
      investigational <- counts$Investigational
      rr <- ((investigational$events + 0.5) / (investigational$n + 1)) /
        ((control$events + 0.5) / (control$n + 1))
      risk_delta <- investigational$rate - control$rate
      small_cell <- min(control$events, investigational$events) < 5
      decision <- if (rr >= risk_limit && investigational$events >= 5) {
        "Open a focused safety review"
      } else if (rr >= risk_limit || small_cell) {
        "Monitor and request QC"
      } else {
        "No immediate signal"
      }

      evidence <- data.frame(
        arm = arms,
        subjects = vapply(counts, `[[`, numeric(1), "n"),
        events = vapply(counts, `[[`, numeric(1), "events"),
        rate = vapply(counts, function(x) pct(x$rate), character(1)),
        check.names = FALSE
      )
      evidence$`risk ratio vs control` <- c("-", round(rr, 2))

      memo <- paste(
        decision,
        "for",
        ae_term,
        "grade",
        paste0(">=", grade_threshold),
        "in",
        tolower(cohort),
        ". Investigational rate:",
        pct(investigational$rate),
        "vs control:",
        pct(control$rate),
        "with RR",
        round(rr, 2),
        "and absolute delta",
        pct(risk_delta),
        "."
      )

      audit <- tags$div(
        class = "rp-audit",
        tags$div(
          tags$strong("Source:"),
          " synthetic subject-level oncology data"
        ),
        tags$div(
          tags$strong("Guardrail:"),
          " aggregate counts only; no patient rows leave the widget"
        ),
        tags$div(
          tags$strong("QC trigger:"),
          if (small_cell) {
            " small event cells require statistician review"
          } else {
            " event cells clear the minimum-count check"
          }
        ),
        tags$div(
          tags$strong("Reproducibility:"),
          " deterministic R function, fixed seed, explicit thresholds"
        )
      )

      list(
        memo = mcp_result_text(
          memo,
          model_value = list(
            widget = "Safety Signal Scout",
            cohort = cohort,
            ae_term = ae_term,
            grade_threshold = grade_threshold,
            risk_ratio = rr,
            risk_delta = risk_delta,
            decision = decision,
            small_cell = small_cell
          )
        ),
        evidence = mcp_result_table(
          evidence,
          text = "Aggregate AE evidence table."
        ),
        risk_plot = mcp_result_plot(
          function() {
            rates <- vapply(counts, function(x) x$rate, numeric(1))
            colors <- c("#39729e", "#ff7518")
            barplot(
              rates * 100,
              names.arg = arms,
              col = colors,
              border = NA,
              ylim = c(0, max(8, max(rates * 100) * 1.28)),
              ylab = "Event rate (%)",
              main = paste(ae_term, "grade", paste0(">=", grade_threshold))
            )
            abline(
              h = control$rate * 100 * risk_limit,
              lty = 2,
              col = "#39729e"
            )
            grid(nx = NA, ny = NULL, col = "#d9e3e6")
          },
          model_value = list(
            arm = arms,
            event_rate = vapply(counts, function(x) x$rate, numeric(1))
          ),
          text = "Bar chart of event rates by arm."
        ),
        audit = mcp_result_html(
          audit,
          text = paste("Audit guardrails for", ae_term, "review.")
        )
      )
    },
    name = "screen_safety_signal",
    description = "Screen aggregate AE risk and return a guarded safety-review memo.",
    arguments = list(
      cohort = type_string("Cohort to inspect, or All cohorts."),
      ae_term = type_string("Adverse event term."),
      grade_threshold = type_number(
        "Minimum AE grade included in the signal screen."
      ),
      risk_limit = type_number(
        "Relative risk limit that triggers watch status."
      )
    )
  )

  mcp_app(
    ui = ui,
    tools = list(tool),
    name = "rpharma-safety-signal",
    # Declared result shape: the contract now covers outputs, not just
    # inputs. The contract inspector renders this schema.
    tool_outputs = list(
      screen_safety_signal = c("memo", "evidence", "risk_plot", "audit")
    ),
    prefers_border = TRUE
  )
}

enrollment_rescue_app <- function(data = trial_data) {
  ui <- skill_shell(
    "Enrollment Rescue Simulator",
    "Stress-test screen failures, visit slippage, and data queries before the next study team meeting.",
    tagList(
      mcp_numeric_input(
        "target_subjects",
        "Target subjects",
        value = 520,
        min = 100,
        step = 10
      ),
      mcp_numeric_input(
        "monthly_randomized",
        "Randomized/month",
        value = 54,
        min = 5,
        step = 1
      ),
      mcp_numeric_input(
        "screen_failure_rate",
        "Screen failure %",
        value = 16,
        min = 0,
        max = 80,
        step = 1
      ),
      mcp_numeric_input(
        "query_reduction",
        "Query reduction %",
        value = 30,
        min = 0,
        max = 90,
        step = 5
      )
    ),
    output_pane("Study-team brief", mcp_text("brief"), wide = TRUE),
    tags$section(
      class = "rp-output-grid",
      output_pane(
        "Milestone forecast",
        mcp_plot("timeline_plot", height = "220px")
      ),
      output_pane("Action plan", mcp_table("actions"))
    )
  )

  tool <- ellmer::tool(
    fun = function(
      target_subjects = 520,
      monthly_randomized = 54,
      screen_failure_rate = 16,
      query_reduction = 30
    ) {
      target_subjects <- as_num(target_subjects, 520)
      monthly_randomized <- as_num(monthly_randomized, 54)
      screen_failure_rate <- as_num(screen_failure_rate, 16) / 100
      query_reduction <- as_num(query_reduction, 30) / 100

      current_randomized <- nrow(data) - sum(data$screen_failure)
      remaining <- max(target_subjects - current_randomized, 0)
      months_to_target <- ceiling(remaining / max(monthly_randomized, 1))
      needed_screened <- ceiling(remaining / max(1 - screen_failure_rate, 0.05))
      open_queries <- sum(data$query_open)
      avoided_queries <- round(open_queries * query_reduction)
      current_missing_visits <- sum(data$missing_visit)

      months <- 0:max(months_to_target, 6)
      cumulative <- pmin(
        current_randomized + monthly_randomized * months,
        target_subjects
      )

      status <- if (months_to_target <= 4) {
        "on track"
      } else if (months_to_target <= 7) {
        "watch"
      } else {
        "rescue needed"
      }

      actions <- data.frame(
        move = c(
          "Prioritize screens",
          "Reduce data friction",
          "Protect visit windows",
          "Document assumptions"
        ),
        recommendation = c(
          paste(
            "Screen",
            fmt_int(needed_screened),
            "candidates to fill the remaining randomized target."
          ),
          paste(
            "Close or prevent about",
            fmt_int(avoided_queries),
            "queries with the proposed workflow."
          ),
          paste(
            "Review",
            fmt_int(current_missing_visits),
            "missing visits before the next DMC cut."
          ),
          "Keep the deterministic scenario inputs with the meeting notes."
        ),
        check.names = FALSE
      )

      brief <- paste(
        "Enrollment is",
        status,
        ":",
        fmt_int(current_randomized),
        "randomized now,",
        fmt_int(remaining),
        "remaining, and an estimated",
        months_to_target,
        "months to target at",
        fmt_int(monthly_randomized),
        "randomized/month."
      )

      list(
        brief = mcp_result_text(
          brief,
          model_value = list(
            widget = "Enrollment Rescue Simulator",
            current_randomized = current_randomized,
            target_subjects = target_subjects,
            remaining = remaining,
            months_to_target = months_to_target,
            status = status,
            avoided_queries = avoided_queries
          )
        ),
        actions = mcp_result_table(
          actions,
          text = "Enrollment rescue action plan."
        ),
        timeline_plot = mcp_result_plot(
          function() {
            plot(
              months,
              cumulative,
              type = "o",
              pch = 19,
              lwd = 2,
              col = "#087443",
              xlab = "Months from now",
              ylab = "Randomized subjects",
              main = "Randomization path"
            )
            abline(h = target_subjects, lty = 2, col = "#ff7518")
            grid(col = "#d9e3e6")
          },
          model_value = list(month = months, randomized = cumulative),
          text = "Line chart showing projected randomization against target."
        )
      )
    },
    name = "simulate_enrollment_rescue",
    description = "Forecast enrollment timing and propose a simple data-quality action plan.",
    arguments = list(
      target_subjects = type_number("Final randomized subject target."),
      monthly_randomized = type_number(
        "Expected randomized subjects per month."
      ),
      screen_failure_rate = type_number("Expected screen failure percentage."),
      query_reduction = type_number("Expected query reduction percentage.")
    )
  )

  mcp_app(
    ui = ui,
    tools = list(tool),
    name = "rpharma-enrollment-rescue",
    tool_outputs = list(
      simulate_enrollment_rescue = c("brief", "timeline_plot", "actions")
    ),
    prefers_border = TRUE
  )
}

metric_box <- function(label, value, note) {
  tags$div(
    class = "rp-metric",
    tags$div(class = "rp-metric-label", label),
    tags$div(class = "rp-metric-value", value),
    tags$div(class = "rp-metric-note", note)
  )
}

result_model_value <- function(result) {
  if (is.null(result)) {
    return(NULL)
  }

  for (value in result) {
    if (inherits(value, "shinymcp_result") && !is.null(value$model_value)) {
      return(value$model_value)
    }
  }

  NULL
}

active_tool_definition <- function(app) {
  app$tool_definitions()[[1]]
}

benefit_card <- function(step, title, body, value = NULL, live = FALSE) {
  tags$div(
    class = "rp-benefit-card",
    `data-live` = if (isTRUE(live)) "true" else "false",
    tags$div(class = "rp-benefit-step", step),
    tags$div(class = "rp-benefit-title", title),
    tags$div(class = "rp-benefit-body", body),
    if (!is.null(value)) {
      tags$code(class = "rp-benefit-value", value)
    }
  )
}

benefit_panel <- function(app, result) {
  definition <- active_tool_definition(app)
  model <- result_model_value(result)
  received <- if (is.null(model)) {
    "Waiting for Apply"
  } else {
    model$decision %||% model$status %||% "Structured result received"
  }
  action <- if (is.null(model)) {
    "No downstream note yet"
  } else if (identical(model$widget, "Safety Signal Scout")) {
    "Study-team safety follow-up is ready"
  } else {
    "Enrollment action plan is ready"
  }

  tags$section(
    class = "rp-benefit-grid",
    benefit_card(
      "1. Approved skill",
      "The dropdown swaps a complete MCP App",
      "This is not just a hidden Shiny tab. The selected skill carries its own UI, tool, schema, and output contract.",
      app$name
    ),
    benefit_card(
      "2. Agent contract",
      "The inputs are inspectable before execution",
      "An agent can call this tool by name with explicit arguments instead of guessing from the screen.",
      paste0(
        definition$name,
        "(",
        length(definition$inputSchema$properties),
        " args)"
      )
    ),
    benefit_card(
      "3. Structured handoff",
      "The parent app receives data, not scraped text",
      "After Apply, the host gets a typed result it can route, summarize, or audit.",
      received,
      live = !is.null(model)
    ),
    benefit_card(
      "4. Portable UI",
      "The same card can run elsewhere",
      "The visible widget is linked to a ui:// resource and can also be used in shinychat or an MCP host.",
      action,
      live = !is.null(model)
    )
  )
}

model_rows <- function(model) {
  if (is.null(model)) {
    return(data.frame(field = character(), value = character()))
  }

  if (identical(model$widget, "Safety Signal Scout")) {
    return(data.frame(
      field = c(
        "Skill",
        "Decision",
        "Cohort",
        "AE term",
        "Risk ratio",
        "Risk delta",
        "QC flag"
      ),
      value = c(
        model$widget,
        model$decision,
        model$cohort,
        model$ae_term,
        round(model$risk_ratio, 2),
        pct(model$risk_delta),
        if (isTRUE(model$small_cell)) "small event cell" else "cell counts OK"
      ),
      check.names = FALSE
    ))
  }

  data.frame(
    field = c(
      "Skill",
      "Status",
      "Randomized now",
      "Remaining",
      "Months to target",
      "Avoided queries"
    ),
    value = c(
      model$widget,
      model$status,
      fmt_int(model$current_randomized),
      fmt_int(model$remaining),
      model$months_to_target,
      fmt_int(model$avoided_queries)
    ),
    check.names = FALSE
  )
}

chat_suggestion_card <- function(title, body, prompt) {
  tags$span(
    class = "rp-chat-suggestion suggestion submit",
    `data-suggestion` = prompt,
    tags$span(class = "rp-chat-suggestion-title", title),
    tags$span(class = "rp-chat-suggestion-body", body)
  )
}

chat_welcome_message <- function() {
  tags$div(
    class = "rp-chat-welcome",
    tags$div(
      tags$strong("Study assistant."),
      " This shinychat panel uses startup messages, submit-ready suggestion cards, and shinymcp tool-result cards."
    ),
    tags$div(
      "Pick a card or type a request. The response is the same approved MCP App, rendered as a chat-native tool card with the call arguments attached."
    ),
    tags$div(
      class = "rp-chat-suggestion-grid",
      chat_suggestion_card(
        "Safety signal screen",
        "Run the current cohort and AE lens through the Safety Signal Scout.",
        "Screen the current safety lens with the approved MCP skill."
      ),
      chat_suggestion_card(
        "Enrollment rescue plan",
        "Open the enrollment simulator as a chat tool card.",
        "Build an enrollment rescue plan with the MCP simulator."
      ),
      chat_suggestion_card(
        "Study-team packet",
        "Return both cards for a meeting-ready handoff.",
        "Prepare both the safety screen and enrollment rescue packet."
      ),
      chat_suggestion_card(
        "Live update check",
        "Open a chat card that reruns when inputs change.",
        "Show how live card updates work in shinychat."
      )
    )
  )
}

chat_footer_message <- function() {
  tags$div(
    class = "rp-chat-footer",
    tags$div(
      class = "rp-chat-footer-copy",
      tags$strong("Footer guardrail."),
      " Suggestions call approved aggregate tools. Chat cards auto-update on debounce; dashboard embeds use Apply for deliberate reruns."
    ),
    tags$div(
      class = "rp-chat-footer-chips",
      tags$span(class = "rp-chat-footer-chip", "No patient rows"),
      tags$span(class = "rp-chat-footer-chip", "Tool args visible"),
      tags$span(class = "rp-chat-footer-chip", "ui:// portable")
    )
  )
}

chat_panel <- function(height = "620px") {
  tags$section(
    class = "rp-chat-section",
    card(
      class = "rp-chat-card",
      full_screen = TRUE,
      card_header(
        tags$div(
          tags$div(class = "rp-chat-heading", "shinychat study assistant"),
          tags$div(
            class = "rp-chat-subtitle",
            "A chat-native route to the same shinymcp cards, using welcome content and clickable suggestions."
          )
        ),
        tags$span(class = "rp-chat-mode", "auto-update cards")
      ),
      card_body(
        class = "rp-chat-body",
        chat_ui(
          "study_chat",
          greeting = chat_greeting(chat_welcome_message()),
          placeholder = "Ask for a safety screen, enrollment plan, or both...",
          width = "100%",
          height = height,
          fill = FALSE,
          footer = chat_footer_message()
        )
      )
    )
  )
}

chat_route <- function(message) {
  message <- tolower(message %||% "")

  if (grepl("both|packet|meeting|handoff|study-team", message)) {
    return("both")
  }
  if (grepl("live|update|auto|rerun|refresh|debounce", message)) {
    return("live_update")
  }
  if (grepl("enroll|random|rescue|screen failure|query|milestone", message)) {
    return("enrollment")
  }
  "safety"
}

chat_intro <- function(route) {
  switch(
    route,
    safety = paste(
      "Running the Safety Signal Scout with the dashboard cohort and AE lens.",
      "The card below is a shinymcp app rendered through shinychat's tool-result UI."
    ),
    enrollment = paste(
      "Running the Enrollment Rescue Simulator as a chat tool card.",
      "The result keeps the interactive MCP card and the structured handoff together."
    ),
    live_update = paste(
      "Opening the Safety Signal Scout in shinychat's live-card mode.",
      "Change an input inside the card and it reruns on debounce; no Apply button is needed in this chat surface."
    ),
    both = paste(
      "Preparing both approved MCP skills for a study-team packet.",
      "Each result is an independent shinymcp card that can move between Shiny, shinychat, and an MCP host."
    )
  )
}

handoff_view <- function(result) {
  if (is.null(result)) {
    return(tags$div(
      class = "rp-handoff",
      tags$div(
        "Run a widget with the Apply button to see what the embedded MCP App sends back to the Shiny host."
      )
    ))
  }

  model <- result_model_value(result)
  if (is.null(model)) {
    return(tags$div(
      class = "rp-handoff",
      "The widget returned display content but no model handoff."
    ))
  }

  rows <- model_rows(model)
  tags$div(
    class = "rp-handoff",
    tags$div(
      class = "rp-callout",
      tags$strong("What shinymcp adds here"),
      tags$div(
        "The iframe rendered the card for the user, but the parent Shiny app also received this structured model value from the MCP tool result."
      )
    ),
    tags$div(
      class = "rp-pill-row",
      tags$span(class = "rp-pill", model$widget %||% "MCP widget"),
      tags$span(
        class = "rp-pill",
        model$decision %||% model$status %||% "ready"
      )
    ),
    tags$table(
      class = "rp-key-table",
      tags$tbody(lapply(seq_len(nrow(rows)), function(i) {
        tags$tr(
          tags$td(rows$field[[i]]),
          tags$td(rows$value[[i]])
        )
      }))
    )
  )
}

host_strip <- function(app) {
  uri <- app$resource_uri()
  tags$div(
    class = "rp-host-strip",
    tags$div(
      class = "rp-host-chip",
      tags$strong("Shiny host"),
      tags$span("mcp_host_server(...)")
    ),
    tags$div(
      class = "rp-host-chip",
      tags$strong("shinychat tool"),
      tags$span("as_shinychat_tool(...)")
    ),
    tags$div(
      class = "rp-host-chip",
      tags$strong("MCP resource"),
      tags$span(uri)
    )
  )
}

contract_view <- function(app) {
  definition <- active_tool_definition(app)
  properties <- definition$inputSchema$properties %||% list()
  fields <- data.frame(
    argument = names(properties),
    type = vapply(
      properties,
      function(prop) prop$type %||% "string",
      character(1)
    ),
    description = vapply(
      properties,
      function(prop) prop$description %||% "",
      character(1)
    ),
    check.names = FALSE
  )

  schema_table <- function(rows, key_header) {
    tags$table(
      tags$thead(
        tags$tr(
          tags$th(key_header),
          tags$th("type"),
          tags$th("description")
        )
      ),
      tags$tbody(lapply(seq_len(nrow(rows)), function(i) {
        tags$tr(
          tags$td(rows[[1]][[i]]),
          tags$td(rows$type[[i]]),
          tags$td(rows$description[[i]])
        )
      }))
    )
  }

  # The declared result shape (outputSchema): the contract covers what the
  # tool returns, not just what the client may send.
  output_properties <- definition$outputSchema$properties %||% list()
  result_fields <- data.frame(
    `result key` = names(output_properties),
    type = vapply(
      output_properties,
      function(prop) prop$type %||% "string",
      character(1)
    ),
    description = vapply(
      output_properties,
      function(prop) prop$description %||% "",
      character(1)
    ),
    check.names = FALSE
  )

  tags$div(
    class = "rp-contract",
    tags$div(
      tags$div(class = "rp-contract-title", "Tool contract"),
      tags$code(class = "rp-code", definition$name),
      tags$code(class = "rp-code", app$resource_uri())
    ),
    tags$div(definition$description),
    schema_table(fields, "argument"),
    if (nrow(result_fields) > 0) {
      tagList(
        tags$div(
          class = "rp-contract-title",
          style = "margin-top: 0.6rem;",
          "Declared result (outputSchema)"
        ),
        schema_table(result_fields, "result key")
      )
    }
  )
}

meeting_note_view <- function(result) {
  model <- result_model_value(result)
  if (is.null(model)) {
    return(tags$div(
      class = "rp-meeting-note",
      tags$strong("Meeting-note handoff"),
      tags$div(
        "Run the selected widget to generate a structured study-team note."
      )
    ))
  }

  if (identical(model$widget, "Safety Signal Scout")) {
    note <- paste(
      "Safety follow-up:",
      model$decision,
      "for",
      model$ae_term,
      "in",
      tolower(model$cohort),
      "with RR",
      round(model$risk_ratio, 2),
      "and risk delta",
      pct(model$risk_delta),
      "."
    )
    next_step <- if (isTRUE(model$small_cell)) {
      "Statistician review required because event cells are small."
    } else {
      "Attach aggregate evidence and audit trail to the study-team packet."
    }
  } else {
    note <- paste(
      "Enrollment follow-up:",
      fmt_int(model$current_randomized),
      "randomized,",
      fmt_int(model$remaining),
      "remaining,",
      model$months_to_target,
      "months to target, status",
      model$status,
      "."
    )
    next_step <- paste(
      "Route the query-reduction plan to data management; expected avoided queries:",
      fmt_int(model$avoided_queries),
      "."
    )
  }

  tags$div(
    class = "rp-meeting-note",
    tags$strong("Meeting-note handoff"),
    tags$div(note),
    tags$div(next_step)
  )
}

comparison_panel <- function() {
  tags$section(
    class = "rp-explain-grid",
    tags$div(
      class = "rp-compare",
      `data-kind` = "shiny",
      tags$h2("Typical Shiny app"),
      tags$ul(
        tags$li("Outputs are primarily human-facing plots, tables, and text."),
        tags$li(
          "Other systems usually need app-specific glue or DOM scraping."
        ),
        tags$li("A module is tied to the Shiny app that hosts it.")
      )
    ),
    tags$div(
      class = "rp-compare",
      `data-kind` = "mcp",
      tags$h2("Same workflow with shinymcp"),
      tags$ul(
        tags$li("The widget is also a tool with a schema an agent can call."),
        tags$li("Results include display output plus structured model values."),
        tags$li("The same card can run in Shiny, shinychat, or any MCP host.")
      )
    )
  )
}

demo_theme <- function() {
  bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary = "#39729e",
    secondary = "#ff7518",
    success = "#087443"
  )
}

navbar_title <- function() {
  tags$span(
    class = "rp-navbar-brand",
    tags$span(class = "rp-navbar-mark", "R"),
    HTML("R<span class=\"rp-wordmark-slash\">/</span>Pharma shinymcp")
  )
}

masthead <- function() {
  tags$section(
    class = "rp-band",
    tags$div(
      class = "rp-brand-row",
      tags$div(
        class = "rp-brand-lockup",
        tags$span(class = "rp-brand-mark", "R"),
        tags$div(
          class = "rp-wordmark",
          HTML("R<span class=\"rp-wordmark-slash\">/</span>Pharma")
        )
      ),
      tags$div(class = "rp-event-pill", "genAI Day | June 16")
    ),
    tags$div(
      class = "rp-hero-content",
      tags$div(
        tags$div(class = "rp-eyebrow", "Hands-on clinical AI demo"),
        tags$h1(class = "rp-title", "Oncology Signal Room"),
        tags$p(
          class = "rp-subtitle",
          "A normal Shiny clinical dashboard with a safe MCP widget bay. The widgets are deterministic R tools wrapped as portable MCP Apps, so they can run in Shiny, chat, or an MCP host."
        )
      ),
      tags$aside(
        class = "rp-hero-card",
        tags$div(class = "rp-hero-card-label", "Community theme"),
        tags$div(
          class = "rp-hero-card-value",
          "Open source R for drug development"
        ),
        tags$div(
          class = "rp-hero-card-note",
          "Collegial, vendor-free workflow built for the R/Pharma audience."
        )
      )
    )
  )
}

dashboard_page <- function() {
  layout_sidebar(
    class = "rp-layout",
    sidebar = sidebar(
      width = 315,
      title = "Study controls",
      selectInput("cohort", "Cohort", cohort_choices),
      selectInput("ae", "AE lens", ae_terms, selected = "Neutropenia"),
      sliderInput(
        "site_floor",
        "Minimum site subjects",
        min = 5,
        max = 45,
        value = 12,
        step = 1
      ),
      selectInput(
        "active_widget",
        "Approved MCP skill",
        choices = c(
          "Safety Signal Scout" = "safety",
          "Enrollment Rescue Simulator" = "enrollment"
        )
      ),
      tags$div(
        class = "rp-note",
        "Synthetic data only. The demo intentionally returns aggregate evidence and audit metadata rather than patient-level rows."
      )
    ),
    uiOutput("benefit_panel"),
    comparison_panel(),
    tags$section(
      class = "rp-metrics",
      uiOutput("metric_subjects"),
      uiOutput("metric_response"),
      uiOutput("metric_ae"),
      uiOutput("metric_queries")
    ),
    tags$section(
      class = "rp-dashboard",
      tags$div(
        class = "rp-panel",
        tags$h2("Current study view"),
        plotOutput("study_plot", height = "280px")
      ),
      tags$div(
        class = "rp-panel",
        tags$h2("Site data-quality watchlist"),
        tableOutput("site_table")
      )
    ),
    tags$section(
      class = "rp-dashboard",
      tags$div(
        class = "rp-panel",
        tags$h2("MCP widget bay"),
        uiOutput("host_strip"),
        tags$div(
          class = "rp-widget-copy",
          tags$div(
            "This slot is the part that makes the demo feel like dynamic search widgets: the outer app provides context, while the embedded MCP App owns its own UI, tool schema, result rendering, and model handoff."
          ),
          tags$div(
            "Switch widgets from the sidebar, change inputs inside the iframe, then press Apply."
          )
        ),
        conditionalPanel(
          "input.active_widget == 'safety'",
          mcp_host_ui("safety")
        ),
        conditionalPanel(
          "input.active_widget == 'enrollment'",
          mcp_host_ui("enrollment")
        )
      ),
      tags$div(
        class = "rp-panel",
        tags$h2("Contract inspector"),
        uiOutput("contract"),
        tags$hr(),
        tags$h2("Last widget handoff"),
        uiOutput("handoff"),
        tags$hr(),
        uiOutput("meeting_note")
      )
    )
  )
}

assistant_page <- function() {
  tags$div(
    class = "rp-assistant-page",
    chat_panel(height = "640px")
  )
}

ui <- page_navbar(
  title = navbar_title(),
  theme = demo_theme(),
  fillable = TRUE,
  fillable_mobile = TRUE,
  window_title = "R/Pharma shinymcp demo",
  header = tagList(
    trial_css(),
    masthead()
  ),
  nav_panel("Dashboard", dashboard_page(), value = "dashboard"),
  nav_panel(
    "shinychat assistant",
    assistant_page(),
    value = "shinychat"
  )
)

server <- function(input, output, session) {
  safety_card <- safety_signal_app()
  enrollment_card <- enrollment_rescue_app()

  safety_chat_tool <- as_shinychat_tool(
    safety_card,
    title = function(arguments, ...) {
      paste("Safety Signal Scout -", arguments$ae_term %||% "current AE")
    },
    open = TRUE,
    show_request = TRUE,
    full_screen = TRUE
  )
  enrollment_chat_tool <- as_shinychat_tool(
    enrollment_card,
    title = function(arguments, ...) {
      paste(
        "Enrollment Rescue Simulator -",
        fmt_int(arguments$target_subjects %||% 520),
        "target"
      )
    },
    open = TRUE,
    show_request = TRUE,
    full_screen = TRUE
  )

  safety_host <- mcp_host_server(
    "safety",
    app = safety_card,
    trigger = "submit",
    height = "520px",
    initial_arguments = list(
      cohort = "All cohorts",
      ae_term = "Neutropenia",
      grade_threshold = 3,
      risk_limit = 1.8
    )
  )
  enrollment_host <- mcp_host_server(
    "enrollment",
    app = enrollment_card,
    trigger = "submit",
    height = "520px",
    initial_arguments = list(
      target_subjects = 520,
      monthly_randomized = 54,
      screen_failure_rate = 16,
      query_reduction = 30
    )
  )

  filtered_data <- reactive({
    data <- trial_data
    if (!identical(input$cohort, "All cohorts")) {
      data <- data[data$cohort == input$cohort, , drop = FALSE]
    }
    data
  })

  active_app <- reactive({
    if (identical(input$active_widget, "safety")) {
      safety_card
    } else {
      enrollment_card
    }
  })

  ae_rate <- reactive({
    data <- filtered_data()
    mean(data[[ae_column(input$ae)]] >= 3)
  })

  output$metric_subjects <- renderUI({
    data <- filtered_data()
    metric_box(
      "Subjects",
      fmt_int(nrow(data)),
      paste(input$cohort, "analysis set")
    )
  })

  output$metric_response <- renderUI({
    data <- filtered_data()
    metric_box(
      "Response rate",
      pct(mean(data$response == 1)),
      "synthetic binary endpoint"
    )
  })

  output$metric_ae <- renderUI({
    metric_box("Grade 3+ AE", pct(ae_rate()), input$ae)
  })

  output$metric_queries <- renderUI({
    data <- filtered_data()
    metric_box(
      "Open queries",
      fmt_int(sum(data$query_open)),
      "data-quality load"
    )
  })

  output$study_plot <- renderPlot({
    data <- filtered_data()
    rates <- aggregate(
      cbind(response, grade3 = data[[ae_column(input$ae)]] >= 3) ~ arm,
      data,
      mean
    )
    mat <- rbind(rates$response, rates$grade3) * 100
    colnames(mat) <- rates$arm
    rownames(mat) <- c("Response", paste(input$ae, "G3+"))
    barplot(
      mat,
      beside = TRUE,
      col = c("#39729e", "#ff7518"),
      border = NA,
      ylim = c(0, max(10, max(mat) * 1.25)),
      ylab = "Rate (%)",
      main = paste(input$cohort, "study snapshot")
    )
    legend(
      "topright",
      legend = rownames(mat),
      fill = c("#39729e", "#ff7518"),
      bty = "n"
    )
    grid(nx = NA, ny = NULL, col = "#d9e3e6")
  })

  output$site_table <- renderTable({
    data <- filtered_data()
    site_counts <- aggregate(
      cbind(
        subjects = rep(1, nrow(data)),
        open_queries = data$query_open,
        missing_visits = data$missing_visit
      ) ~ site,
      data,
      sum
    )
    site_counts <- site_counts[
      site_counts$subjects >= input$site_floor,
      ,
      drop = FALSE
    ]
    site_counts$query_rate <- paste0(
      round(100 * site_counts$open_queries / site_counts$subjects, 1),
      "%"
    )
    site_counts$visit_gap_rate <- paste0(
      round(100 * site_counts$missing_visits / site_counts$subjects, 1),
      "%"
    )
    site_counts <- site_counts[
      order(-site_counts$open_queries, -site_counts$missing_visits),
    ]
    head(
      site_counts[, c(
        "site",
        "subjects",
        "open_queries",
        "query_rate",
        "visit_gap_rate"
      )],
      8
    )
  })

  active_result <- reactive({
    if (identical(input$active_widget, "safety")) {
      safety_host$last_raw_result()
    } else {
      enrollment_host$last_raw_result()
    }
  })

  output$handoff <- renderUI({
    handoff_view(active_result())
  })

  output$benefit_panel <- renderUI({
    benefit_panel(active_app(), active_result())
  })

  observeEvent(input$study_chat_user_input, {
    route <- chat_route(input$study_chat_user_input)
    chat_append("study_chat", chat_intro(route))

    if (route %in% c("safety", "both", "live_update")) {
      chat_append(
        "study_chat",
        safety_chat_tool(
          cohort = input$cohort %||% "All cohorts",
          ae_term = input$ae %||% "Neutropenia",
          grade_threshold = 3,
          risk_limit = 1.8
        )
      )
    }

    if (route %in% c("enrollment", "both")) {
      chat_append(
        "study_chat",
        enrollment_chat_tool(
          target_subjects = 520,
          monthly_randomized = 54,
          screen_failure_rate = 16,
          query_reduction = 30
        )
      )
    }
  })

  output$host_strip <- renderUI({
    host_strip(active_app())
  })

  output$contract <- renderUI({
    contract_view(active_app())
  })

  output$meeting_note <- renderUI({
    meeting_note_view(active_result())
  })
}

shinyApp(ui, server)
