# scratch.R — temporary working script
source("scripts/build_codebook.R")

cb <- build_country_round(
  country    = "CZE",
  round      = 2L,
  wave_files = c("1" = "data/raw/CZE_R2_W1.dta",
                 "2" = "data/raw/CZE_R2_W2.dta")
)

print(cb)
cat(sprintf("\n%d rows, %d vars in all waves\n",
            nrow(cb), sum(cb$in_all_waves & cb$wave == "1")))
