source(file.path("R", "00_helpers.R"))

estimate_accounting_functions <- function(step1_path = file.path("data_intermediate", "step1_firm_quarter.rds"),
                                          begyear = 1981L,
                                          endyear = 2009L) {
  step1 <- as.data.table(readRDS(step1_path))
  require_columns(step1, c("gvkey", "datadate", "fqenddt", "datacqtr", "sic2", "dnibe", "bhr"), "step1")

  candidates <- unique(step1[datadate == fqenddt, .(gvkey1 = gvkey, datadate1 = datadate, fqenddt1 = fqenddt, datacqtr1 = datacqtr, sic2)])
  candidates[, bfqenddt := month_begin_shift(fqenddt1, -47L)]

  windows <- merge(candidates, step1[, .(gvkey1 = gvkey, fqenddt, dnibe, bhr)], by = "gvkey1", allow.cartesian = TRUE)
  windows <- windows[bfqenddt <= fqenddt & fqenddt <= fqenddt1 & !is.na(dnibe) & !is.na(bhr)]
  windows[, year := data.table::year(datadate1)]
  windows[, bfqenddt := NULL]
  setorder(windows, gvkey1, datadate1, fqenddt1, fqenddt)

  counts <- windows[, .(n = .N), by = .(gvkey1, datadate1, fqenddt1)]
  windows <- counts[n >= 14L & n <= 16L][windows, on = .(gvkey1, datadate1, fqenddt1), nomatch = 0L]
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
