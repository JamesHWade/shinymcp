# "shinymcp by example" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the flat `inst/examples/` directory into an ordered, concept-by-concept learning ladder, narrated by a pkgdown article and a slim examples index, filling the three missing rungs.

**Architecture:** Reuse the nine existing example apps in a defined order (do not rename their directories — the order lives in the article and index). Add three small new examples for the gaps: `hello-mcp-minimal` (the floor), `serve-to-client` (reach a real MCP client), `embed-in-shiny` (Shiny as host). Narrate with `vignettes/shinymcp-by-example.Rmd` and `inst/examples/README.md`.

**Tech Stack:** R, shinymcp, ellmer, bslib/htmltools, httpuv (preview/serve), pkgdown, testthat 3e.

**Source spec:** `design/shinymcp-by-example.md`

**Verified API used in this plan:**
- `mcp_app(ui, tools = list(), name = "shinymcp-app", version = "0.1.0", theme = NULL, ...)`
- `serve(app, type = c("stdio", "http"), port = 8080)` — bare `serve(app)` is stdio.
- `preview_app(app, port = NULL, launch = TRUE)` — `app` may be an `McpApp` **or a directory path** containing `app.R` (source()d to obtain the object).
- `mcp_host_ui(id)`; `mcp_host_server(id, app, trigger = c("debounce","change","submit","manual"), debounce_ms = 250, height = "auto", initial_arguments = NULL, debug = FALSE)`
- `as_shinychat_tool(app, value_fn = NULL, summary = NULL, ...)`
- Components: `mcp_text(id)`, `mcp_table(id)`, `mcp_plot(id, width, height)`, `mcp_select(id, label, choices, selected)`, `mcp_text_input(id, label, value, placeholder)`, `mcp_numeric_input(id, label, value, min, max, step)`
- Tool pattern in this repo (mirror exactly): `ellmer::tool(fun = function(...) {...}, name = "...", description = "...", arguments = list(x = ellmer::type_string("..."), ...))`. The `fun` returns a named list whose names match output ids.

**Run-command convention (use consistently in article + index):**
- mcp_app examples (end in `serve(app)`): preview locally with `shinymcp::preview_app(system.file("examples", "<dir>", package = "shinymcp"))`; serve to a client by pointing an MCP config at `Rscript <path-to-app.R>`.
- Real Shiny examples (`shinychat-card`, `embed-in-shiny`, `rpharma-hangout`): `shiny::runApp(system.file("examples", "<dir>", package = "shinymcp"))`.

---

## File Structure

**Create:**
- `inst/examples/hello-mcp-minimal/app.R` — rung 1, smallest MCP App.
- `inst/examples/serve-to-client/serve.R` — rung 8 server entry point.
- `inst/examples/serve-to-client/mcp.json` — example client config.
- `inst/examples/serve-to-client/README.md` — Claude Desktop, then VS Code, setup steps.
- `inst/examples/embed-in-shiny/app.R` — rung 10, host embed.
- `inst/examples/README.md` — the ordered index table.
- `vignettes/shinymcp-by-example.Rmd` — the narrated ladder article.
- `tests/testthat/test-examples.R` — smoke checks for the new examples.

**Modify:**
- `_pkgdown.yml` — add the article to the navbar `articles` menu.

---

## Task 1: Examples index (`inst/examples/README.md`)

**Files:**
- Create: `inst/examples/README.md`

- [ ] **Step 1: Write the index file**

```markdown
# shinymcp examples

An ordered tour. Each rung adds one idea on top of the last. The narrated version,
with code and explanation, is the [shinymcp by example](https://jameshwade.github.io/shinymcp/articles/shinymcp-by-example.html) article.

Preview an MCP App locally:

```r
shinymcp::preview_app(system.file("examples", "penguins", package = "shinymcp"))
```

| # | Example | What it adds |
|---|---------|--------------|
| 1 | [`hello-mcp-minimal`](hello-mcp-minimal) | One input, one tool, one output — the smallest MCP App |
| 2 | [`hello-mcp`](hello-mcp) | Rich outputs (a plot and text) and a bslib theme |
| 3 | [`penguins`](penguins) | Native bslib/shiny inputs, auto-detected by arg-name == element id |
| 4 | [`bslib-inputs`](bslib-inputs) | The auto-detection rules, plus `mcp_input()`/`mcp_output()` escape hatches |
| 5 | [`bind-mcp-demo`](bind-mcp-demo) | `bindMcp()`: expose only chosen parts of an existing app; some inputs stay private |
| 6 | [`multi-tool`](multi-tool) | Several tools and chained reactives in one app |
| 7 | [`module-tool`](module-tool) | `mcp_tool_module()`: reuse a Shiny module as a tool |
| 8 | [`converted-dashboard`](converted-dashboard) | Output of `convert_app()` — a plain Shiny app turned into an MCP App |
| 9 | [`serve-to-client`](serve-to-client) | Reach a real MCP client (Claude Desktop, then VS Code) over stdio |
| 10 | [`shinychat-card`](shinychat-card) | Surface a card as a shinychat tool result with `as_shinychat_tool()` |
| 11 | [`embed-in-shiny`](embed-in-shiny) | `mcp_host_server()`/`mcp_host_ui()`: Shiny as the review surface |
| 12 | [`data-explorer`](data-explorer) | Build inputs programmatically from a data frame |
| 13 | [`rpharma-hangout`](rpharma-hangout) | Capstone: multi-skill clinical app, contract inspector, `model_value` handoff |

For tuning the prompts behind these tools, see [`{dsprrr}`](https://jameshwade.github.io/dsprrr/);
for letting an agent call them, see [`{deputy}`](https://jameshwade.github.io/deputy/).
```

> Note: the spec listed 12 rungs; this index keeps the same concepts but lists `data-explorer`
> as its own row (it was previously folded into "exists" apps). If a tighter 12-row table is
> preferred, fold `data-explorer` into the `penguins`/`hello-mcp` narration. Confirm during review.

- [ ] **Step 2: Verify links resolve to real directories**

Run: `for d in hello-mcp-minimal hello-mcp penguins bslib-inputs bind-mcp-demo multi-tool module-tool converted-dashboard serve-to-client shinychat-card embed-in-shiny data-explorer rpharma-hangout; do test -d inst/examples/$d && echo "ok $d" || echo "MISSING $d"; done`
Expected: every row prints `ok` once Tasks 2–4 are done (before then, the three new dirs print `MISSING`).

- [ ] **Step 3: Commit**

```bash
git add inst/examples/README.md
git commit -m "docs: add ordered shinymcp examples index"
```

---

## Task 2: Rung 1 — `hello-mcp-minimal/app.R`

**Files:**
- Create: `inst/examples/hello-mcp-minimal/app.R`
- Test: `tests/testthat/test-examples.R` (added in Task 5)

- [ ] **Step 1: Write the example**

```r
# hello-mcp-minimal — the smallest possible MCP App.
#
# One input, one tool, one output. No theme, no plot. This is the shape every
# other example builds on: an `ui` of mcp_* components, a list of ellmer tools
# whose argument names match the input ids and whose return-list names match the
# output ids, then mcp_app() + serve().
library(shinymcp)

ui <- htmltools::tagList(
  mcp_text_input("name", "Your name", value = "world"),
  mcp_text("greeting")
)

tools <- list(
  ellmer::tool(
    fun = function(name = "world") {
      list(greeting = paste0("Hello, ", name, "!"))
    },
    name = "greet",
    description = "Greet a person by name",
    arguments = list(
      name = ellmer::type_string("The name to greet")
    )
  )
)

app <- mcp_app(ui, tools, name = "hello-mcp-minimal")
serve(app)
```

- [ ] **Step 2: Verify it loads and previews**

Run: `Rscript -e 'srv <- shinymcp::preview_app(system.file("examples","hello-mcp-minimal", package="shinymcp"), launch = FALSE); cat("URL:", srv$url, "\n"); srv$stop()'`
Expected: prints a `URL: http://127.0.0.1:<port>` line and exits cleanly (no error).
(If `system.file` returns "" because the package is loaded from source, point at `inst/examples/hello-mcp-minimal` directly during dev.)

- [ ] **Step 3: Commit**

```bash
git add inst/examples/hello-mcp-minimal/app.R
git commit -m "feat(examples): add hello-mcp-minimal, the smallest MCP App"
```

---

## Task 3: Rung 9 — `serve-to-client/`

**Files:**
- Create: `inst/examples/serve-to-client/serve.R`
- Create: `inst/examples/serve-to-client/mcp.json`
- Create: `inst/examples/serve-to-client/README.md`

- [ ] **Step 1: Write the server entry point**

```r
# serve-to-client/serve.R — an MCP server you can call from a real client.
#
# This is the same kind of mcp_app() as the other examples; the difference is how
# you run it. Instead of previewing it locally, you register this file as a stdio
# MCP server in your client's config (see README.md). The client then lists and
# calls the `greet` tool and renders its card.
library(shinymcp)

app <- mcp_app(
  ui = htmltools::tagList(
    mcp_text_input("name", "Your name", value = "world"),
    mcp_text("greeting")
  ),
  tools = list(
    ellmer::tool(
      fun = function(name = "world") {
        list(greeting = paste0("Hello, ", name, "!"))
      },
      name = "greet",
      description = "Greet a person by name",
      arguments = list(
        name = ellmer::type_string("The name to greet")
      )
    )
  ),
  name = "shinymcp-demo"
)

serve(app, type = "stdio")
```

- [ ] **Step 2: Write the example client config**

```json
{
  "mcpServers": {
    "shinymcp-demo": {
      "command": "Rscript",
      "args": ["/ABSOLUTE/PATH/TO/serve-to-client/serve.R"]
    }
  }
}
```

- [ ] **Step 3: Write the README (Claude Desktop first, then VS Code)**

````markdown
# serve-to-client

Every other example previews locally. This one shows the point of MCP: calling your
R tool from a real client. The server is `serve.R` — an ordinary `mcp_app()` ending in
`serve(app, type = "stdio")`. A client launches that script and talks to it over stdio.

Find the absolute path to `serve.R`:

```r
system.file("examples", "serve-to-client", "serve.R", package = "shinymcp")
```

You need `Rscript` on your `PATH` (check with `which Rscript`) and the `shinymcp` and
`ellmer` packages installed in the library that `Rscript` uses.

## Claude Desktop

1. Open **Settings → Developer → Edit Config** (or edit the file directly):
   - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - Windows: `%APPDATA%\Claude\claude_desktop_config.json`
2. Add the server (use the absolute path from above; on macOS an absolute `Rscript`
   path such as `/opt/homebrew/bin/Rscript` is more reliable than bare `Rscript`):

   ```json
   {
     "mcpServers": {
       "shinymcp-demo": {
         "command": "Rscript",
         "args": ["/ABSOLUTE/PATH/TO/serve-to-client/serve.R"]
       }
     }
   }
   ```

3. Quit and reopen Claude Desktop. The `greet` tool appears in the tools list; ask it to
   greet someone and the card renders inline.

## VS Code

1. Create `.vscode/mcp.json` in your workspace:

   ```json
   {
     "servers": {
       "shinymcp-demo": {
         "type": "stdio",
         "command": "Rscript",
         "args": ["/ABSOLUTE/PATH/TO/serve-to-client/serve.R"]
       }
     }
   }
   ```

2. Open the file and click **Start** on the server, or run **MCP: List Servers** from the
   Command Palette and start it there.
3. In Copilot Chat (Agent mode), the `greet` tool is now available.

## Troubleshooting

- Nothing appears: confirm `Rscript <path-to-serve.R>` runs without error in a terminal
  (it will wait on stdin — that is correct; press Ctrl-C to exit).
- "command not found": use the absolute path to `Rscript`.
- Tool errors: check the client's MCP logs for the server's stderr.
````

- [ ] **Step 4: Verify the server script loads (without blocking on stdio)**

Run: `Rscript -e 'env <- new.env(); env$serve <- function(app, ...) app; sys.source(system.file("examples","serve-to-client","serve.R", package="shinymcp"), envir = env); cat("app name:", env$app$name, "\n")'`
Expected: prints `app name: shinymcp-demo`. (Stubbing `serve` prevents the stdio loop from blocking the check.)

- [ ] **Step 5: Validate the JSON config parses**

Run: `Rscript -e 'jsonlite::fromJSON(system.file("examples","serve-to-client","mcp.json", package="shinymcp")); cat("json ok\n")'`
Expected: `json ok`.

- [ ] **Step 6: Commit**

```bash
git add inst/examples/serve-to-client
git commit -m "feat(examples): add serve-to-client (Claude Desktop, VS Code)"
```

---

## Task 4: Rung 11 — `embed-in-shiny/app.R`

**Files:**
- Create: `inst/examples/embed-in-shiny/app.R`

- [ ] **Step 1: Write the example**

```r
# embed-in-shiny — Shiny as the review surface for an MCP App.
#
# Define the MCP App once (the same object you would serve to a client), then host
# it inside a Shiny dashboard with mcp_host_ui()/mcp_host_server(). The card runs
# the real tool; the surrounding Shiny app is where a reviewer inspects it.
library(shiny)
library(bslib)
library(shinymcp)

greet_app <- mcp_app(
  ui = htmltools::tagList(
    mcp_text_input("name", "Your name", value = "world"),
    mcp_text("greeting")
  ),
  tools = list(
    ellmer::tool(
      fun = function(name = "world") {
        list(greeting = paste0("Hello, ", name, "!"))
      },
      name = "greet",
      description = "Greet a person by name",
      arguments = list(
        name = ellmer::type_string("The name to greet")
      )
    )
  ),
  name = "greet"
)

ui <- page_sidebar(
  title = "An MCP App embedded in Shiny",
  sidebar = sidebar(
    "The card on the right is the same MCP App you would serve to a client. ",
    "Here it runs inside Shiny, which is a convenient place to review it."
  ),
  card(
    card_header("Embedded MCP App"),
    mcp_host_ui("greet")
  )
)

server <- function(input, output, session) {
  mcp_host_server("greet", greet_app, trigger = "change")
}

shinyApp(ui, server)
```

- [ ] **Step 2: Verify it parses and builds a Shiny app object**

Run: `Rscript -e 'env <- new.env(); env$shinyApp <- function(ui, server, ...) structure(list(ui=ui, server=server), class="shiny.appobj"); sys.source(system.file("examples","embed-in-shiny","app.R", package="shinymcp"), envir = env); cat("ok\n")'`
Expected: `ok` with no error (confirms the file sources and `mcp_host_*` calls resolve).

- [ ] **Step 3: Commit**

```bash
git add inst/examples/embed-in-shiny/app.R
git commit -m "feat(examples): add embed-in-shiny host example"
```

---

## Task 5: Smoke tests for the new examples

**Files:**
- Create: `tests/testthat/test-examples.R`

- [ ] **Step 1: Write the tests**

```r
test_that("hello-mcp-minimal previews without error", {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("ellmer")
  dir <- system.file("examples", "hello-mcp-minimal", package = "shinymcp")
  skip_if(dir == "", "example not installed")
  srv <- preview_app(dir, launch = FALSE)
  on.exit(srv$stop(), add = TRUE)
  expect_match(srv$url, "^http://127\\.0\\.0\\.1:")
})

test_that("serve-to-client server script builds the expected app", {
  skip_if_not_installed("ellmer")
  path <- system.file("examples", "serve-to-client", "serve.R", package = "shinymcp")
  skip_if(path == "", "example not installed")
  env <- new.env()
  env$serve <- function(app, ...) app # stub so stdio loop never starts
  sys.source(path, envir = env)
  expect_s3_class(env$app, "McpApp")
  expect_identical(env$app$name, "shinymcp-demo")
})

test_that("embed-in-shiny sources into a shiny app object", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("ellmer")
  path <- system.file("examples", "embed-in-shiny", "app.R", package = "shinymcp")
  skip_if(path == "", "example not installed")
  env <- new.env()
  captured <- new.env()
  env$shinyApp <- function(ui, server, ...) {
    captured$built <- TRUE
    structure(list(), class = "shiny.appobj")
  }
  sys.source(path, envir = env)
  expect_true(isTRUE(captured$built))
})
```

> Implementation note: confirm `env$app` is the public class name (`McpApp`). If `preview_app(dir, ...)`
> needs the package installed (not just `load_all()`), run these under `devtools::test()` after
> `devtools::install()` or use `testthat::test_local()`; otherwise fall back to pointing at
> `testthat::test_path("../../inst/examples/...")`.

- [ ] **Step 2: Run the tests**

Run: `Rscript -e "devtools::test(filter = 'examples')"`
Expected: 3 passing tests (or skips if optional deps/installed paths are unavailable in the dev setup — resolve so they PASS, not skip, in CI).

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-examples.R
git commit -m "test(examples): smoke-test new example apps"
```

---

## Task 6: The article (`vignettes/shinymcp-by-example.Rmd`)

**Files:**
- Create: `vignettes/shinymcp-by-example.Rmd`

- [ ] **Step 1: Write the article header and intro**

```
---
title: "shinymcp by example"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{shinymcp by example}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

```{r, include = FALSE}
knitr::opts_chunk$set(collapse = TRUE, comment = "#>", eval = FALSE)
```

A tour of shinymcp, one idea at a time. Each example adds a single concept to the one
before it. The apps ship with the package; preview any of them locally:

```{r}
shinymcp::preview_app(system.file("examples", "penguins", package = "shinymcp"))
```
```

- [ ] **Step 2: Write one section per rung using this exact template**

For each rung, write a `## N. <dir> — <concept>` section containing: (a) one or two
sentences naming the concept, (b) the key snippet (not the whole app), (c) the run command,
(d) one honest sentence on when the pattern is the wrong choice. Content per rung:

1. **hello-mcp-minimal — the smallest MCP App.** Concept: a UI of `mcp_*` components + a list of
   `ellmer::tool()`s; argument names match input ids, return-list names match output ids. Snippet:
   the `greet` tool. Run: `preview_app(system.file("examples","hello-mcp-minimal", package="shinymcp"))`.
   When not: if you only need a function call with no UI, a plain MCP tool (no card) is simpler.
2. **hello-mcp — rich outputs and a theme.** Concept: `mcp_plot()`/`mcp_text()` outputs and a bslib
   theme. Snippet: the plot output + tool return with a base64 plot. When not: a single scalar
   result doesn't need a plot card.
3. **penguins — native inputs.** Concept: native `shiny`/`bslib` inputs are auto-detected when the
   element id equals the tool argument name; no `mcp_*` wrappers needed. Snippet: a `selectInput`
   whose id matches a tool arg. When not: when you want explicit control, the `mcp_*` inputs are clearer.
4. **bslib-inputs — the rules and escape hatches.** Concept: the id == arg-name rule, plus
   `mcp_input()`/`mcp_output()` for tags that don't follow it. Snippet: an `mcp_output()` on a custom tag.
   When not: if every input already matches by id, you don't need the escape hatches.
5. **bind-mcp-demo — selective exposure.** Concept: `bindMcp()` annotates an existing Shiny app so only
   chosen inputs/outputs are visible to the client; the rest stay private. Snippet: the `|> bindMcp()`
   annotations and the deliberately-unexposed input. When not: a brand-new app is cleaner built with
   `mcp_app()` directly.
6. **multi-tool — many tools, chained reactives.** Concept: independent connected components become
   separate tools; the analyzer traces transitive reactive chains. Snippet: the two tools. When not:
   one task = one tool; don't split a single operation.
7. **module-tool — reuse a Shiny module.** Concept: `mcp_tool_module()` wraps a standard module
   (ui+server) as a tool. Snippet: the module + `mcp_tool_module()` call. When not: a one-off app
   doesn't need module structure.
8. **converted-dashboard — automatic conversion.** Concept: `convert_app()` (parse → analyze → generate)
   turns a plain Shiny app into this. Snippet: the `convert_app()` invocation and a note that
   `original-app.R` is the input. Link to `vignette("automatic-conversion")`. When not: conversion
   infers shape, not clinical logic — review the generated tool bodies.
9. **serve-to-client — reach a real client.** Concept: `serve(app, type = "stdio")` + a client config
   makes the tool callable from Claude Desktop or VS Code. Snippet: the `.mcp.json` block. Point to
   `inst/examples/serve-to-client/README.md`. When not: for local iteration, `preview_app()` is faster.
10. **shinychat-card — a card in chat.** Concept: `as_shinychat_tool()` surfaces a card as a shinychat
    tool result. Snippet: `as_shinychat_tool(app)` + `register_tool`. Run: `runApp(...)`. When not: if
    you're not building a chat UI, you don't need this wrapper.
11. **embed-in-shiny — Shiny as host.** Concept: `mcp_host_ui()`/`mcp_host_server()` embed the same app
    into a dashboard as a review surface. Snippet: the host ui/server pair + `trigger`. When not: for a
    pure client deployment, you don't need a Shiny host.
12. **data-explorer — inputs from data.** Concept: build inputs programmatically from a data frame.
    Snippet: the column-selector generation. When not: a fixed, known schema is simpler hard-coded.
13. **rpharma-hangout — the capstone.** Concept: a realistic clinical app combining multi-skill cards,
    a contract inspector, and the aggregate `model_value` handoff, reachable from a client, Shiny, and
    shinychat. Run: `runApp(...)`. Link to `inst/examples/rpharma-hangout/README.md`.

- [ ] **Step 3: Write the "Going further" section**

```
## Going further

These examples keep the LLM out of the loop so they run offline. Two related packages build
on the same R functions:

- [`{dsprrr}`](https://jameshwade.github.io/dsprrr/) fits prompts to data with DSPy-style
  signatures, optimization, and tracing, so you improve a prompt with examples instead of by hand.
- [`{deputy}`](https://jameshwade.github.io/deputy/) is an agent runtime: it lets a tool-using
  agent call reviewed R functions, with permissions, hooks, and multi-agent coordination.
```

- [ ] **Step 4: Knit the article**

Run: `Rscript -e 'devtools::build_rmd("vignettes/shinymcp-by-example.Rmd")'`
Expected: builds with no error (chunks are `eval = FALSE`, so no app launches).

- [ ] **Step 5: Commit**

```bash
git add vignettes/shinymcp-by-example.Rmd
git commit -m "docs: add 'shinymcp by example' article"
```

---

## Task 7: Register the article in pkgdown

**Files:**
- Modify: `_pkgdown.yml` (the `navbar.components.articles.menu` list)

- [ ] **Step 1: Add the menu entry as the first article**

In `_pkgdown.yml`, under `navbar: components: articles: menu:`, add as the first item:

```yaml
        - text: shinymcp by example
          href: articles/shinymcp-by-example.html
```

- [ ] **Step 2: Build the site reference/articles to verify**

Run: `Rscript -e 'pkgdown::build_article("shinymcp-by-example")'`
Expected: writes `docs/articles/shinymcp-by-example.html` with no error.

- [ ] **Step 3: Commit**

```bash
git add _pkgdown.yml
git commit -m "docs: list 'shinymcp by example' in pkgdown navbar"
```

---

## Task 8: Final verification

- [ ] **Step 1: All example dirs exist and are referenced**

Run: `for d in hello-mcp-minimal hello-mcp penguins bslib-inputs bind-mcp-demo multi-tool module-tool converted-dashboard serve-to-client shinychat-card embed-in-shiny data-explorer rpharma-hangout; do test -d inst/examples/$d && echo "ok $d" || echo "MISSING $d"; done`
Expected: all `ok`.

- [ ] **Step 2: Tests pass**

Run: `Rscript -e "devtools::test(filter = 'examples')"`
Expected: all pass.

- [ ] **Step 3: Package check (documentation + examples)**

Run: `Rscript -e "devtools::check_man(); devtools::test()"`
Expected: no errors; existing tests still pass.

- [ ] **Step 4: air format**

Run: `air format R/ tests/testthat/ inst/examples/`
Expected: clean (or applies formatting; commit any changes).

- [ ] **Step 5: Final commit if formatting changed**

```bash
git add -A
git commit -m "style: air format example ladder"
```

---

## Notes for the implementer

- **Do not rename existing example directories.** Order lives in the index and article only.
- **Mirror the existing tool pattern exactly** (`ellmer::tool(fun=, name=, description=, arguments=)`)
  — it is what the other examples use and is known to work with this repo's ellmer version.
- **Beads:** create a beads issue/epic for this work before implementing (project convention). At
  the time of writing the beads dolt store reported an error (`.beads/dolt/.../repo_state.json`
  missing); run `bd doctor` / `bd init` if needed before relying on it.
- **dsprrr/deputy stay link-only** — no example apps for them in this repo.
