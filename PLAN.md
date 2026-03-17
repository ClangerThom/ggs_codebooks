# GGS Codebooks — Project Plan

## Goal

Produce machine-readable codebooks for all GGS rounds and waves so that
Claude Code (CC) can query variable metadata cheaply via R, instead of
relying on proprietary browser-only tooling.

---

## Folder structure

```
ggs_codebooks/
├── scripts/
│   ├── build_codebook.R        # generalised single-country-round builder
│   └── build_all.R             # loops over all available .dta files
├── data/
│   ├── raw/                    # gitignored — proprietary .dta source files
│   └── codebooks/
│       ├── index.csv           # master catalogue (one row per country-round-wave)
│       ├── CZE_R2.csv
│       ├── CZE_R1.csv
│       ├── FRA_R1.csv
│       └── ...
├── example_czech_round_2_w1w2_codebook.R   # original reference script
├── .gitignore
└── PLAN.md
```

---

## Codebook schema (one row per variable × wave)

| column        | description                                           |
|---------------|-------------------------------------------------------|
| country       | ISO 3166-1 alpha-3 (e.g. `CZE`)                       |
| round         | GGS round (`1` or `2`)                                |
| wave          | Wave number within that round                         |
| var_name      | Variable name as in the .dta file                     |
| var_label     | Full variable label                                   |
| type          | `categorical` or `numeric`                            |
| n_valid       | Count of non-missing observations                     |
| pct_miss      | % missing                                             |
| range_or_cats | Numeric range OR `code=Label; …` for categoricals     |
| in_both       | TRUE if var appears in all waves of this country-round|

---

## One big CSV vs per-country-round CSVs

### Option A — one monolithic CSV

**Pros:** single file, trivial cross-country lookups with `dplyr::filter()`
**Cons:** potentially 100 k+ rows; CC must load everything even for a
single-country task; hard to add one new country without rewriting the file;
slow `read.csv()` cold start in R

### Option B — one CSV per country-round  ✓ recommended

**Pros:**
- CC loads only what it needs → minimal tokens and R memory
- Each file is ~300–1 500 rows (one GGS country-round has ~300–800 variables
  per wave, times 2–3 waves)
- New country-rounds can be added without touching existing files
- Matches the natural unit of analysis (one country-round at a time)

**Cons:** cross-country comparisons require loading multiple files —
mitigated by the `index.csv` catalogue and a small helper function

### Decision: Option B + a lightweight index

`index.csv` stores one row per country-round with columns:
`country, iso3, round, waves, n_vars, file` — so CC can discover what
exists cheaply before deciding which full codebook to load.

---

## Countries and rounds

### GGS Round 1 (~2003–2011)
Austria · Belgium · Bulgaria · Czech Republic · Estonia · France ·
Georgia · Germany · Hungary · Italy · Lithuania · Netherlands · Norway ·
Poland · Romania · Russia · Sweden · (+ Australia and Japan as outside-Europe)

Waves: typically W1 + W2; a few countries have W3.

### GGS Round 2 / GGS-II (~2019–ongoing)
Austria · Bulgaria · Czech Republic · Denmark · Estonia · France ·
Georgia · Germany · Hungary · Italy · Netherlands · Norway · Poland ·
(further countries being added)

Waves: W1 released; W2 released for early-adopter countries.

File naming convention: `{ISO3}_R{round}.csv`  e.g. `CZE_R2.csv`

---

## Build workflow

1. Place raw `.dta` files under `data/raw/` (never committed).
2. Run `scripts/build_codebook.R` for a single country-round — pass
   `country`, `round`, and a named list of wave paths as arguments.
3. Or run `scripts/build_all.R` which auto-discovers all `.dta` files
   in `data/raw/` by naming convention and rebuilds every codebook plus
   the index.

---

## How CC will use the codebooks

```r
# Step 1 — discover what is available (tiny, always cheap)
index <- read.csv("data/codebooks/index.csv")

# Step 2 — load only the relevant country-round
cb <- read.csv("data/codebooks/CZE_R2.csv")

# Step 3 — answer a question
cb |> dplyr::filter(var_name == "a_sex")
```

CC reads the R output (a small printed tibble) rather than the raw CSV,
keeping token cost low regardless of codebook size.

---

## Next steps

- [ ] Generalise `example_czech_round_2_w1w2_codebook.R` into
      `scripts/build_codebook.R` (add `country` / `round` args, write to
      `data/codebooks/{ISO3}_R{round}.csv`, update `index.csv`)
- [ ] Build CZE R2 codebook as first real output
- [ ] Work through remaining available country-rounds as data access allows
- [ ] Add a small `scripts/query_codebook.R` helper for CC to use
