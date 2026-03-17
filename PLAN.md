# GGS Codebooks — Project Plan

## Goal

Produce machine-readable codebooks for all GGS rounds and waves so that
Claude Code (CC) can query variable metadata cheaply via R, instead of
relying on proprietary browser-only tooling.

Primary use cases:
1. **Cross-country harmonisation** — find and compare how variables are
   coded across countries for comparative studies
2. **Single-country variable lookup** — inspect what variables and codings
   are available for a specific country-round

---

## Folder structure

```
ggs_codebooks/
├── scripts/
│   ├── build_codebook.R        # generalised single-country-round builder
│   └── build_all.R             # loops over all available .dta files, writes
│                               # per-round files and updates index
├── data/
│   ├── raw/                    # gitignored — proprietary .dta source files
│   └── codebooks/
│       ├── index.csv           # master catalogue (one row per country-round)
│       ├── GGS_R1.csv          # all Round 1 countries, all waves
│       └── GGS_R2.csv          # all Round 2 countries, all waves
├── example_czech_round_2_w1w2_codebook.R   # original reference script
├── .gitignore
└── PLAN.md
```

---

## Codebook schema (one row per variable × wave × country)

| column        | description                                            |
|---------------|--------------------------------------------------------|
| country       | ISO 3166-1 alpha-3 (e.g. `CZE`)                        |
| round         | GGS round (`1` or `2`)                                 |
| wave          | Wave number within that round                          |
| var_name      | Variable name as in the .dta file                      |
| var_label     | Full variable label                                    |
| type          | `categorical` or `numeric`                             |
| n_valid       | Count of non-missing observations                      |
| pct_miss      | % missing                                              |
| range_or_cats | Numeric range OR `code=Label; …` for categoricals      |
| in_all_waves  | TRUE if var appears in every wave of this country-round|

---

## CSV structure decision

### Options considered

| Option | Structure | Harmonisation query | Single-country query |
|--------|-----------|--------------------|-----------------------|
| A | One monolithic CSV (all rounds) | trivial | trivial |
| B | Per-country-round (e.g. `CZE_R2.csv`) | load N files, rbind | load 1 file |
| C | **Per-round (e.g. `GGS_R2.csv`)** ✓ | **load 1 file, filter** | **load 1 file, filter** |

### Decision: Option C — one CSV per GGS round

**Why not one monolithic CSV (A):** Both rounds combined could exceed
100 k rows as R2 grows. More importantly, R1 and R2 are distinct instruments
with different variable sets; keeping them separate avoids confusion and lets
CC load only the relevant round.

**Why not per-country-round (B):** Harmonisation — a primary use case — would
require loading and rbinding ~10–20 files, adding friction for both the build
process and CC queries.

**Why per-round (C):**
- A single `read.csv("data/codebooks/GGS_R2.csv")` gives CC all countries
  for a round — ideal for harmonisation
- Single-country work is `filter(country == "CZE")` — no extra file I/O
- R1 ≈ 20 countries × 2 waves × ~500 vars ≈ 20 k rows; R2 similar — both
  are fast to load and produce compact printed output for CC
- New countries are added by appending rows, not creating new files
- Only two files to maintain long-term

The `index.csv` provides a cheap overview (countries, waves, var counts)
without loading the full codebooks.

---

## Countries and rounds

### GGS Round 1 (~2003–2011)
Austria · Belgium · Bulgaria · Czech Republic · Estonia · France ·
Georgia · Germany · Hungary · Italy · Lithuania · Netherlands · Norway ·
Poland · Romania · Russia · Sweden · (+ Australia and Japan outside Europe)

Waves: typically W1 + W2; a few countries have W3.

### GGS Round 2 / GGS-II (~2019–ongoing)
Austria · Bulgaria · Czech Republic · Denmark · Estonia · France ·
Georgia · Germany · Hungary · Italy · Netherlands · Norway · Poland ·
(further countries being added)

Waves: W1 released; W2 released for early-adopter countries.

---

## Build workflow

1. Place raw `.dta` files under `data/raw/` (never committed). Suggested
   naming: `{ISO3}_R{round}_W{wave}.dta` e.g. `CZE_R2_W1.dta`
2. Run `scripts/build_codebook.R` for a single country-round — appends
   to the relevant `GGS_R{round}.csv` and updates `index.csv`.
3. Or run `scripts/build_all.R` which auto-discovers all `.dta` files
   in `data/raw/` by naming convention and rebuilds both round files
   and the index from scratch.

---

## How CC will use the codebooks

```r
# ── Harmonisation: compare a variable across all R2 countries ────────────────
cb_r2 <- read.csv("data/codebooks/GGS_R2.csv")

cb_r2 |>
  dplyr::filter(var_name == "dv_coh") |>
  dplyr::select(country, wave, var_label, range_or_cats)

# ── Single-country lookup ────────────────────────────────────────────────────
cb_r2 |>
  dplyr::filter(country == "CZE", wave == 1) |>
  dplyr::filter(grepl("partner", var_label, ignore.case = TRUE))

# ── Cheap discovery without loading full codebooks ───────────────────────────
index <- read.csv("data/codebooks/index.csv")
```

CC reads the printed R output (a compact tibble) rather than the raw CSV,
keeping token cost low regardless of codebook size.

---

## Next steps

- [ ] Generalise `example_czech_round_2_w1w2_codebook.R` into
      `scripts/build_codebook.R` (add `country` / `round` args, append to
      `GGS_R{round}.csv`, update `index.csv`)
- [ ] Build CZE R2 as first real entry in `GGS_R2.csv`
- [ ] Work through remaining available country-rounds as data access allows
- [ ] Add `scripts/build_all.R` runner
- [ ] Add a small `scripts/query_codebook.R` helper for CC to use
