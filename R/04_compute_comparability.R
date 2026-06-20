source(file.path("R", "00_helpers.R"))

compute_pairwise_comparability <- function(window_path = file.path("data_intermediate", "step2_accounting_windows.rds"),
                                           pair_path = file.path("data_intermediate", "firm_pairs.rds")) {
  windows <- as.data.table(readRDS(window_path))
  pairs <- as.data.table(readRDS(pair_path))
  require_columns(windows, c("gvkey1", "datadate1", "fqenddt", "bhr"), "step2_accounting_windows")
  require_columns(pairs, c("gvkey1", "datadate1", "gvkey_j", "a_dif", "b_dif"), "firm_pairs")

  base <- windows[, .(gvkey1, datadate1, fqenddt, bhr)]
  pair_quarters <- merge(pairs, base, by = c("gvkey1", "datadate1"), allow.cartesian = TRUE)
  pair_quarters[, error := abs(a_dif + bhr * b_dif)]

  firm_pair_year <- pair_quarters[
    ,
    .(n = .N, me_error = mean(error)),
    by = .(gvkey_i = gvkey1, datadate_i = datadate1, gvkey_j)
  ][n >= 14L & n <= 16L]
  firm_pair_year[, acctcomp := sas_round(-1 * me_error * 100, 0.001)]
  firm_pair_year <- firm_pair_year[!is.na(acctcomp), .(gvkey_i, datadate_i, gvkey_j, acctcomp)]
  setorder(firm_pair_year, gvkey_i, datadate_i, gvkey_j)

  append_diagnostic("step4", "firm_pair_year_rows", nrow(firm_pair_year))
  append_diagnostic("step4", "acctcomp_mean", mean(firm_pair_year$acctcomp, na.rm = TRUE))
  append_diagnostic("step4", "acctcomp_median", stats::median(firm_pair_year$acctcomp, na.rm = TRUE))
  write_rds(firm_pair_year, file.path("data_output", "acctcomp_firmpairyear.rds"))
  invisible(firm_pair_year)
}

aggregate_firm_year_comparability <- function(pair_path = file.path("data_output", "acctcomp_firmpairyear.rds")) {
  pairs <- as.data.table(readRDS(pair_path))
  require_columns(pairs, c("gvkey_i", "datadate_i", "gvkey_j", "acctcomp"), "acctcomp_firmpairyear")

  acctcomp <- copy(pairs)
  setnames(acctcomp, c("gvkey_i", "datadate_i"), c("gvkey", "datadate"))
  acctcomp <- acctcomp[!is.na(acctcomp)]
  setorder(acctcomp, gvkey, datadate, -acctcomp)
  acctcomp[, rank := seq_len(.N), by = .(gvkey, datadate)]

  top4 <- acctcomp[rank <= 4L, .(m4_acctcomp = mean(acctcomp)), by = .(gvkey, datadate)]
  top10 <- acctcomp[rank <= 10L, .(m10_acctcomp = mean(acctcomp)), by = .(gvkey, datadate)]
  all_peers <- acctcomp[, .(
    n_acctcomp = .N,
    ind_acctcomp = mean(acctcomp),
    indmd_acctcomp = stats::median(acctcomp)
  ), by = .(gvkey, datadate)]

  firm_year <- Reduce(function(x, y) merge(x, y, by = c("gvkey", "datadate"), all = TRUE), list(top4, top10, all_peers))
  firm_year[, `:=`(
    m4_acctcomp = sas_round(m4_acctcomp, 0.01),
    m10_acctcomp = sas_round(m10_acctcomp, 0.01),
    ind_acctcomp = sas_round(ind_acctcomp, 0.01),
    indmd_acctcomp = sas_round(indmd_acctcomp, 0.01),
    year = data.table::year(datadate)
  )]
  setorder(firm_year, gvkey, datadate)

  append_diagnostic("step4", "firm_year_rows", nrow(firm_year))
  write_rds(firm_year, file.path("data_output", "acctcomp_firmyear.rds"))
  invisible(firm_year)
}

if (sys.nframe() == 0L) {
  compute_pairwise_comparability()
  aggregate_firm_year_comparability()
}
