source(file.path("R", "00_helpers.R"))

estimate_accounting_functions <- function(step1_path = file.path("data_intermediate", "step1_firm_quarter.rds"),
                                          begyear = 1981L,
                                          endyear = 2009L,
                                          window_diagnostics_path = file.path("reports", "window_diagnostics.csv")) {
  step1 <- as.data.table(readRDS(step1_path))
  require_columns(step1, c("gvkey", "datadate", "fqenddt", "datacqtr", "sic2", "dnibe", "bhr"), "step1")
  step1[, `:=`(
    datadate = as_idate(datadate, "step1.datadate"),
    fqenddt = as_idate(fqenddt, "step1.fqenddt")
  )]

  candidates <- unique(step1[datadate == fqenddt, .(gvkey1 = gvkey, datadate1 = datadate, fqenddt1 = fqenddt, datacqtr1 = datacqtr, sic2)])
  candidates[, bfqenddt := month_begin_shift(fqenddt1, -47L)]

  windows <- merge(candidates, step1[, .(gvkey1 = gvkey, fqenddt, dnibe, bhr)], by = "gvkey1", allow.cartesian = TRUE)
  windows <- windows[bfqenddt <= fqenddt & fqenddt <= fqenddt1 & !is.na(dnibe) & !is.na(bhr)]
  windows[, year := data.table::year(datadate1)]
  windows[, bfqenddt := NULL]
  setorder(windows, gvkey1, datadate1, fqenddt1, fqenddt)

  window_diag <- build_window_diagnostics(windows)
  ensure_dir(dirname(window_diagnostics_path))
  fwrite(window_diag, window_diagnostics_path)
  append_diagnostic("step2", "window_duplicate_fqenddt_rows", sum(window_diag$duplicate_fqenddt_rows, na.rm = TRUE))
  append_diagnostic("step2", "windows_with_irregular_quarter_spacing", sum(window_diag$irregular_quarter_spacing, na.rm = TRUE))
  append_diagnostic("step2", "windows_with_missing_fiscal_quarter_sequence", sum(window_diag$missing_fiscal_quarter_sequence, na.rm = TRUE))

  counts <- windows[, .(n = .N), by = .(gvkey1, datadate1, fqenddt1)]
  windows <- counts[n >= 14L & n <= 16L][windows, on = .(gvkey1, datadate1, fqenddt1), nomatch = 0L]
  if (nrow(windows)) {
    retained_counts <- windows[, .(n_valid_obs = .N), by = .(gvkey1, datadate1, fqenddt1)]
    bad_counts <- retained_counts[!(n_valid_obs >= 14L & n_valid_obs <= 16L)]
    if (nrow(bad_counts)) {
      fwrite(bad_counts, file.path("reports", "window_count_failures.csv"))
      stop("Retained accounting windows outside the required 14-16 observation range; see reports/window_count_failures.csv", call. = FALSE)
    }
  }
  windows[, n := NULL]

  coefs <- windows[, ols_intercept_slope(dnibe, bhr), by = .(gvkey1, datadate1, fqenddt1, datacqtr1, sic2)]
  coefs[, year := data.table::year(datadate1)]
  delete_outside_percentiles(coefs, "a_i", "year")
  delete_outside_percentiles(coefs, "b_i", "year")

  coefs <- coefs[
    data.table::year(datadate1) >= begyear & data.table::year(datadate1) <= endyear &
      !is.na(a_i) & !is.na(b_i)
  ]

  windows <- merge(windows, coefs, by = c("gvkey1", "datadate1", "fqenddt1", "datacqtr1", "sic2", "year"), all = FALSE)

  industry_counts <- unique(windows[, .(gvkey1, year, sic2)])[, .(count = uniqueN(gvkey1)), by = .(sic2, year)]
  windows <- merge(windows, industry_counts, by = c("sic2", "year"), all.x = TRUE)
  windows <- windows[count >= 11L]
  setorder(windows, gvkey1, datadate1, fqenddt1, fqenddt)

  append_diagnostic("step2", "accounting_window_rows", nrow(windows))
  append_diagnostic("step2", "firm_years", uniqueN(windows, by = c("gvkey1", "datadate1")))
  append_diagnostic("step2", "industry_years", uniqueN(windows, by = c("sic2", "year")))

  write_rds(windows, file.path("data_intermediate", "step2_accounting_windows.rds"))
  write_rds(unique(windows[, .(gvkey1, datadate1, fqenddt1, datacqtr1, sic2, year, a_i, b_i, count)]),
            file.path("data_intermediate", "accounting_coefficients.rds"))
  invisible(windows)
}

if (sys.nframe() == 0L) {
  estimate_accounting_functions()
}
