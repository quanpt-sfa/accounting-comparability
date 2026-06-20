library(testthat)
library(data.table)

source(file.path("R", "00_helpers.R"))
source(file.path("R", "03_build_firm_pairs.R"))
source(file.path("R", "04_compute_comparability.R"))
source(file.path("R", "05_validate_against_verdi.R"))

test_that("date parsing distinguishes supported formats and rejects serial dates", {
  diag_path <- tempfile(fileext = ".csv")
  expect_equal(as_idate(as.IDate("2020-12-31"), "idate", diag_path), as.IDate("2020-12-31"))
  expect_equal(as_idate(as.Date("2020-12-31"), "date", diag_path), as.IDate("2020-12-31"))
  expect_equal(as_idate(20201231, "numeric_yyyymmdd", diag_path), as.IDate("2020-12-31"))
  expect_equal(as_idate("20201231", "character_yyyymmdd", diag_path), as.IDate("2020-12-31"))
  expect_equal(as_idate("2020-12-31", "character_iso", diag_path), as.IDate("2020-12-31"))
  expect_error(as_idate(44196, "unsupported_serial", diag_path), "Invalid or suspicious dates")
  expect_true(file.exists(diag_path))
})

test_that("rolling-window date construction keeps the 16-quarter DKV window", {
  end_date <- as.IDate("2020-12-31")
  begin_date <- month_begin_shift(end_date, -47L)
  quarters <- as.IDate(c(
    "2016-12-31", "2017-03-31", "2017-06-30", "2017-09-30",
    "2017-12-31", "2018-03-31", "2018-06-30", "2018-09-30",
    "2018-12-31", "2019-03-31", "2019-06-30", "2019-09-30",
    "2019-12-31", "2020-03-31", "2020-06-30", "2020-09-30",
    "2020-12-31"
  ))
  kept <- quarters[begin_date <= quarters & quarters <= end_date]
  expect_equal(length(kept), 16L)
  expect_equal(min(kept), as.IDate("2017-03-31"))
})

test_that("rolling-window diagnostics flag duplicate and irregular quarters", {
  windows <- data.table(
    gvkey1 = "A",
    datadate1 = as.IDate("2020-12-31"),
    fqenddt = as.IDate(c("2019-03-31", "2019-03-31", "2019-09-30")),
    dnibe = c(1, 2, 3),
    bhr = c(0.1, 0.2, 0.3)
  )
  diag <- build_window_diagnostics(windows)
  expect_equal(diag$duplicate_fqenddt_rows, 1L)
  expect_true(diag$irregular_quarter_spacing)
  expect_true(diag$missing_fiscal_quarter_sequence)
  expect_false(diag$window_count_ok)
})

test_that("same-industry firm-pair generation excludes self-pairs and keeps direction", {
  tmp <- tempfile(fileext = ".rds")
  coefs <- data.table(
    gvkey1 = c("A", "B", "C"),
    datadate1 = as.IDate(c("2020-12-31", "2020-12-31", "2020-12-31")),
    sic2 = c(10L, 10L, 20L),
    year = c(2020L, 2020L, 2020L),
    a_i = c(1, 2, 3),
    b_i = c(0.1, 0.2, 0.3)
  )
  saveRDS(coefs, tmp)
  pairs <- build_firm_pairs(tmp)
  expect_equal(nrow(pairs), 2L)
  expect_setequal(paste(pairs$gvkey1, pairs$gvkey_j), c("A B", "B A"))
})

test_that("comparability score has the SAS negative absolute-error sign convention", {
  windows <- data.table(
    gvkey1 = rep("A", 14),
    datadate1 = rep(as.IDate("2020-12-31"), 14),
    fqenddt = as.IDate("2017-09-30") + 0:13 * 91,
    bhr = rep(0.5, 14)
  )
  pairs <- data.table(
    gvkey1 = "A",
    datadate1 = as.IDate("2020-12-31"),
    gvkey_j = "B",
    a_dif = 0.01,
    b_dif = 0.02
  )
  wpath <- tempfile(fileext = ".rds")
  ppath <- tempfile(fileext = ".rds")
  saveRDS(windows, wpath)
  saveRDS(pairs, ppath)
  out <- compute_pairwise_comparability(wpath, ppath)
  expect_equal(out$acctcomp, -2)
})

test_that("missing earnings or returns are excluded from OLS helper", {
  fit <- ols_intercept_slope(y = c(1, 2, NA, 4), x = c(0, 1, 2, NA))
  expect_equal(fit$a_i, 1)
  expect_equal(fit$b_i, 1)
})

test_that("firm-pair-year scores aggregate to top-peer and industry firm-year measures", {
  pairs <- data.table(
    gvkey_i = rep("A", 12),
    datadate_i = rep(as.IDate("2020-12-31"), 12),
    gvkey_j = sprintf("P%02d", 1:12),
    acctcomp = -12:-1
  )
  path <- tempfile(fileext = ".rds")
  saveRDS(pairs, path)
  out <- aggregate_firm_year_comparability(path)
  expect_equal(out$n_acctcomp, 12L)
  expect_equal(out$m4_acctcomp, -2.5)
  expect_equal(out$m10_acctcomp, -5.5)
  expect_equal(out$ind_acctcomp, -6.5)
})

test_that("replication mode fails when reference files are missing", {
  expect_error(
    validate_against_verdi(mode = "replication", reference_pair_path = NULL, reference_firm_year_path = NULL),
    "reference_pair_path"
  )
})
