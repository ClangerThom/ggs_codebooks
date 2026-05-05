# GGS Analysis Kit — Plan

## Goal

Turn `ggs_codebooks` into a launchpad for new CC-assisted R/Quarto
analyses of GGS. Future analyses live as their own GitHub repos under
`~/github_projects/`; this repo provides the codebooks (built per
`PLAN.md`) plus the conventions, helpers, docs, and one Quarto extension
that those analyses lean on.

This plan is distinct from `PLAN.md`, which covers codebook
construction and is owned by a parallel CC agent.

---

## Conventions

These three rules govern everything below. The new `CLAUDE.md` will
state them as the project's contract with CC.

### 1. Two output channels per analysis chunk

- **Render channel → human.** Quarto produces HTML/PDF/decks for the
  user to open.
- **Data channel → CC.** Every chunk that produces a chart, table, or
  model also writes a tidy artefact to `output/data/*.tsv` via a
  `tee()` helper. CC reads those artefacts; CC does **not** read
  rendered HTML or screenshots except when visual correctness is the
  actual question.

### 2. Two read patterns for CC

- **Large source data (codebook CSVs, raw `.dta`)** → query via
  `Rscript -e '...'` and read the printed slice. Never `Read` the full
  file directly.
- **Analysis artefacts (tee'd TSVs, small docs)** → direct `Read`.
  They are small, durable, and self-contained.

### 3. Quarto + purl as the authoring/inspection split

- `.qmd` is the source of truth.
- A thin `render.R` wraps `quarto::quarto_render()` (and, where useful,
  `knitr::purl()`) so CC can drive renders and re-introspect chunks
  via `Rscript`.
- Conference decks use the MUNI FSS theme
  (`format: muni-fss-revealjs`, github.com/ClangerThom/muni_fss_quarto_theme).
  In-analysis inspection decks use the `ggs-inspect` extension shipped
  from this repo (serif, FT pink #FFF1E5).

The project `.Rprofile` (in each analysis repo) disables crayon/cli
ANSI colours and removes tibble print truncation so `Rscript` stdout
is CC-legible by default.

---

## Notes

**Canonical code.** The `tee()` helper and the project `.Rprofile`
options block live verbatim in `docs/starting_a_new_analysis.md` (#7).
Every new analysis copies them from there. Do not maintain alternative
versions elsewhere — drift defeats the purpose.

**Doc style.** Each `docs/*.md` page is short and opinionated. Point
at GGP documentation for canonical detail; do not reproduce it.

**GitHub username.** Use `ClangerThom` for repo URLs and `quarto add`
commands. The local git config `ClangerThomas` is a separate identity
and must not appear in URLs.

---

## First-cut deliverables

| # | Item | Status | Depends on |
|---|------|--------|------------|
| 1 | Rewritten `CLAUDE.md` | Now | — |
| 2 | `docs/missing_data.md` | Now | — |
| 3 | `docs/weights.md` | Now | — |
| 4 | `docs/longitudinal.md` | Now | — |
| 5 | `docs/r1_vs_r2.md` | Now | — |
| 6 | `docs/country_coverage.md` + builder | Now | codebooks rebuilt |
| 7 | `docs/starting_a_new_analysis.md` | Now | — |
| 8 | `docs/common_variables.md` (template) | Now | — |
| 9 | `_extensions/ggs-inspect/` | Now | — |
| 10 | `scripts/query_codebook.R` (API spec only) | Spec now, build post-rebuild | codebooks rebuilt |
| 11 | Phase B placeholder (questionnaire ingestion) | Note only | own future plan |

### 1. Rewritten `CLAUDE.md`

Purpose: tell CC how to use this repo.

Sections:
- Codebook access (via `Rscript`, never direct `Read` of the round CSVs).
- Codebook schema (one-table reference for the columns).
- Query recipes (`find_var`, `var_info`, `compare_coding` once #10 lands;
  inline `Rscript -e` snippets in the meantime).
- The three conventions above, restated as rules.
- R 4.6.0 pin (keep current text).
- Wave-prefix gotcha (R1 a*/b*/c*; keep current text).
- Pointers: `docs/`, `_extensions/ggs-inspect/`, the MUNI theme.

**Done when:**
- [ ] States the three conventions
- [ ] Codebook schema reference fits on one screen
- [ ] Includes at least one query recipe runnable as `Rscript -e`

### 2. `docs/missing_data.md`

GGS missingness has three layers:
- Stata extended missings (`.a`–`.z`) surfaced by `haven` as tagged NAs.
- Negative-coded missings (-1, -2, -3 etc.) used in places where the
  questionnaire uses "Don't know"/"Refusal"/"Not applicable".
- Structural skips (variable not asked given a routing condition).

Doc covers: how each surfaces in `haven`/`labelled`, when to convert
to `NA` vs preserve as a category, recipes (`zap_missing`, `user_na_to_na`,
custom helpers), and how this interacts with the codebook's `n_valid` /
`pct_miss` columns.

**Done when:**
- [ ] Distinguishes the three layers (`.a`–`.z`, negative codes, structural skips)
- [ ] Includes one cleaning recipe per layer

### 3. `docs/weights.md`

Short, opinionated. Design weights vs post-stratification vs
longitudinal/panel weights. Variable names per round. When to use which
for descriptives, regression, panel analysis. Pointers to GGP
documentation for the underlying formulas — we don't reproduce them.

**Done when:**
- [ ] Lists weight variable names per round
- [ ] States which weight to use for descriptives, regression, panel

### 4. `docs/longitudinal.md`

Respondent ID linkage across waves. Attrition. The R1 a*/b*/c* wave
prefix and how it interacts with `bind_rows`. Pivoting between long
and wide for panel work.

**Done when:**
- [ ] Documents respondent ID linkage across waves
- [ ] Documents the R1 `a*`/`b*`/`c*` prefix gotcha

### 5. `docs/r1_vs_r2.md`

Why naming differs. Sample-frame and instrument differences worth
knowing before treating R1 + R2 as a single longitudinal series. Where
they can and cannot be combined.

**Done when:**
- [ ] Lists key instrument differences
- [ ] States when R1 + R2 can and cannot be combined

### 6. `docs/country_coverage.md` (auto-generated) + builder

Builder: `scripts/build_coverage.R`. Reads both round CSVs, emits a
country × round × wave matrix as markdown table(s) and writes
`docs/country_coverage.md`.

Auto-regen note in the file header so readers know not to hand-edit.
Run after each codebook rebuild.

**Done when:**
- [ ] `scripts/build_coverage.R` exists and runs cleanly
- [ ] Output carries an auto-regen warning header
- [ ] Regenerates idempotently from the round CSVs

### 7. `docs/starting_a_new_analysis.md`

Replaces the abandoned `templates/new_analysis/` idea. A checklist
walking CC (or the user) through bootstrapping a fresh analysis repo
in `~/github_projects/`:

1. `gh repo create` (suggested name pattern).
2. Folder layout: `analysis.qmd`, `render.R`, `R/helpers.R`, `output/data/`.
3. Drop-in `.Rprofile` block (literal code).
4. Drop-in `tee()` helper (literal code).
5. Drop-in child `CLAUDE.md` template (with a pointer back to this
   repo's docs).
6. `quarto add ClangerThom/ggs_codebooks` to install the
   `ggs-inspect` extension.
7. `.gitignore` essentials.

CC reads this doc when scaffolding a new analysis; we don't ship a
copyable template directory.

**Done when:**
- [ ] Bootstrap checklist is ≤10 steps
- [ ] Pins canonical `tee()` and `.Rprofile` code verbatim
- [ ] Includes child `CLAUDE.md` template pointing back to this repo

### 8. `docs/common_variables.md` (template)

User-populated. Markdown table:

| Concept | R1 var | R2 var | Notes |
|---------|--------|--------|-------|
| Sex | … | … | … |
| Age | … | … | … |

A handful of rows pre-filled with placeholder syntax to show shape;
user fills in real mappings as they crop up in actual analyses.

**Done when:**
- [ ] Has the four-column table header
- [ ] Has 1–2 placeholder rows showing shape
- [ ] Notes that the user populates real entries

### 9. `_extensions/ggs-inspect/`

A Quarto extension shipped from this repo. Provides
`format: ggs-inspect-revealjs` — serif font, FT pink #FFF1E5
background, no MUNI branding.

Installed in any analysis repo via:

```
quarto add ClangerThom/ggs_codebooks
```

Quarto walks `_extensions/` and adds the format. Coexisting with the
codebooks and docs in one repo is supported.

The extension is intentionally tiny: format YAML + one CSS file. Not a
template — analysts write their own deck `.qmd` and reference the
format.

**Done when:**
- [ ] Provides a working `format: ggs-inspect-revealjs`
- [ ] Renders a test deck with serif font and `#FFF1E5` background
- [ ] `quarto add ClangerThom/ggs_codebooks` installs it cleanly into a fresh dir

### 10. `scripts/query_codebook.R` — API spec (deferred)

Source-able helpers for codebook queries. Designed to be invoked via
`Rscript -e 'source("…/query_codebook.R"); find_var("partner")'` or
sourced inside a chunk.

Planned signatures:

```r
find_var(pattern, round, country = NULL, in_label = TRUE, in_name = TRUE)
var_info(var, round)
compare_coding(var, round)        # do all countries code this the same?
country_vars(country, round, wave = NULL)
var_in_countries(var, round)      # coverage map
```

Each returns a tibble printed full-width. Implementation deferred until
the parallel agent's codebook rebuild lands and the schema is locked.

### 11. Phase B placeholder — questionnaire ingestion

Future workstream, not part of the first cut. The user has the GGS R1
and R2 questionnaires as PDFs (not machine-readable). Eventual goal:
PDF → structured markdown (one block per question with stem, response
options, routing, notes) → cross-linked to codebook variable names.

Will require its own scoping plan covering: which rounds and languages
to ingest, structuring schema, distillation strategy, refresh cadence.
**Do not start until separately scoped.**

---

## Deferred — Tier 4 CC tooling

After the first cut is in place and we see real friction:

- Project slash commands under a committed `.claude/commands/`:
  `/find-var`, `/harmonise`, `/inspect`, `/new-analysis`.
- Sub-agents under `.claude/agents/`: `ggs-variable-finder`
  (codebook-first, never opens raw `.dta`), `ggs-harmonisation-reviewer`.
- `.claude/settings.json` permission allowlist for routine `Rscript` /
  `Read` calls.

Committing `.claude/` requires editing `.gitignore` to un-ignore
`commands/` and `agents/` while keeping `settings.local.json` ignored.

---

## Open questions

- **Inspect extension naming.** `ggs-inspect-revealjs` vs shorter
  `ggs-inspect`? Decide at build time.
- **Coverage doc cadence.** Run `build_coverage.R` manually after each
  codebook rebuild, or wire it into `build_all.R`? Lean: wire it in,
  but only after #6 exists and is stable.
- **`docs/common_variables.md` shape.** Markdown table is the simplest
  thing; if the list grows past ~30 rows we may want a CSV the docs
  page renders from. Defer until the user populates a first version.

---

## Build order

1. CLAUDE.md (#1) — sets the contract.
2. `_extensions/ggs-inspect/` (#9) — small, standalone, unblocks deck use.
3. `docs/starting_a_new_analysis.md` (#7) — depends on #1 and #9 existing.
4. Domain docs (#2 #3 #4 #5) — independent, write in any order.
5. `docs/common_variables.md` template (#8) — handed to the user.
6. `docs/country_coverage.md` + builder (#6) — after the codebook rebuild lands.
7. `scripts/query_codebook.R` (#10) — same trigger as #6.
