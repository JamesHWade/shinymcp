# R/Pharma GenAI Day Hangout Prep

Event: R/Pharma genAI Day hangout, June 16, 2026

Working title: shinymcp hangout

Tagline: Run Shiny-style R workflows from an MCP client, with controls and results in one card

## Event Frame

- Format: 60-minute hangout/discussion/demo, not a formal conference talk.
- Audience: R/Pharma statisticians, statistical programmers, Shiny developers, data scientists, and platform/governance people.
- Organizer guidance: go technical; live programming, demos, or showing new capabilities are welcome; slides are optional.
- Topic commitment: talk about `shinymcp`, how it works, and demo it.
- Core promise: reviewed Shiny workflows can become MCP Apps: the card collects inputs, the MCP client calls a named R-backed tool, R computes, and the client receives results it can show, summarize, or pass along.
- Default shape: use the 60-minute run-of-show as primary, present `slides.qmd` (organized around the when/why spine), and keep the live demo as the center of gravity.

## Current Assets

- `run-of-show.md`: 60-minute live structure with timing, Q&A, objections, and fallback path.
- `slides.qmd`: primary presentation deck, organized around the when/why decision spine; renders to `slides.html`.
- `slides-succinct.qmd`: earlier 15-slide conversation deck; kept as a lean backup.
- `../app.R`: R/Pharma Oncology Signal Room demo; parsed and served locally with HTTP 200.
- `../README.md`: concise demo overview and teaching points.

## Verified

- Quarto installation is healthy.
- `slides.qmd` renders with `quarto render slides.qmd --to revealjs`.
- `slides-succinct.qmd` also renders (backup deck).
- Required R packages are available: `shiny`, `bslib`, `htmltools`, `ellmer`, `shinychat`, and `shinymcp`.
- Demo app starts locally with `pkgload::load_all(); shiny::runApp("inst/examples/rpharma-hangout", host = "127.0.0.1", port = 7345, launch.browser = FALSE)`.
- Root page returns HTTP 200 and includes the expected R/Pharma shinymcp dashboard content.

## Preparation Priorities

1. Confirm schedule/logistics.
   - Find or request final calendar invite, start time, meeting link, recording policy, and whether a title/abstract is needed.
   - Treat the slot length as confirmed at 50 minutes.

2. Choose final talk shape.
   - Use `run-of-show.md` as the primary plan.
   - Present `slides.qmd` as the deck; skip slides freely when discussion is better.
   - Keep `slides-succinct.qmd` as a lean backup.
   - Open on the when/why question; the asset you trust is reviewed R.
   - Keep the live demo in the talk even if other sections compress.

3. Harden the demo path.
   - Rehearse the Oncology Signal Room click path end to end.
   - Confirm the Safety Signal Scout defaults produce a visible signal.
   - Confirm lowering RR watch limit changes the decision through R logic.
   - Confirm Enrollment Rescue Simulator switch works and the contract inspector updates.
   - Keep a rendered GIF or screenshots open as fallback.

4. Tighten the pharma review story.
   - Say "synthetic data" early and repeatedly.
   - Emphasize aggregate outputs, visible arguments, client-readable result data, and R computation.
   - Avoid implying the client computes clinical numbers or that MCP alone solves data-control policy.

5. Prepare Q&A anchors.
   - Which MCP clients can call it today?
   - Why not client-specific tools?
   - Who computes the clinical numbers?
   - How does patient-data control work?
   - How would this be validated?
   - What does production readiness require?

## Suggested Workback

- June 8-9: confirm logistics, start time, meeting link, recording policy, and title/abstract needs.
- June 10-11: rehearse deck plus demo; trim anything that weakens the core contract story.
- June 12: run package tests/checks relevant to the demo; render final deck.
- June 13: record fallback GIF/screenshots and collect exact demo values.
- June 15: full dress rehearsal from clean R session; prepare links and backup tabs.
- June 16: launch app early, pre-warm one Apply cycle, keep fallback artifacts open.

## Talk Shape Decision

- Primary: 60-minute hangout using `run-of-show.md`, presenting `slides.qmd`.
- Deck role: guide the room through the story; skip slides freely when the discussion is better than the deck.
- Demo role: prove the contract story. Keep the Oncology Signal Room path at 8-10 minutes.
- Optional branch A: if the room is technical, spend more time in `model_value`, schema, and the bridge.
- Optional branch B: if the room is governance-heavy, spend more time on aggregate result data, R computation, review boundaries, and validation.
- Optional branch C: if Q&A starts early, use the seeded questions in `run-of-show.md` rather than forcing more slides.

## Pre-Flight Commands

```bash
cd /Users/james/Projects/shinymcp
Rscript -e 'pkgload::load_all(); parse(file = "inst/examples/rpharma-hangout/app.R"); cat("app parse ok\n")'
cd inst/examples/rpharma-hangout/talk
quarto render slides.qmd --to revealjs
```

```r
pkgload::load_all()
shiny::runApp(
  "inst/examples/rpharma-hangout",
  host = "127.0.0.1",
  port = 7345,
  launch.browser = TRUE
)
```

## Open Questions

- What is the exact start time on June 16?
- Is there a final event page/title/abstract deadline?
- Should the live demo include shinychat, or keep shinychat as a brief optional path?
- Resolved: `slides.qmd` is the deck to present; `slides-succinct.qmd` is the backup.
