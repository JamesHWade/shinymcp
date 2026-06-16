# gepa-demo.R
# Produces the REAL before/after numbers shown in slides-dsprrr.qmd.
#
# Task: support-ticket urgency triage (same classification/enum shape as the
# dsprrr email-classifier example). The annotation rubric is "urgency depends
# on whether the product is usable, NOT on the customer's tone":
#   urgent = core product unusable (can't log in, outage, data loss, payments down)
#   normal = degraded or a blocking question, but the product still works
#   low    = cosmetic / feedback / feature request -- regardless of tone
# A vague baseline prompt triages by emotional tone and gets the tone/usability
# conflicts wrong. GEPA reflects on the training failures and rewrites the
# instruction to encode the rubric.
#
# Run: Rscript talk/scripts/gepa-demo.R   (reads OPENAI_API_KEY from ~/.Renviron)
# Output: talk/scripts/gepa-results.json  (numbers + evolved instruction)

suppressMessages({
  pkgload::load_all("/Users/james/Projects/dsprrr", quiet = TRUE)
  library(ellmer)
})

set.seed(616)

base_dir <- "/Users/james/Projects/shinymcp/inst/examples/rpharma-hangout/talk/scripts"

# Reproducible + cheap: temperature 0 + on-disk cache so re-runs are instant.
configure_cache(
  enable_memory = TRUE,
  enable_disk = TRUE,
  disk_path = file.path(base_dir, ".gepa_cache")
)

llm <- chat_openai(model = "gpt-4o-mini", params = params(temperature = 0))

# --- Baseline module: minimal instruction, rubric NOT stated -----------------
baseline_instructions <- "Classify how urgent this support ticket is: urgent, normal, or low."

triage <- signature(
  "ticket -> urgency: enum('urgent', 'normal', 'low')",
  instructions = baseline_instructions
) |>
  module(type = "predict", template = "Ticket: {ticket}\n\nUrgency:")

# --- Data: rubric = usability, not tone --------------------------------------
trainset <- dsp_trainset(
  ticket = c(
    # urgent: core product unusable (note: some are politely worded)
    "Hi team, just letting you know I can't log into my account at all since this morning.",
    "Our production checkout has been returning errors for the past hour.",
    "I think I deleted a project and all of its data is gone - can it be recovered?",
    # normal: degraded or a blocking question, product still works
    "The dashboard is loading slowly today, but it still works.",
    "Could you tell me how to export my report to CSV?",
    "I get a warning when I save, though the save does seem to go through.",
    # low: cosmetic / feedback / feature request (note: some are angrily worded)
    "I'm FURIOUS - there is a typo on your pricing page!!!",
    "It would be great if you added a dark mode someday.",
    "Just wanted to say the new logo looks fantastic.",
    "Minor thing: the help link in the footer points to the old page."
  ),
  urgency = c(
    "urgent",
    "urgent",
    "urgent",
    "normal",
    "normal",
    "normal",
    "low",
    "low",
    "low",
    "low"
  )
)

# Held-out test: each item is an unambiguous tone/usability conflict, so the
# only way to score well is to follow the rubric instead of the tone.
testset <- dsp_trainset(
  ticket = c(
    "Quick question - I really love the app - but I literally cannot log in right now.",
    "Absolutely disgraceful!! The hero image on your homepage looks blurry!!!",
    "The page is a bit sluggish today, but I still got my work done.",
    "Hi team, no big deal - but none of our saved dashboards will open, they all error out.",
    "Would be nice to have keyboard shortcuts eventually.",
    "I can't complete any payments - the button just does nothing."
  ),
  urgency = c("urgent", "low", "normal", "urgent", "low", "urgent")
)

# --- Metrics ------------------------------------------------------------------
norm <- function(x) tolower(trimws(as.character(x)))

# Plain numeric metric for held-out evaluation.
acc <- function(prediction, expected_row) {
  as.numeric(norm(prediction) == norm(expected_row$urgency))
}

# Feedback-aware metric drives GEPA's reflection (the GEPA-paper mechanism).
# The feedback carries the *annotation rationale* for the label (keyed to the
# label category, not to any test case) -- this is what metric_with_feedback is
# for: turn human labeling guidance into signal the optimizer can compile.
rationale <- function(label) {
  switch(
    label,
    urgent = "the product is unusable or core functionality is broken, regardless of the customer's tone",
    normal = "the product still works but is degraded, or it is a how-to question",
    low = "it is cosmetic, feedback, or a feature request with no functional impact, regardless of tone"
  )
}

fb_metric <- metric_with_feedback(
  function(prediction, expected_row) {
    correct <- norm(prediction) == norm(expected_row$urgency)
    if (correct) {
      list(score = 1, feedback = "Correct.")
    } else {
      list(
        score = 0,
        feedback = paste0(
          "Expected '",
          expected_row$urgency,
          "' because ",
          rationale(expected_row$urgency),
          "; predicted '",
          as.character(prediction),
          "'."
        )
      )
    }
  },
  field = "urgency"
)

# --- BEFORE: evaluate the hand-written baseline on held-out test --------------
message("== Evaluating baseline on held-out test ==")
before <- evaluate(triage, testset, acc, .llm = llm, .progress = FALSE)

# --- COMPILE with GEPA: reflect on training failures, evolve instruction ------
message("== Running GEPA (this makes the LLM calls) ==")
# crossover_rate = 0 + mutation_rate = 1 -> every candidate is a single
# coherent *reflective rewrite* (no parent-concatenation artifacts), which is
# exactly the reflect-on-failures-then-rewrite mechanism we describe.
tp <- GEPA(
  metric = fb_metric,
  population_size = 8L,
  generations = 4L,
  mutation_rate = 1,
  crossover_rate = 0,
  seed = 42,
  verbose = TRUE
)
optimized <- compile(tp, triage, trainset, .llm = llm)

# --- AFTER: evaluate the GEPA-evolved module on the SAME held-out test --------
message("== Evaluating GEPA-optimized module on held-out test ==")
after <- evaluate(optimized, testset, acc, .llm = llm, .progress = FALSE)

evolved_instructions <- optimized$signature@instructions

results <- list(
  model = "gpt-4o-mini",
  optimizer = "GEPA",
  population_size = tp@population_size,
  generations = tp@generations,
  n_train = nrow(trainset),
  n_test = nrow(testset),
  before_score = before$mean_score,
  after_score = after$mean_score,
  before_scores = before$scores,
  after_scores = after$scores,
  before_preds = vapply(before$predictions, as.character, character(1)),
  after_preds = vapply(after$predictions, as.character, character(1)),
  test_ticket = testset$ticket,
  test_truth = testset$urgency,
  baseline_instructions = baseline_instructions,
  evolved_instructions = evolved_instructions
)

cat("\n\n================ RESULTS ================\n")
cat(sprintf(
  "Baseline (hand-written) test accuracy: %.3f (%d/%d)\n",
  results$before_score,
  round(results$before_score * results$n_test),
  results$n_test
))
cat(sprintf(
  "GEPA-optimized       test accuracy: %.3f (%d/%d)\n",
  results$after_score,
  round(results$after_score * results$n_test),
  results$n_test
))
cat("\n--- Baseline instructions ---\n", results$baseline_instructions, "\n")
cat("\n--- GEPA-evolved instructions ---\n", results$evolved_instructions, "\n")
cat("\nPer-example (truth | before -> after):\n")
for (i in seq_len(results$n_test)) {
  cat(sprintf(
    "  %-7s | %-7s -> %-7s  %s\n",
    results$test_truth[i],
    results$before_preds[i],
    results$after_preds[i],
    results$test_ticket[i]
  ))
}

out_json <- file.path(base_dir, "gepa-results.json")
jsonlite::write_json(results, out_json, auto_unbox = TRUE, pretty = TRUE)
cat("\nWrote", out_json, "\n")
