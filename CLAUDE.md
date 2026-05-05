# CLAUDE.md

## Codebook access
Always read CSVs from `data/codebooks/` through R, not directly. Use
`scripts/scratch.R` for inspection and ad-hoc queries.

## Codebook schema (24 columns)
`country`, `country_name`, `round`, `wave`, `var_name`, `var_label`,
`module`, `type`, `n_total`, `n_valid`, `pct_miss`, `value_min`,
`value_max`, `cat_levels`, `mean`, `median`, `sd`, `q1`, `q3`,
`n_unique`, `n_tagged_na`, `tagged_na_summary`, `in_all_waves`,
`source_file`. See `PLAN.md` for full description.

`type` is `numeric` | `categorical` | `string`.
- `value_min`/`value_max`/`mean`/`median`/`sd`/`q1`/`q3` populated only
  for numerics
- `cat_levels` populated only for categoricals (packed `"code=Label; …"`)
- `n_unique` populated for numerics and strings
- `tagged_na_summary` formats as `.a=Don't know (12); .b=Refusal (3)`;
  `n_tagged_na` is the total count for cheap filtering
- `module` is looked up from `data/codebooks/module_prefixes.csv` —
  extend that CSV when new prefixes are confirmed

## Running R on this machine
`Rscript` resolves to **R 4.6.0** (`C:\Program Files\R\R-4.6.0\bin`,
on the user PATH). The machine also has R 4.5.1 installed — do **not**
invoke it: the project's packages (`readr`, `dplyr`, `haven`, `labelled`,
`purrr`, `tibble`, `tidyr`) are built for 4.6.0 and loading them under
4.5.1 fails with a DLL-version error.

## Schema gotcha
`GGS_R1.csv` stores `wave` as numeric (`1`, `2`, `3`); `GGS_R2.csv`
stores it as character (`"1"`, `"2"`, `"1_register"`). Coerce to
character before `bind_rows()` if combining rounds.
