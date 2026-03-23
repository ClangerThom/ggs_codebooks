# scratch.R — temporary working script
library(haven)
library(dplyr)
library(readr)

# ── Investigate duplicates ────────────────────────────────────────────────────
cat("=== Investigating duplicate var_names in source .dta files ===\n\n")

# R1 W1: _merge
w1 <- haven::read_dta("data/raw/R1_W1.dta")
merge_cols <- names(w1)[grepl("^_merge", names(w1))]
cat("R1 W1 columns matching '^_merge':\n")
print(merge_cols)

# R1 W2: b231_
w2 <- haven::read_dta("data/raw/R1_W2.dta")
b231_cols <- names(w2)[grepl("^b231_", names(w2))]
cat("\nR1 W2 columns matching '^b231_':\n")
print(b231_cols)
cat("var_labels for b231_ cols:\n")
for (nm in b231_cols) cat(sprintf("  %-20s %s\n", nm, labelled::var_label(w2[[nm]])))

# R2: KAZ surveyversion, SWE region
kaz <- haven::read_dta("data/raw/KAZ_R2_W1.dta")
sv_cols <- names(kaz)[grepl("surveyversion", names(kaz), ignore.case = TRUE)]
cat("\nR2 KAZ columns matching 'surveyversion':\n"); print(sv_cols)

swe <- haven::read_dta("data/raw/SWE_R2_W1.dta")
reg_cols <- names(swe)[grepl("^region", names(swe), ignore.case = TRUE)]
cat("\nR2 SWE columns matching '^region':\n"); print(reg_cols)

rm(w1, w2, kaz, swe)

# ── Inspect codebooks ─────────────────────────────────────────────────────────
inspect_codebook <- function(path) {
  cb <- readr::read_csv(path, show_col_types = FALSE)
  cat(sprintf("\n\n══════════════════════════════════════════\n"))
  cat(sprintf("FILE: %s\n", basename(path)))
  cat(sprintf("  %d rows | %d cols\n", nrow(cb), ncol(cb)))
  cat(sprintf("══════════════════════════════════════════\n"))

  # 1. Schema
  cat("\n── Column types ──\n")
  print(sapply(cb, class))

  # 2. Countries / rounds / waves
  cat("\n── Countries x waves ──\n")
  print(cb |> dplyr::count(country, round, wave) |> tidyr::pivot_wider(names_from = wave, values_from = n))

  # 3. Duplicates
  dups <- cb |> dplyr::count(country, round, wave, var_name) |> dplyr::filter(n > 1)
  cat(sprintf("\n── Duplicate country/round/wave/var_name rows: %d ──\n", nrow(dups)))
  if (nrow(dups) > 0) print(dups)

  # 4. type values
  cat("\n── type breakdown ──\n")
  print(cb |> dplyr::count(type))

  # 5. Missing var_label
  n_no_label <- sum(is.na(cb$var_label))
  cat(sprintf("\n── Variables with no label: %d (%.1f%%)\n",
              n_no_label, 100 * n_no_label / nrow(cb)))

  # 6. pct_miss out of range
  bad_pct <- cb |> dplyr::filter(pct_miss < 0 | pct_miss > 100)
  cat(sprintf("\n── pct_miss out of [0,100]: %d rows ──\n", nrow(bad_pct)))
  if (nrow(bad_pct) > 0) print(bad_pct)

  # 7. n_valid negative
  bad_n <- cb |> dplyr::filter(n_valid < 0)
  cat(sprintf("\n── n_valid < 0: %d rows ──\n", nrow(bad_n)))

  # 8. 100% missing variables
  all_miss <- cb |> dplyr::filter(pct_miss == 100)
  cat(sprintf("\n── 100%% missing variables: %d ──\n", nrow(all_miss)))
  if (nrow(all_miss) > 0) print(all_miss |> dplyr::count(country, round, wave))

  # 9. range_or_cats: numeric vars that have a value (should be a range or NA)
  cat("\n── Numeric range_or_cats sample (first 5) ──\n")
  print(cb |> dplyr::filter(type == "numeric", !is.na(range_or_cats)) |> head(5) |>
          dplyr::select(country, wave, var_name, range_or_cats))

  # 10. range_or_cats: categorical vars with NA (all cats were tagged-NA only?)
  cat_no_cats <- cb |> dplyr::filter(type == "categorical", is.na(range_or_cats))
  cat(sprintf("\n── Categorical vars with NA range_or_cats: %d ──\n", nrow(cat_no_cats)))
  if (nrow(cat_no_cats) > 0) print(head(cat_no_cats, 10) |> dplyr::select(country, wave, var_name, var_label))

  # 11. in_all_waves: single-wave countries should all be TRUE
  single_wave_countries <- cb |>
    dplyr::distinct(country, wave) |>
    dplyr::count(country) |>
    dplyr::filter(n == 1) |>
    dplyr::pull(country)
  if (length(single_wave_countries) > 0) {
    bad_inall <- cb |>
      dplyr::filter(country %in% single_wave_countries, !in_all_waves)
    cat(sprintf("\n── Single-wave countries with in_all_waves=FALSE: %d rows ──\n", nrow(bad_inall)))
  }

  # 12. in_all_waves rate for multi-wave countries
  cat("\n── in_all_waves rate by country (multi-wave only) ──\n")
  multi_wave <- cb |>
    dplyr::distinct(country, wave) |>
    dplyr::count(country) |>
    dplyr::filter(n > 1) |>
    dplyr::pull(country)
  if (length(multi_wave) > 0) {
    print(cb |> dplyr::filter(country %in% multi_wave, wave == min(wave)) |>
      dplyr::group_by(country) |>
      dplyr::summarise(pct_in_all_waves = round(mean(in_all_waves) * 100, 1), .groups = "drop"))
  }

  # 13. Truncated range_or_cats strings
  truncated <- sum(grepl("\\.\\.\\.$", cb$range_or_cats), na.rm = TRUE)
  cat(sprintf("\n── Truncated range_or_cats (>200 bytes): %d ──\n", truncated))
  if (truncated > 0) {
    print(cb |> dplyr::filter(grepl("\\.\\.\\.$", range_or_cats)) |>
            head(3) |> dplyr::select(country, wave, var_name, range_or_cats))
  }

  invisible(cb)
}

r1 <- inspect_codebook("data/codebooks/GGS_R1.csv")
r2 <- inspect_codebook("data/codebooks/GGS_R2.csv")
