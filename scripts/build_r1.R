# =============================================================================
# build_r1.R
# Purpose : Build GGS_R1.csv from consolidated multi-country wave files.
#           R1 uses one file per wave (all countries combined), unlike R2.
#
# Strategy: Two passes per wave —
#   1. Metadata pass (full dataset): var_label, type, categorical cat_levels
#   2. Per-country pass: n_total, n_valid, pct_miss, numeric ranges,
#                        distribution stats, n_unique, tagged_na_summary
#
# Run from repo root:
#   Rscript scripts/build_r1.R
# =============================================================================

source("scripts/build_codebook.R")   # loads haven, labelled, dplyr, purrr
library(readr)
library(tibble)

RAW_DIR <- "data/raw"
OUT_DIR <- "data/codebooks"

# GGS R1 country name (as used in the .dta value labels) -> ISO3
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

WAVE_INFO <- list(
  list(wave = "1", path = file.path(RAW_DIR, "R1_W1.dta"), cvar = "acountry"),
  list(wave = "2", path = file.path(RAW_DIR, "R1_W2.dta"), cvar = "bcountry"),
  list(wave = "3", path = file.path(RAW_DIR, "R1_W3.dta"), cvar = "ccountry")
)

prefix_map <- load_module_prefixes()

# =============================================================================
all_parts <- list()

for (wi in WAVE_INFO) {
  wave <- wi$wave
  path <- wi$path
  cvar <- wi$cvar

  message(sprintf("\n=== Wave %s: reading %s ===", wave, basename(path)))
  df <- haven::read_dta(path)
  message(sprintf("  %d rows x %d cols", nrow(df), ncol(df)))

  # Countries present in this wave (with at least 1 row)
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
  # Pass 1 — metadata from full dataset (label, type, categorical cat_levels)
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
    type   <- if (is.character(col))   "string"
              else if (is_cat)         "categorical"
              else                     "numeric"

    cat_str <- if (is_cat) {
      codes   <- as.numeric(valid_vlabs)
      labels  <- iconv(names(valid_vlabs), to = "UTF-8", sub = "?")
      ord     <- order(codes)
      pairs   <- paste0(codes[ord], "=", labels[ord])
      raw_str <- paste(pairs, collapse = "; ")
      if (nchar(raw_str, type = "bytes") > 200)
        paste0(substr(raw_str, 1, 197), "...") else raw_str
    } else {
      NA_character_
    }

    tibble::tibble(var_name = col_name, var_label = vlab,
                   type = type, cat_levels = cat_str)
  })

  # ---------------------------------------------------------------------------
  # Pass 2 — per-country: n_total, missingness, numeric ranges + dist stats,
  #          n_unique, tagged_na_summary
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

    var_type_lookup <- setNames(meta$type, meta$var_name)

    per_var <- purrr::imap_dfr(sub_df, function(col, col_name) {
      n_miss   <- sum(is.na(col))
      n_valid  <- n_rows - n_miss
      pct_miss <- round(n_miss / n_rows * 100, 1)
      var_type <- var_type_lookup[[col_name]]

      value_min <- value_max <- NA_real_
      mean_v <- median_v <- sd_v <- q1_v <- q3_v <- NA_real_
      n_unique <- NA_integer_

      if (var_type == "string") {
        n_unique <- dplyr::n_distinct(col, na.rm = TRUE)

      } else if (var_type == "numeric") {
        num_col <- suppressWarnings(as.numeric(col))
        mn <- suppressWarnings(min(num_col, na.rm = TRUE))
        mx <- suppressWarnings(max(num_col, na.rm = TRUE))
        if (!is.infinite(mn)) value_min <- mn
        if (!is.infinite(mx)) value_max <- mx
        if (n_valid > 0) {
          mean_v   <- signif(mean(num_col, na.rm = TRUE), 4)
          median_v <- signif(stats::median(num_col, na.rm = TRUE), 4)
          sd_v     <- signif(stats::sd(num_col, na.rm = TRUE), 4)
          qs       <- suppressWarnings(stats::quantile(num_col,
                        c(0.25, 0.75), na.rm = TRUE, names = FALSE))
          q1_v     <- signif(qs[1], 4)
          q3_v     <- signif(qs[2], 4)
          n_unique <- dplyr::n_distinct(num_col, na.rm = TRUE)
        }
      }

      n_tagged_na <- if (is.numeric(col) || inherits(col, "haven_labelled")) {
        as.integer(sum(!is.na(haven::na_tag(col))))
      } else {
        0L
      }
      tagged_na_summary <- build_tagged_na_summary(col)

      tibble::tibble(
        var_name = col_name,
        n_total = n_rows, n_valid = n_valid, pct_miss = pct_miss,
        value_min = value_min, value_max = value_max,
        mean = mean_v, median = median_v, sd = sd_v,
        q1 = q1_v, q3 = q3_v,
        n_unique = n_unique,
        n_tagged_na = n_tagged_na,
        tagged_na_summary = tagged_na_summary
      )
    })

    cb <- meta |>
      dplyr::left_join(per_var, by = "var_name") |>
      dplyr::mutate(
        country      = iso3,
        country_name = unname(ISO3_NAME_MAP[iso3]),
        round        = 1L,
        wave         = wave,
        source_file  = basename(path)
      ) |>
      dplyr::select(country, country_name, round, wave,
                    var_name, var_label, type,
                    n_total, n_valid, pct_miss,
                    value_min, value_max, cat_levels,
                    mean, median, sd, q1, q3, n_unique,
                    n_tagged_na, tagged_na_summary, source_file)

    all_parts[[length(all_parts) + 1]] <- cb
  }
}

# =============================================================================
# Combine, compute in_all_waves, assign module, finalise column order
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
  dplyr::mutate(in_all_waves = n_var_waves == n_waves,
                module = assign_module(var_name, 1L, prefix_map)) |>
  dplyr::select(country, country_name, round, wave,
                var_name, var_label, module, type,
                n_total, n_valid, pct_miss,
                value_min, value_max, cat_levels,
                mean, median, sd, q1, q3, n_unique,
                n_tagged_na, tagged_na_summary,
                in_all_waves, source_file) |>
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
