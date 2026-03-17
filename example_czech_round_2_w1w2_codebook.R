# =============================================================================
# 00_codebook.R
# Purpose : Build a general-purpose codebook for GGS Wave 1 & Wave 2 (Czech).
#           Outputs one row per variable × wave.
# Outputs : output/codebook.rds  — primary, queried programmatically
#           output/codebook.csv  — secondary, human-readable reference
# =============================================================================

# -----------------------------------------------------------------------------
# Step 1 — Load packages
# -----------------------------------------------------------------------------
library(haven)      # read_dta(), Stata labels
library(labelled)   # var_label(), val_labels()
library(dplyr)      # data wrangling
library(purrr)      # map helpers

# -----------------------------------------------------------------------------
# Step 2 — Read both waves
# -----------------------------------------------------------------------------
message("Reading Wave 1 ...")
w1 <- haven::read_dta("data/raw/GGSII_Wave1_CZ_V_2_1.dta")

message("Reading Wave 2 ...")
w2 <- haven::read_dta("data/raw/GGSII_Wave2_CZ_V_1_0.dta")

message(sprintf("Wave 1: %d rows × %d columns", nrow(w1), ncol(w1)))
message(sprintf("Wave 2: %d rows × %d columns", nrow(w2), ncol(w2)))

# -----------------------------------------------------------------------------
# Step 3 — Extraction function
# -----------------------------------------------------------------------------
extract_var_info <- function(df, wave_num) {
  n_rows <- nrow(df)

  purrr::imap_dfr(df, function(col, col_name) {
    # Variable label
    vlab <- labelled::var_label(col)
    if (is.null(vlab) || identical(vlab, "")) {
      vlab <- attr(col, "label")
    }
    vlab <- if (is.null(vlab)) NA_character_ else as.character(vlab)

    # Type: categorical only if there are value labels for *non-missing* codes.
    # Stata stores extended missing values (.a, .b, … .z) as tagged NAs with
    # labels (e.g. "Refusal", "Not applicable"). Filtering those out prevents
    # genuinely continuous variables from being misclassified as categorical.
    vlabs <- labelled::val_labels(col)
    valid_vlabs <- NULL
    if (!is.null(vlabs) && length(vlabs) > 0) {
      keep        <- !haven::is_tagged_na(vlabs) & !is.na(vlabs)
      valid_vlabs <- vlabs[keep]
    }
    is_cat <- length(valid_vlabs) > 0

    type <- if (is_cat) "categorical" else "numeric"

    # Missingness
    n_miss  <- sum(is.na(col))
    n_valid <- n_rows - n_miss
    pct_miss <- round(n_miss / n_rows * 100, 1)

    # range_or_cats
    if (is_cat) {
      # Build "code=Label; ..." using only valid (non-tagged-NA) value labels
      codes  <- as.numeric(valid_vlabs)
      labels <- names(valid_vlabs)
      ord    <- order(codes)
      pairs  <- paste0(codes[ord], "=", labels[ord])
      raw_str <- paste(pairs, collapse = "; ")
      range_or_cats <- if (nchar(raw_str) > 200) {
        paste0(substr(raw_str, 1, 197), "...")
      } else {
        raw_str
      }
    } else {
      # Numeric range — strip haven/labelled class before computing min/max
      num_col <- suppressWarnings(as.numeric(col))
      mn <- suppressWarnings(min(num_col, na.rm = TRUE))
      mx <- suppressWarnings(max(num_col, na.rm = TRUE))
      if (is.infinite(mn) || is.infinite(mx)) {
        range_or_cats <- NA_character_
      } else {
        range_or_cats <- paste0(mn, "-", mx)
      }
    }

    tibble::tibble(
      wave          = wave_num,
      var_name      = col_name,
      var_label     = vlab,
      type          = type,
      n_valid       = n_valid,
      pct_miss      = pct_miss,
      range_or_cats = range_or_cats
    )
  })
}

# -----------------------------------------------------------------------------
# Step 4 — Build combined codebook
# -----------------------------------------------------------------------------
message("Extracting Wave 1 variable info ...")
cb1 <- extract_var_info(w1, 1L)

message("Extracting Wave 2 variable info ...")
cb2 <- extract_var_info(w2, 2L)

codebook_df <- dplyr::bind_rows(cb1, cb2)

# Add in_both flag
both_vars <- intersect(names(w1), names(w2))
codebook_df <- codebook_df |>
  dplyr::mutate(in_both = var_name %in% both_vars)

# -----------------------------------------------------------------------------
# Step 5 — Save outputs
# -----------------------------------------------------------------------------
if (!dir.exists("data/codebook")) dir.create("data/codebook", recursive = TRUE)

saveRDS(codebook_df, "data/codebook/codebook.rds")
message("Saved: data/codebook/codebook.rds")

readr::write_excel_csv(codebook_df, "data/codebook/codebook.csv")  # UTF-8 BOM for Windows/Excel
message("Saved: data/codebook/codebook.csv")

# -----------------------------------------------------------------------------
# Step 6 — Console summary
# -----------------------------------------------------------------------------
cat("\n========== CODEBOOK SUMMARY ==========\n")

cat(sprintf("\nVariables per wave:\n"))
codebook_df |>
  dplyr::count(wave) |>
  dplyr::rename(n_variables = n) |>
  print()

cat(sprintf("\nVariables appearing in BOTH waves: %d\n", length(both_vars)))

cat("\nType breakdown per wave:\n")
codebook_df |>
  dplyr::count(wave, type) |>
  tidyr::pivot_wider(names_from = type, values_from = n, values_fill = 0L) |>
  print()

cat("\n======================================\n")

