# Design: "shinymcp by example" — a teaching ladder of examples

**Date:** 2026-06-14
**Author:** James Wade (with Claude)
**Status:** Draft, pending review

## Problem

`inst/examples/` holds about a dozen example apps, but they sit as a flat, unordered
directory. A newcomer can't tell where to start or how the ideas build on each other. The
R/Pharma genAI Day session ("Shiny components as building blocks for AI agents") wants real
examples that teach one concept at a time and step up in complexity, ending at the
`rpharma-hangout` capstone.

## Goal

Turn the existing examples into an ordered learning path — each rung adds exactly one new
concept — narrated by a single pkgdown article and a slim examples index. Reuse the apps that
already exist; build only the three pieces that are missing. Keep shinymcp the focus;
`{dsprrr}` and `{deputy}` appear once, at the end, as "going further."

## Approach

Curate and order the existing apps; do **not** rename the example directories (renaming would
break tests, vignette links, and `system.file()` paths). The ladder order lives in the
article and the index table, not in directory names. Fill three gaps with small new examples.

### The ladder

Each rung introduces one concept. "exists" = use as-is; "fill" = new work.

| #  | Example dir          | New concept                                                        | Status        |
|----|----------------------|--------------------------------------------------------------------|---------------|
| 1  | `hello-mcp-minimal`  | The smallest MCP App: one `tool()`, one output, `mcp_app()`/`serve()` | **fill (empty today)** |
| 2  | `hello-mcp`          | Inputs and rich outputs (plot, text) via `mcp_*()` components       | exists        |
| 3  | `penguins`           | Native bslib/shiny inputs auto-detected by arg-name == element id   | exists        |
| 4  | `bind-mcp-demo`      | `bindMcp()`: expose only chosen parts of an existing app; some stay private | exists |
| 5  | `multi-tool`         | Several tools plus chained reactives in one app                     | exists        |
| 6  | `module-tool`        | `mcp_tool_module()`: reuse a Shiny module as a tool                 | exists        |
| 7  | `converted-dashboard`| Automatic conversion with `convert_app()` (parse → analyze → generate) | exists (show the process, not just output) |
| 8  | `serve-to-client`    | A headless `serve()` script + `.mcp.json` so a real MCP client calls it | **fill (new dir)** |
| 9  | `shinychat-card`     | Surface a card as a shinychat tool result (`as_shinychat_tool()`)   | exists        |
| 10 | `embed-in-shiny`     | `mcp_host_server()` / `mcp_host_ui()`: Shiny as the review/host surface | **fill (new dir, small)** |
| 11 | `rpharma-hangout`    | Capstone: multi-skill, contract inspector, `model_value` handoff, all three client paths | exists |
| 12 | (none — prose)       | Going further: `{dsprrr}` to tune the prompts, `{deputy}` to let an agent call these tools | links only |

### Gaps to fill

1. **`hello-mcp-minimal/app.R`** — the absolute floor. One `ellmer::tool()` (e.g. summarize a
   built-in dataset), one `mcp_text()` or `mcp_table()` output, `mcp_app()` + `serve()`. Target
   ~15-20 lines so the shape is obvious at a glance. No bslib theme, no plot.

2. **`serve-to-client/`** — focuses on external reach, which every other example does only
   incidentally. Contents: a small `serve.R` that defines an `mcp_app()` and serves it over
   stdio, a `.mcp.json` snippet, and a `README.md` with the exact steps to register the server
   with an MCP client — **Claude Desktop first, then VS Code**. *Implementation note:* confirm `serve()`'s
   transport arguments (stdio vs HTTP) and the resource/tool registration path against current
   `R/serve.R` before writing.

3. **`embed-in-shiny/`** — a minimal Shiny app that embeds one MCP App back into a dashboard with
   `mcp_host_ui()` / `mcp_host_server()`, so readers see "Shiny as the review surface" without the
   full capstone's complexity. *Implementation note:* confirm the host server/ui signatures and
   the submit-vs-auto-update mode against current `R/mcp-app.R` / host code before writing.

### Narration

1. **pkgdown article: `vignettes/shinymcp-by-example.Rmd`** — walks the ladder top to bottom.
   One short section per rung: the concept in a sentence or two, the key code snippet (not the
   whole app), the run command, and one honest line on when the pattern is the wrong choice.
   Final section: "Going further" with `{dsprrr}` and `{deputy}`. Voice: clear and concrete,
   one idea per rung (Hadley/Joe register).

2. **`inst/examples/README.md`** — an ordered table: rung, example, concept, run command. A map
   you can read in ten seconds, sitting next to the code. Links each row to its example dir.

Run command per runnable rung:
`shiny::runApp(system.file("examples", "<dir>", package = "shinymcp"))`.
For `serve-to-client`, the command is an `Rscript` that calls `serve()` plus the client config.

## Out of scope

- Renaming or renumbering existing example directories.
- New `{dsprrr}` or `{deputy}` example apps (they are covered by links only).
- Reworking the existing conversion vignettes (`automatic-conversion.Rmd`,
  `converting-shiny-apps.Rmd`); the article links to them rather than duplicating them.

## Verification

- Each runnable example launches without error (smoke check via `shiny::runApp` or an app-object
  load). Add or extend a test that every `inst/examples/*/app.R` at least parses and builds its
  app object.
- The new article knits cleanly (`pkgdown::build_article("shinymcp-by-example")`).
- All links in the article and index resolve.
- `serve-to-client` actually connects from one real MCP client before the example is called done.

## Resolved decisions

- `serve-to-client` documents **Claude Desktop first, then VS Code**.
- The examples index lives at `inst/examples/README.md` (file only); the `shinymcp-by-example`
  article is the docs-site entry.
