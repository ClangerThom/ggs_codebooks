# =============================================================================
# build_all.R
# Purpose : Discover all .dta files in data/raw/, build GGS_R1.csv and
#           GGS_R2.csv, and write data/codebooks/index.csv.
#
# File naming convention expected in data/raw/:
#   {ISO3}_R{round}_W{wave_label}.dta
#   e.g. CZE_R2_W1.dta, SWE_R2_W1_register.dta
#
# Run from repo root:
#   Rscript scripts/build_all.R
# =============================================================================

source("scripts/build_codebook.R")
library(readr)
library(tibble)

RAW_DIR <- "data/raw"
OUT_DIR <- "data/codebooks"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# -----------------------------------------------------------------------------
# Discover and parse .dta filenames
# -----------------------------------------------------------------------------
dta_paths <- list.files(RAW_DIR, pattern = "\\.dta$", full.names = TRUE)

if (length(dta_paths) == 0) stop("No .dta files found in ", RAW_DIR)

parse_dta_name <- function(path) {
  fname <- tools::file_path_sans_ext(basename(path))
  # Match: ISO3 _ R{round} _ W{wave_label}
  m <- regexec("^([A-Z]{3})_R([0-9]+)_W(.+)$", fname)
  parts <- regmatches(fname, m)[[1]]
  if (length(parts) == 0) {
    warning("Skipping unrecognised filename: ", basename(path))
    return(NULL)
  }
  list(country = parts[2], round = as.integer(parts[3]), wave = parts[4], path = path)
}

parsed <- Filter(Negate(is.null), lapply(dta_paths, parse_dta_name))
message(sprintf("Found %d .dta file(s) matching naming convention.", length(parsed)))

# -----------------------------------------------------------------------------
# Group by country-round, build codebooks
# -----------------------------------------------------------------------------
group_keys <- paste0(sapply(parsed, `[[`, "country"), "_R", sapply(parsed, `[[`, "round"))
groups     <- split(parsed, group_keys)

r1_parts <- list()
r2_parts <- list()

for (key in sort(names(groups))) {
  grp     <- groups[[key]]
  country <- grp[[1]]$country
  round   <- grp[[1]]$round

  wave_files <- setNames(
    sapply(grp, `[[`, "path"),
    sapply(grp, `[[`, "wave")
  )
  # Sort waves so they appear in order (1 before 2, survey before register)
  wave_files <- wave_files[order(names(wave_files))]

  message(sprintf("\nBuilding: %s  Round %d  Waves: %s",
                  country, round, paste(names(wave_files), collapse = ", ")))

  cb <- build_country_round(country, round, wave_files)

  if (round == 1L) r1_parts[[length(r1_parts) + 1]] <- cb
  if (round == 2L) r2_parts[[length(r2_parts) + 1]] <- cb
}

# -----------------------------------------------------------------------------
# Write per-round CSVs
# -----------------------------------------------------------------------------
write_round_csv <- function(parts, round) {
  if (length(parts) == 0) return(invisible(NULL))
  df   <- dplyr::bind_rows(parts)
  path <- file.path(OUT_DIR, sprintf("GGS_R%d.csv", round))
  readr::write_excel_csv(df, path)
  message(sprintf("\nSaved: %s  (%d rows)", path, nrow(df)))
  invisible(df)
}

r1 <- write_round_csv(r1_parts, 1L)
r2 <- write_round_csv(r2_parts, 2L)

# -----------------------------------------------------------------------------
# Write index.csv
# -----------------------------------------------------------------------------
index_rows <- lapply(sort(names(groups)), function(key) {
  grp     <- groups[[key]]
  country <- grp[[1]]$country
  round   <- grp[[1]]$round
  waves   <- paste(sort(sapply(grp, `[[`, "wave")), collapse = ", ")
  n_vars  <- nrow(if (round == 1L) r1 else r2 |>
    dplyr::filter(country == !!country, round == !!round) |>
    dplyr::distinct(var_name))
  tibble::tibble(
    country = country,
    round   = round,
    waves   = waves,
    n_vars  = n_vars,
    file    = sprintf("GGS_R%d.csv", round)
  )
})

index <- dplyr::bind_rows(index_rows)
readr::write_excel_csv(index, file.path(OUT_DIR, "index.csv"))
message(sprintf("\nSaved: data/codebooks/index.csv"))

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
cat("\n========== BUILD SUMMARY ==========\n")
print(index)
cat("====================================\n")
