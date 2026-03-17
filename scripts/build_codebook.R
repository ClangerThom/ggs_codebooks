# =============================================================================
# build_codebook.R
# Purpose : Functions to extract variable metadata from GGS .dta files for
#           one country-round and return a tidy data frame.
#           Sourced by build_all.R; not intended to be run directly.
#
# Schema  : country | round | wave | var_name | var_label | type |
#           n_valid | pct_miss | range_or_cats | in_all_waves
# =============================================================================

library(haven)
library(labelled)
library(dplyr)
library(purrr)

# -----------------------------------------------------------------------------
# extract_var_info()
# Returns one row per variable for a single wave of a single country-round.
# -----------------------------------------------------------------------------
extract_var_info <- function(df, country, round, wave) {
  n_rows <- nrow(df)

  purrr::imap_dfr(df, function(col, col_name) {

    # Variable label
    vlab <- labelled::var_label(col)
    if (is.null(vlab) || identical(vlab, "")) vlab <- attr(col, "label")
    vlab <- if (is.null(vlab)) NA_character_ else as.character(vlab)

    # Type: categorical only if there are value labels for *non-missing* codes.
    # Stata stores extended missing values (.a, .b, ... .z) as tagged NAs with
    # labels (e.g. "Refusal", "Not applicable"). Filtering those out prevents
    # genuinely continuous variables from being misclassified as categorical.
    vlabs       <- labelled::val_labels(col)
    valid_vlabs <- NULL
    if (!is.null(vlabs) && length(vlabs) > 0) {
      keep        <- !haven::is_tagged_na(vlabs) & !is.na(vlabs)
      valid_vlabs <- vlabs[keep]
    }
    is_cat <- length(valid_vlabs) > 0
    type   <- if (is_cat) "categorical" else "numeric"

    # Missingness
    n_miss   <- sum(is.na(col))
    n_valid  <- n_rows - n_miss
    pct_miss <- round(n_miss / n_rows * 100, 1)

    # range_or_cats
    if (is_cat) {
      codes   <- as.numeric(valid_vlabs)
      labels  <- names(valid_vlabs)
      ord     <- order(codes)
      pairs   <- paste0(codes[ord], "=", labels[ord])
      raw_str <- paste(pairs, collapse = "; ")
      range_or_cats <- if (nchar(raw_str) > 200) {
        paste0(substr(raw_str, 1, 197), "...")
      } else {
        raw_str
      }
    } else {
      num_col <- suppressWarnings(as.numeric(col))
      mn      <- suppressWarnings(min(num_col, na.rm = TRUE))
      mx      <- suppressWarnings(max(num_col, na.rm = TRUE))
      range_or_cats <- if (is.infinite(mn) || is.infinite(mx)) {
        NA_character_
      } else {
        paste0(mn, "-", mx)
      }
    }

    tibble::tibble(
      country       = country,
      round         = round,
      wave          = as.character(wave),
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
# build_country_round()
# Reads all waves for one country-round, extracts metadata, adds in_all_waves.
#
# Args:
#   country    : ISO3 code string, e.g. "CZE"
#   round      : integer, 1 or 2
#   wave_files : named character vector — names are wave labels (e.g. "1", "2",
#                "1_register"), values are paths to .dta files
#
# Returns: data frame with one row per variable x wave
# -----------------------------------------------------------------------------
build_country_round <- function(country, round, wave_files) {

  all_waves <- purrr::imap_dfr(wave_files, function(path, wave) {
    message(sprintf("  Reading %s R%s W%s ...", country, round, wave))
    df <- haven::read_dta(path)
    message(sprintf("    %d rows x %d cols", nrow(df), ncol(df)))
    extract_var_info(df, country, round, wave)
  })

  # in_all_waves: TRUE if var_name appears in every wave of this country-round.
  # For single-wave countries this is trivially TRUE for all variables.
  wave_labels <- names(wave_files)
  if (length(wave_labels) > 1) {
    vars_in_all <- all_waves |>
      dplyr::distinct(wave, var_name) |>
      dplyr::count(var_name) |>
      dplyr::filter(n == length(wave_labels)) |>
      dplyr::pull(var_name)
    all_waves <- all_waves |>
      dplyr::mutate(in_all_waves = var_name %in% vars_in_all)
  } else {
    all_waves <- all_waves |>
      dplyr::mutate(in_all_waves = TRUE)
  }

  all_waves
}
