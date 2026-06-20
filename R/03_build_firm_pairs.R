source(file.path("R", "00_helpers.R"))

build_firm_pairs <- function(coef_path = file.path("data_intermediate", "accounting_coefficients.rds")) {
  coefs <- as.data.table(readRDS(coef_path))
  require_columns(coefs, c("gvkey1", "datadate1", "sic2", "year", "a_i", "b_i"), "accounting_coefficients")

  firms <- unique(coefs[, .(gvkey1, datadate1, sic2, year, a_i, b_i)])
  setorder(firms, year, gvkey1)
  firms[, id := seq_len(.N), by = year]

  peers <- firms[, .(gvkey_j = gvkey1, sic2, year, a_j = a_i, b_j = b_i)]
  pairs <- merge(firms, peers, by = c("sic2", "year"), allow.cartesian = TRUE)
  pairs <- pairs[gvkey1 != gvkey_j]
  pairs[, `:=`(a_dif = a_i - a_j, b_dif = b_i - b_j)]
  pairs <- pairs[, .(gvkey1, datadate1, sic2, year, gvkey_j, a_dif, b_dif)]
  setorder(pairs, year, gvkey1, gvkey_j)

  append_diagnostic("step3", "firm_pair_year_candidates", nrow(pairs))
  append_diagnostic("step3", "firm_years_with_peers", uniqueN(pairs, by = c("gvkey1", "datadate1")))
  write_rds(pairs, file.path("data_intermediate", "firm_pairs.rds"))
  invisible(pairs)
}

if (sys.nframe() == 0L) {
  build_firm_pairs()
}
