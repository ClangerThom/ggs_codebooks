# =============================================================================
# build_r1.R
# Purpose : Build GGS_R1.csv from consolidated multi-country wave files.
#           R1 uses one file per wave (all countries combined), unlike R2.
#
# Strategy: Two passes per wave —
#   1. Metadata pass (full dataset): var_label, type, categorical range_or_cats
#   2. Per-country pass: n_valid, pct_miss, numeric ranges
#   This avoids repeating 2500+ label extractions for each of ~16 countries.
#
# Run from repo root:
#   Rscript scripts/build_r1.R
# =============================================================================

source("scripts/build_codebook.R")   # loads haven, labelled, dplyr, purrr
library(readr)
library(tibble)

RAW_DIR <- "data/raw"
OUT_DIR <- "data/codebooks"

# GGS R1 country name → ISO3 (names match value labels in the .dta files)
ISO3_MAP <- c(
  "Bulgaria"      = "BGR",
  "Russia"        = "RUS",
  "Georgia"       = "GEO",
  "Germany"       = "DEU",
  "France"        = "FRA",
  "Hungary"       = "HUN",
  "Italy"         = "ITA",
  "Netherlands"   = "NLD",
  "Romania"       = "ROU",
  "Norway"        = "NOR",
  "Austria"       = "AUT",
  "Estonia"       = "EST",
  "Belgium"       = "BEL",
  "Australia"     = "AUS",
  "Lithuania"     = "LTU",
  "Poland"        = "POL",
  "CzechRepublic" = "CZE",
  "Sweden"        = "SWE"
)

# Country variable prefix follows the wave letter (a/b/c) used throughout R1
WAVE_INFO <- list(
  list(wave = "1", path = file.path(RAW_DIR, "R1_W1.dta"), cvar = "acountry"),
  list(wave = "2", path = file.path(RAW_DIR, "R1_W2.dta"), cvar = "bcountry"),
  list(wave = "3", path = file.path(RAW_DIR, "R1_W3.dta"), cvar = "ccountry")
)

# =============================================================================
all_parts <- list()

for (wi in WAVE_INFO) {
  wave <- wi$wave
  path <- wi$path
  cvar <- wi$cvar

  message(sprintf("\n=== Wave %s: reading %s ===", wave, basename(path)))
  df <- haven::read_dta(path)
  message(sprintf("  %d rows x %d cols", nrow(df), ncol(df)))

  # Countries present in this wave (with at least 1 row, skip tagged-NA labels)
  country_labels   <- labelled::val_labels(df[[cvar]])
  country_code_vec <- as.numeric(df[[cvar]])
  valid_country_names <- names(country_labels)[
    !is.na(as.numeric(country_labels)) &
    sapply(as.numeric(country_labels), function(code) {
      sum(country_code_vec == code, na.rm = TRUE) > 0
    })
  ]
  message(sprintf("  Countries with data: %s",
                  paste(valid_country_names, collapse = ", ")))

  var_names <- setdiff(names(df), cvar)

  # ---------------------------------------------------------------------------
  # Pass 1 — metadata from full dataset (labels, type, categorical categories)
  # ---------------------------------------------------------------------------
  message("  Extracting variable metadata ...")
  meta <- purrr::imap_dfr(df[, var_names], function(col, col_name) {
    vlab <- labelled::var_label(col)
    if (is.null(vlab) || identical(vlab, "")) vlab <- attr(col, "label")
    vlab <- if (is.null(vlab)) NA_character_ else
      iconv(as.character(vlab), to = "UTF-8", sub = "?")

    vlabs       <- labelled::val_labels(col)
    valid_vlabs <- NULL
    if (!is.null(vlabs) && length(vlabs) > 0) {
      keep        <- !haven::is_tagged_na(vlabs) & !is.na(vlabs)
      valid_vlabs <- vlabs[keep]
    }
    is_cat <- length(valid_vlabs) > 0
    type   <- if (is_cat) "categorical" else "numeric"

    range_or_cats <- if (is_cat) {
      codes   <- as.numeric(valid_vlabs)
      labels  <- iconv(names(valid_vlabs), to = "UTF-8", sub = "?")
      ord     <- order(codes)
      pairs   <- paste0(codes[ord], "=", labels[ord])
      raw_str <- paste(pairs, collapse = "; ")
      if (nchar(raw_str, type = "bytes") > 200)
        paste0(substr(raw_str, 1, 197), "...") else raw_str
    } else {
      NA_character_   # numeric range filled per country below
    }

    tibble::tibble(var_name = col_name, var_label = vlab,
                   type = type, range_or_cats = range_or_cats)
  })
  numeric_vars <- meta$var_name[meta$type == "numeric"]

  # ---------------------------------------------------------------------------
  # Pass 2 — per-country: missingness + numeric ranges
  # ---------------------------------------------------------------------------
  for (cn in valid_country_names) {
    iso3 <- ISO3_MAP[[cn]]
    if (is.null(iso3) || is.na(iso3)) {
      warning(sprintf("No ISO3 mapping for '%s' — skipping", cn))
      next
    }

    code   <- as.numeric(country_labels[[cn]])
    sub_df <- df[country_code_vec == code, var_names, drop = FALSE]
    n_rows <- nrow(sub_df)
    message(sprintf("    %s (%s): %d rows", cn, iso3, n_rows))

    miss_df <- purrr::imap_dfr(sub_df, function(col, col_name) {
      n_miss <- sum(is.na(col))
      tibble::tibble(
        var_name = col_name,
        n_valid  = n_rows - n_miss,
        pct_miss = round(n_miss / n_rows * 100, 1)
      )
    })

    num_sub <- sub_df[, intersect(numeric_vars, names(sub_df)), drop = FALSE]
    num_ranges <- purrr::imap_dfr(num_sub, function(col, col_name) {
      num_col <- suppressWarnings(as.numeric(col))
      mn  <- suppressWarnings(min(num_col, na.rm = TRUE))
      mx  <- suppressWarnings(max(num_col, na.rm = TRUE))
      rng <- if (is.infinite(mn) || is.infinite(mx)) NA_character_ else paste0(mn, "-", mx)
      tibble::tibble(var_name = col_name, num_range = rng)
    })

    cb <- meta |>
      dplyr::left_join(miss_df,    by = "var_name") |>
      dplyr::left_join(num_ranges, by = "var_name") |>
      dplyr::mutate(
        range_or_cats = dplyr::if_else(type == "numeric", num_range, range_or_cats),
        country       = iso3,
        round         = 1L,
        wave          = wave
      ) |>
      dplyr::select(country, round, wave, var_name, var_label, type,
                    n_valid, pct_miss, range_or_cats)

    all_parts[[length(all_parts) + 1]] <- cb
  }
}

# =============================================================================
# Combine and compute in_all_waves
# =============================================================================
r1 <- dplyr::bind_rows(all_parts)

country_n_waves <- r1 |>
  dplyr::distinct(country, wave) |>
  dplyr::count(country, name = "n_waves")

var_n_waves <- r1 |>
  dplyr::distinct(country, wave, var_name) |>
  dplyr::count(country, var_name, name = "n_var_waves")

r1 <- r1 |>
  dplyr::left_join(country_n_waves, by = "country") |>
  dplyr::left_join(var_n_waves,     by = c("country", "var_name")) |>
  dplyr::mutate(in_all_waves = n_var_waves == n_waves) |>
  dplyr::select(-n_waves, -n_var_waves) |>
  dplyr::arrange(country, wave, var_name)

# =============================================================================
# Save GGS_R1.csv
# =============================================================================
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
out_path <- file.path(OUT_DIR, "GGS_R1.csv")
readr::write_excel_csv(r1, out_path)
message(sprintf("\nSaved: %s  (%d rows)", out_path, nrow(r1)))

# =============================================================================
# Update index.csv (append R1 entries alongside existing R2)
# =============================================================================
r1_index <- r1 |>
  dplyr::group_by(country) |>
  dplyr::summarise(
    round   = 1L,
    waves   = paste(sort(unique(wave)), collapse = ", "),
    n_vars  = dplyr::n_distinct(var_name),
    file    = "GGS_R1.csv",
    .groups = "drop"
  ) |>
  dplyr::select(country, round, waves, n_vars, file)

existing_index <- tryCatch(
  readr::read_csv(file.path(OUT_DIR, "index.csv"), show_col_types = FALSE),
  error = function(e) tibble::tibble()
)
full_index <- dplyr::bind_rows(
  existing_index |> dplyr::filter(round != 1L),
  r1_index
) |>
  dplyr::arrange(round, country)

readr::write_excel_csv(full_index, file.path(OUT_DIR, "index.csv"))
message("Updated: data/codebooks/index.csv")

# =============================================================================
# Summary
# =============================================================================
cat("\n========== BUILD SUMMARY (R1) ==========\n")
print(r1_index)
cat("=========================================\n")
