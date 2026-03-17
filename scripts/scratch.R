# scratch.R — temporary working script
library(haven)
library(labelled)
library(dplyr)

w1 <- haven::read_dta("data/raw/R1_W1.dta")
cat(sprintf("W1: %d rows x %d cols\n", nrow(w1), ncol(w1)))

# Quick check of W2 and W3 structure
for (wf in c("data/raw/R1_W2.dta", "data/raw/R1_W3.dta")) {
  df <- haven::read_dta(wf)
  cat(sprintf("\n%s: %d rows x %d cols\n", basename(wf), nrow(df), ncol(df)))

  # Find country variable
  cvar <- names(df)[grepl("country", names(df), ignore.case = TRUE)][1]
  cat("Country var:", cvar, "\n")
  cat("Countries:\n")
  print(labelled::val_labels(df[[cvar]]))

  counts <- table(as.numeric(df[[cvar]]))
  cat("Counts by code:", paste(names(counts[counts > 0]), collapse=", "), "\n")
}
