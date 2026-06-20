library(testthat)
library(data.table)

repo_root <- if (basename(getwd()) == "testthat") normalizePath(file.path("..", "..")) else getwd()
setwd(repo_root)
source(file.path(repo_root, "R", "00_helpers.R"))
source(file.path(repo_root, "R", "05_validate_against_verdi.R"))

pair_2013_fixture_path <- file.path(repo_root, "tests", "fixtures", "verdi_2013_firmpair_reference_sample.csv")
firmyear_2013_fixture_path <- file.path(repo_root, "tests", "fixtures", "verdi_2013_firmyear_reference_sample.csv")

cleanup_pipeline_reference_reports <- function() {
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

test_that("2013 Verdi reference fixtures preserve pair-year and firm-year schemas", {
  pair_ref <- fread(pair_2013_fixture_path, keepLeadingZeros = TRUE)
  firmyear_ref <- fread(firmyear_2013_fixture_path, keepLeadingZeros = TRUE)

  expect_named(pair_ref, c("gvkey_i", "datadate_i", "gvkey_j", "acctcomp"))
  expect_named(firmyear_ref, c("gvkey", "datadate", "m4_acctcomp", "m10_acctcomp", "n_acctcomp", "ind_acctcomp", "indmd_acctcomp", "year"))
  expect_equal(nrow(pair_ref), 40L)
  expect_equal(nrow(firmyear_ref), 24L)
  expect_equal(range(as.integer(substr(pair_ref$datadate_i, 1, 4))), c(1981L, 2013L))
  expect_equal(range(as.integer(firmyear_ref$year)), c(1981L, 2013L))
})

test_that("replication validation passes when pipeline outputs match 2013 Verdi references", {
  cleanup_pipeline_reference_reports()
  on.exit(cleanup_pipeline_reference_reports(), add = TRUE)

  pair_actual <- fread(pair_2013_fixture_path, keepLeadingZeros = TRUE)
  firmyear_actual <- fread(firmyear_2013_fixture_path, keepLeadingZeros = TRUE)
  pair_actual[, datadate_i := as_idate(datadate_i, "fixture_2013_pair.datadate_i")]
  firmyear_actual[, datadate := as_idate(datadate, "fixture_2013_firmyear.datadate")]

  pair_path <- tempfile(fileext = ".rds")
  firmyear_path <- tempfile(fileext = ".rds")
  saveRDS(pair_actual, pair_path)
  saveRDS(firmyear_actual, firmyear_path)

  checks <- validate_against_verdi(
    pair_path = pair_path,
    firm_year_path = firmyear_path,
    reference_pair_path = pair_2013_fixture_path,
    reference_firm_year_path = firmyear_2013_fixture_path,
    mode = "replication",
    min_pair_correlation = 0.999,
    min_pair_near_exact_rate = 1,
    min_firm_year_correlation = 0.999,
    min_firm_year_near_exact_rate = 1
  )

  expect_equal(checks[check == "reference_pair_acctcomp_overlap_rows", as.numeric(value)], nrow(pair_actual))
  expect_equal(checks[check == "reference_pair_acctcomp_near_exact_rate", as.numeric(value)], 1)
  expect_equal(checks[check == "reference_firm_year_m4_acctcomp_overlap_rows", as.numeric(value)], nrow(firmyear_actual))
  expect_equal(checks[check == "reference_firm_year_m4_acctcomp_near_exact_rate", as.numeric(value)], 1)
})

test_that("full bundled SAS2013 references have the expected terminal year when haven is available", {
  skip_if_not_installed("haven")
  pair_path <- file.path(repo_root, "data_raw", "acctcomp_firmpairyear_2013.sas7bdat")
  firmyear_path <- file.path(repo_root, "data_raw", "Verdi_2011_JN_BenefitsFinancial_DATA_2013.sas7bdat")
  skip_if_not(file.exists(pair_path), "Bundled 2013 pair-year reference is not present.")
  skip_if_not(file.exists(firmyear_path), "Bundled 2013 firm-year reference is not present.")

  pair_ref <- read_table_auto(pair_path)
  firmyear_ref <- read_table_auto(firmyear_path)
  pair_ref[, datadate_i := as_idate(datadate_i, "sas2013_pair.datadate_i")]

  expect_named(pair_ref, c("gvkey_i", "datadate_i", "gvkey_j", "acctcomp"))
  expect_named(firmyear_ref, c("gvkey", "datadate", "m4_acctcomp", "m10_acctcomp", "n_acctcomp", "ind_acctcomp", "indmd_acctcomp", "year"))
  expect_equal(nrow(pair_ref), 12913571L)
  expect_equal(nrow(firmyear_ref), 85129L)
  expect_equal(range(data.table::year(pair_ref$datadate_i), na.rm = TRUE), c(1981L, 2013L))
  expect_equal(range(as.integer(firmyear_ref$year), na.rm = TRUE), c(1981L, 2013L))
})
