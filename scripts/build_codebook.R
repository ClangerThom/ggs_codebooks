# =============================================================================
# build_codebook.R
# Purpose : Functions to extract variable metadata from GGS .dta files for
#           one country-round and return a tidy data frame.
#           Sourced by build_all.R; not intended to be run directly.
#
# Schema  : country, country_name, round, wave,
#           var_name, var_label, module, type,
#           n_total, n_valid, pct_miss,
#           range_or_cats, mean, median, sd, q1, q3, n_unique,
#           tagged_na_summary, in_all_waves, source_file
# =============================================================================

library(haven)
library(labelled)
library(dplyr)
library(purrr)

# -----------------------------------------------------------------------------
# Shared lookup tables — sourced into both build_all.R and build_r1.R
# -----------------------------------------------------------------------------

# ISO3 -> display country name (covers all GGS R1 + R2 countries currently
# present in the project; extend as new countries are added).
ISO3_NAME_MAP <- c(
  ARG = "Argentina",  AUS = "Australia",       AUT = "Austria",
  BEL = "Belgium",    BGR = "Bulgaria",        BLR = "Belarus",
  CZE = "Czech Republic", DEU = "Germany",     DNK = "Denmark",
  EST = "Estonia",    FIN = "Finland",         FRA = "France",
  GBR = "United Kingdom", GEO = "Georgia",     HKG = "Hong Kong",
  HRV = "Croatia",    HUN = "Hungary",         ITA = "Italy",
  KAZ = "Kazakhstan", LTU = "Lithuania",       MDA = "Moldova",
  NLD = "Netherlands", NOR = "Norway",         POL = "Poland",
  ROU = "Romania",    RUS = "Russia",          SWE = "Sweden",
  TWN = "Taiwan",     URY = "Uruguay"
)

# Path to the curated module prefix lookup
MODULE_PREFIX_PATH <- "data/codebooks/module_prefixes.csv"

load_module_prefixes <- function(path = MODULE_PREFIX_PATH) {
  if (!file.exists(path)) return(NULL)
  readr::read_csv(path, show_col_types = FALSE)
}

# -----------------------------------------------------------------------------
# assign_module()
# Maps var_name -> module via prefix lookup. R1 strips the leading wave letter
# (a/b/c) before matching, since R1 prefixes the wave onto every var name.
# Longest prefix wins so that "dv_" beats a hypothetical "d".
# -----------------------------------------------------------------------------
assign_module <- function(var_names, round, prefix_map) {
  if (is.null(prefix_map) || nrow(prefix_map) == 0)
    return(rep(NA_character_, length(var_names)))

  pm <- prefix_map[prefix_map$round == round, , drop = FALSE]
  if (nrow(pm) == 0) return(rep(NA_character_, length(var_names)))
  pm <- pm[order(-nchar(pm$prefix)), , drop = FALSE]

  stems <- if (round == 1L) sub("^[a-c]", "", var_names) else var_names

  vapply(stems, function(s) {
    for (k in seq_len(nrow(pm))) {
      if (startsWith(s, pm$prefix[k])) return(pm$module[k])
    }
    NA_character_
  }, character(1), USE.NAMES = FALSE)
}

# -----------------------------------------------------------------------------
# build_tagged_na_summary()
# Builds e.g. ".a=Don't know (12); .b=Refusal (3)" from a haven_labelled column.
# Tagged NAs (.a-.z) are how Stata stores extended missing reasons; haven
# preserves these and exposes the tag char via na_tag().
# -----------------------------------------------------------------------------
build_tagged_na_summary <- function(col) {
  if (!inherits(col, "haven_labelled")) return(NA_character_)
  vlabs <- labelled::val_labels(col)
  if (is.null(vlabs) || length(vlabs) == 0) return(NA_character_)

  tagged_idx <- haven::is_tagged_na(vlabs)
  if (!any(tagged_idx)) return(NA_character_)

  tagged_lbls  <- iconv(names(vlabs)[tagged_idx], to = "UTF-8", sub = "?")
  tagged_chars <- haven::na_tag(vlabs[tagged_idx])

  data_tags <- haven::na_tag(col)
  if (all(is.na(data_tags))) return(NA_character_)

  counts <- table(data_tags)
  if (length(counts) == 0) return(NA_character_)

  parts <- vapply(names(counts), function(t) {
    lbl_idx <- which(tagged_chars == t)
    lbl <- if (length(lbl_idx) > 0) tagged_lbls[lbl_idx[1]] else "(unlabelled)"
    sprintf(".%s=%s (%d)", t, lbl, as.integer(counts[[t]]))
  }, character(1))
  paste(parts, collapse = "; ")
}

# -----------------------------------------------------------------------------
# extract_var_info()
# One row per variable for a single wave of a single country-round.
# -----------------------------------------------------------------------------
extract_var_info <- function(df, country, round, wave,
                             source_file  = NA_character_,
                             country_name = NA_character_) {
  n_rows <- nrow(df)

  purrr::imap_dfr(df, function(col, col_name) {

    # ── Variable label ──────────────────────────────────────────────────────
    vlab <- labelled::var_label(col)
    if (is.null(vlab) || identical(vlab, "")) vlab <- attr(col, "label")
    vlab <- if (is.null(vlab)) NA_character_ else
      iconv(as.character(vlab), to = "UTF-8", sub = "?")

    # ── Type detection (string > categorical > numeric) ─────────────────────
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

    # ── Missingness ─────────────────────────────────────────────────────────
    n_miss   <- sum(is.na(col))
    n_valid  <- n_rows - n_miss
    pct_miss <- round(n_miss / n_rows * 100, 1)

    # ── value_min / value_max / cat_levels / distribution stats / n_unique ──
    value_min <- value_max <- NA_real_
    cat_levels <- NA_character_
    mean_v <- median_v <- sd_v <- q1_v <- q3_v <- NA_real_
    n_unique <- NA_integer_

    if (type == "string") {
      n_unique <- dplyr::n_distinct(col, na.rm = TRUE)

    } else if (type == "categorical") {
      codes   <- as.numeric(valid_vlabs)
      labels  <- iconv(names(valid_vlabs), to = "UTF-8", sub = "?")
      ord     <- order(codes)
      pairs   <- paste0(codes[ord], "=", labels[ord])
      raw_str <- paste(pairs, collapse = "; ")
      cat_levels <- if (nchar(raw_str, type = "bytes") > 200) {
        paste0(substr(raw_str, 1, 197), "...")
      } else {
        raw_str
      }

    } else {  # numeric
      num_col <- suppressWarnings(as.numeric(col))
      mn      <- suppressWarnings(min(num_col, na.rm = TRUE))
      mx      <- suppressWarnings(max(num_col, na.rm = TRUE))
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

    # ── Tagged-NA count + label breakdown ───────────────────────────────────
    n_tagged_na <- if (is.numeric(col) || inherits(col, "haven_labelled")) {
      as.integer(sum(!is.na(haven::na_tag(col))))
    } else {
      0L
    }
    tagged_na_summary <- build_tagged_na_summary(col)

    tibble::tibble(
      country           = country,
      country_name      = country_name,
      round             = round,
      wave              = as.character(wave),
      var_name          = col_name,
      var_label         = vlab,
      type              = type,
      n_total           = n_rows,
      n_valid           = n_valid,
      pct_miss          = pct_miss,
      value_min         = value_min,
      value_max         = value_max,
      cat_levels        = cat_levels,
      mean              = mean_v,
      median            = median_v,
      sd                = sd_v,
      q1                = q1_v,
      q3                = q3_v,
      n_unique          = n_unique,
      n_tagged_na       = n_tagged_na,
      tagged_na_summary = tagged_na_summary,
      source_file       = source_file
    )
  })
}

# -----------------------------------------------------------------------------
# build_country_round()
# Reads all waves for one country-round, extracts metadata, adds in_all_waves
# and module, returns the final column order.
#
# Args:
#   country      : ISO3 code string, e.g. "CZE"
#   round        : integer, 1 or 2
#   wave_files   : named character vector — names are wave labels (e.g. "1",
#                  "2", "1_register"), values are paths to .dta files
#   country_name : optional display name; defaults to ISO3_NAME_MAP[country]
#   prefix_map   : optional module-prefix lookup (data frame); defaults to
#                  load_module_prefixes()
# -----------------------------------------------------------------------------
build_country_round <- function(country, round, wave_files,
                                country_name = NULL,
                                prefix_map   = NULL) {

  if (is.null(country_name)) {
    country_name <- ISO3_NAME_MAP[country]
    if (is.na(country_name)) country_name <- NA_character_
  }
  if (is.null(prefix_map)) prefix_map <- load_module_prefixes()

  all_waves <- purrr::imap_dfr(wave_files, function(path, wave) {
    message(sprintf("  Reading %s R%s W%s ...", country, round, wave))
    df <- haven::read_dta(path)
    message(sprintf("    %d rows x %d cols", nrow(df), ncol(df)))
    extract_var_info(df, country, round, wave,
                     source_file  = basename(path),
                     country_name = country_name)
  })

  # in_all_waves: TRUE if var_name appears in every wave of this country-round.
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

  all_waves |>
    dplyr::mutate(module = assign_module(var_name, round, prefix_map)) |>
    dplyr::select(country, country_name, round, wave,
                  var_name, var_label, module, type,
                  n_total, n_valid, pct_miss,
                  value_min, value_max, cat_levels,
                  mean, median, sd, q1, q3, n_unique,
                  n_tagged_na, tagged_na_summary,
                  in_all_waves, source_file)
}
