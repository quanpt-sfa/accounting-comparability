library(testthat)
library(data.table)

repo_root <- if (basename(getwd()) == "testthat") normalizePath(file.path("..", "..")) else getwd()
setwd(repo_root)
source(file.path(repo_root, "R", "00_helpers.R"))
source(file.path(repo_root, "R", "05_validate_against_verdi.R"))

firmyear_2009_fixture_path <- file.path(repo_root, "tests", "fixtures", "verdi_firmyear_reference_sample.csv")
pair_2013_fixture_path <- file.path(repo_root, "tests", "fixtures", "verdi_2013_firmpair_reference_sample.csv")
firmyear_2013_fixture_path <- file.path(repo_root, "tests", "fixtures", "verdi_2013_firmyear_reference_sample.csv")

cleanup_author_fixture_reports <- function() {
  files <- file.path(
    "reports",
    c(
      "validation_checks.csv",
      "validation_failures.csv",
      "validation_summary.csv",
      "hand_check_firm_pair_year_sample.rds",
      "hand_check_firm_year_sample.rds"
    )
  )
  unlink(files[file.exists(files)])
}

expect_metric_columns_numeric <- function(dt, cols) {
  for (col in cols) {
    expect_true(is.numeric(dt[[col]]), info = sprintf("%s should be numeric", col))
    expect_false(anyNA(dt[[col]]), info = sprintf("%s should not contain missing values", col))
  }
}

test_that("author fixture schemas, parsed dates, metric types, and year ranges are stable", {
  fy_2009 <- fread(firmyear_2009_fixture_path, keepLeadingZeros = TRUE)
  pair_2013 <- fread(pair_2013_fixture_path, keepLeadingZeros = TRUE)
  fy_2013 <- fread(firmyear_2013_fixture_path, keepLeadingZeros = TRUE)

  expect_named(fy_2009, c("gvkey", "datadate", "m4_acctcomp", "m10_acctcomp", "n_acctcomp", "ind_acctcomp", "indmd_acctcomp", "year"))
  expect_named(pair_2013, c("gvkey_i", "datadate_i", "gvkey_j", "acctcomp"))
  expect_named(fy_2013, c("gvkey", "datadate", "m4_acctcomp", "m10_acctcomp", "n_acctcomp", "ind_acctcomp", "indmd_acctcomp", "year"))

  expect_equal(as_idate(fy_2009$datadate, "fixture_2009.datadate"), as.IDate(fy_2009$datadate))
  expect_equal(as_idate(pair_2013$datadate_i, "fixture_2013_pair.datadate_i"), as.IDate(pair_2013$datadate_i))
  expect_equal(as_idate(fy_2013$datadate, "fixture_2013_firmyear.datadate"), as.IDate(fy_2013$datadate))

  expect_metric_columns_numeric(fy_2009, c("m4_acctcomp", "m10_acctcomp", "n_acctcomp", "ind_acctcomp", "indmd_acctcomp", "year"))
  expect_metric_columns_numeric(pair_2013, "acctcomp")
  expect_metric_columns_numeric(fy_2013, c("m4_acctcomp", "m10_acctcomp", "n_acctcomp", "ind_acctcomp", "indmd_acctcomp", "year"))

  expect_equal(range(as.integer(fy_2009$year)), c(1981L, 1990L))
  expect_equal(range(as.integer(substr(pair_2013$datadate_i, 1, 4))), c(1981L, 2013L))
  expect_equal(range(as.integer(fy_2013$year)), c(1981L, 2013L))
})

test_that("known fixture rows match explicit Verdi reference values", {
  fy_2009 <- fread(firmyear_2009_fixture_path, keepLeadingZeros = TRUE)
  pair_2013 <- fread(pair_2013_fixture_path, keepLeadingZeros = TRUE)
  fy_2013 <- fread(firmyear_2013_fixture_path, keepLeadingZeros = TRUE)

  row_001020 <- fy_2009[gvkey == "001020" & datadate == "1981-12-31"]
  expect_equal(nrow(row_001020), 1L)
  expect_equal(row_001020$m4_acctcomp, -0.80)
  expect_equal(row_001020$m10_acctcomp, -1.10)
  expect_equal(row_001020$n_acctcomp, 17)
  expect_equal(row_001020$ind_acctcomp, -1.81)
  expect_equal(row_001020$indmd_acctcomp, -1.35)

  row_282189 <- fy_2013[gvkey == "282189" & datadate == "2013-06-30"]
  expect_equal(nrow(row_282189), 1L)
  expect_equal(row_282189$m4_acctcomp, -0.18)
  expect_equal(row_282189$m10_acctcomp, -0.28)
  expect_equal(row_282189$n_acctcomp, 133)
  expect_equal(row_282189$ind_acctcomp, -3.17)
  expect_equal(row_282189$indmd_acctcomp, -2.14)

  selected_pairs <- pair_2013[gvkey_i == "282189" & datadate_i == "2013-06-30" & gvkey_j %in% c("174169", "179831", "273726")]
  setorder(selected_pairs, gvkey_j)
  expect_equal(selected_pairs$gvkey_j, c("174169", "179831", "273726"))
  expect_equal(selected_pairs$acctcomp, c(-7.212, -0.416, -0.467))
})

test_that("replication validation passes for hand-built actual outputs matching fixture oracles", {
  cleanup_author_fixture_reports()
  on.exit(cleanup_author_fixture_reports(), add = TRUE)

  pair_actual <- data.table(
    gvkey_i = c("282189", "282189", "282189"),
    datadate_i = as.IDate(c("2013-06-30", "2013-06-30", "2013-06-30")),
    gvkey_j = c("174169", "179831", "273726"),
    acctcomp = c(-7.212, -0.416, -0.467)
  )
  firmyear_actual <- data.table(
    gvkey = c("001020", "282189"),
    datadate = as.IDate(c("1981-12-31", "2013-06-30")),
    m4_acctcomp = c(-0.80, -0.18),
    m10_acctcomp = c(-1.10, -0.28),
    n_acctcomp = c(17, 133),
    ind_acctcomp = c(-1.81, -3.17),
    indmd_acctcomp = c(-1.35, -2.14),
    year = c(1981, 2013)
  )

  pair_ref_path <- tempfile(fileext = ".csv")
  firmyear_ref_path <- tempfile(fileext = ".csv")
  fwrite(pair_actual[, .(gvkey_i, datadate_i, gvkey_j, acctcomp)], pair_ref_path)
  fwrite(firmyear_actual, firmyear_ref_path)

  pair_path <- tempfile(fileext = ".rds")
  firmyear_path <- tempfile(fileext = ".rds")
  saveRDS(pair_actual, pair_path)
  saveRDS(firmyear_actual, firmyear_path)

  checks <- validate_against_verdi(
    pair_path = pair_path,
    firm_year_path = firmyear_path,
    reference_pair_path = pair_ref_path,
    reference_firm_year_path = firmyear_ref_path,
    mode = "replication",
    min_pair_correlation = 0.999,
    min_pair_near_exact_rate = 1,
    min_firm_year_correlation = 0.999,
    min_firm_year_near_exact_rate = 1
  )

  expect_equal(checks[check == "reference_pair_acctcomp_overlap_rows", as.numeric(value)], 3)
  expect_equal(checks[check == "reference_pair_acctcomp_near_exact_rate", as.numeric(value)], 1)
  expect_equal(checks[check == "reference_firm_year_m4_acctcomp_overlap_rows", as.numeric(value)], 2)
  expect_equal(checks[check == "reference_firm_year_m4_acctcomp_near_exact_rate", as.numeric(value)], 1)
})

test_that("replication validation fails for perturbed author-oracle values", {
  cleanup_author_fixture_reports()
  on.exit(cleanup_author_fixture_reports(), add = TRUE)

  pair_reference <- data.table(
    gvkey_i = c("282189", "282189", "282189"),
    datadate_i = as.IDate(c("2013-06-30", "2013-06-30", "2013-06-30")),
    gvkey_j = c("174169", "179831", "273726"),
    acctcomp = c(-7.212, -0.416, -0.467)
  )
  firmyear_reference <- data.table(
    gvkey = c("001020", "282189"),
    datadate = as.IDate(c("1981-12-31", "2013-06-30")),
    m4_acctcomp = c(-0.80, -0.18),
    m10_acctcomp = c(-1.10, -0.28),
    n_acctcomp = c(17, 133),
    ind_acctcomp = c(-1.81, -3.17),
    indmd_acctcomp = c(-1.35, -2.14),
    year = c(1981, 2013)
  )
  pair_actual <- copy(pair_reference)
  firmyear_actual <- copy(firmyear_reference)
  pair_actual[gvkey_j == "179831", acctcomp := acctcomp + 0.25]
  firmyear_actual[gvkey == "282189", m4_acctcomp := m4_acctcomp - 0.25]

  pair_ref_path <- tempfile(fileext = ".csv")
  firmyear_ref_path <- tempfile(fileext = ".csv")
  pair_path <- tempfile(fileext = ".rds")
  firmyear_path <- tempfile(fileext = ".rds")
  fwrite(pair_reference, pair_ref_path)
  fwrite(firmyear_reference, firmyear_ref_path)
  saveRDS(pair_actual, pair_path)
  saveRDS(firmyear_actual, firmyear_path)

  expect_error(
    validate_against_verdi(
      pair_path = pair_path,
      firm_year_path = firmyear_path,
      reference_pair_path = pair_ref_path,
      reference_firm_year_path = firmyear_ref_path,
      mode = "replication",
      min_pair_correlation = 0.999,
      min_pair_near_exact_rate = 1,
      min_firm_year_correlation = 0.999,
      min_firm_year_near_exact_rate = 1
    ),
    "Validation failed"
  )
})

test_that("replication mode fails when either required reference path is missing", {
  cleanup_author_fixture_reports()
  on.exit(cleanup_author_fixture_reports(), add = TRUE)

  pair_path <- tempfile(fileext = ".rds")
  firmyear_path <- tempfile(fileext = ".rds")
  saveRDS(data.table(gvkey_i = "001020", datadate_i = as.IDate("1981-12-31"), gvkey_j = "001856", acctcomp = -4.764), pair_path)
  saveRDS(data.table(gvkey = "001020", datadate = as.IDate("1981-12-31"), m4_acctcomp = -0.80), firmyear_path)

  expect_error(
    validate_against_verdi(
      pair_path = pair_path,
      firm_year_path = firmyear_path,
      reference_pair_path = NULL,
      reference_firm_year_path = firmyear_2013_fixture_path,
      mode = "replication"
    ),
    "reference_pair_path"
  )
  expect_error(
    validate_against_verdi(
      pair_path = pair_path,
      firm_year_path = firmyear_path,
      reference_pair_path = pair_2013_fixture_path,
      reference_firm_year_path = NULL,
      mode = "replication"
    ),
    "reference_firm_year_path"
  )
})

test_that("full local 2013 pair-year reference is optionally validated when available", {
  full_pair_path <- file.path(repo_root, "data_raw", "acctcomp_firmpairyear_2013.sas7bdat")
  skip_if_not(file.exists(full_pair_path), "Full 2013 pair-year reference is not present locally; large reference files are not committed.")
  skip_if_not_installed("haven")

  full_pair <- read_table_auto(full_pair_path)
  full_pair[, datadate_i := as_idate(datadate_i, "full_pair_2013.datadate_i")]
  expect_named(full_pair, c("gvkey_i", "datadate_i", "gvkey_j", "acctcomp"))
  expect_equal(nrow(full_pair), 12913571L)
  expect_equal(range(data.table::year(full_pair$datadate_i), na.rm = TRUE), c(1981L, 2013L))

  first_20 <- full_pair[1:20]
  comparison <- compare_reference_metric(
    actual = first_20,
    reference = first_20,
    keys = c("gvkey_i", "datadate_i", "gvkey_j"),
    metric = "acctcomp",
    label = "full_reference_pair_smoke",
    tolerance = 0.001,
    min_correlation = 0.999,
    min_near_exact_rate = 1
  )
  expect_length(comparison$failures, 0L)
  expect_equal(comparison$results[check == "full_reference_pair_smoke_acctcomp_overlap_rows", value], 20)
})
