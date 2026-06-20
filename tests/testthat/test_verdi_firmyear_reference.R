library(testthat)
library(data.table)

repo_root <- if (basename(getwd()) == "testthat") normalizePath(file.path("..", "..")) else getwd()
setwd(repo_root)
source(file.path(repo_root, "R", "00_helpers.R"))
source(file.path(repo_root, "R", "05_validate_against_verdi.R"))

verdi_fixture_path <- file.path(repo_root, "tests", "fixtures", "verdi_firmyear_reference_sample.csv")

cleanup_validation_reports <- function() {
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

test_that("Verdi firm-year fixture preserves author reference schema and known values", {
  ref <- fread(verdi_fixture_path, colClasses = c(gvkey = "character"))
  expect_named(ref, c("gvkey", "datadate", "m4_acctcomp", "m10_acctcomp", "n_acctcomp", "ind_acctcomp", "indmd_acctcomp", "year"))
  expect_equal(nrow(ref), 12L)
  expect_equal(ref[gvkey == "001020" & year == 1981L, m4_acctcomp], -0.80)
  expect_equal(ref[gvkey == "001011" & year == 1986L, n_acctcomp], 32)
})

test_that("firm-year validation passes against the Verdi reference fixture", {
  cleanup_validation_reports()
  on.exit(cleanup_validation_reports(), add = TRUE)

  ref <- fread(verdi_fixture_path, colClasses = c(gvkey = "character"))
  ref[, datadate := as_idate(datadate, "fixture.datadate")]

  pair_path <- tempfile(fileext = ".rds")
  firm_year_path <- tempfile(fileext = ".rds")
  pair <- data.table(
    gvkey_i = c("001011", "001011"),
    datadate_i = as.IDate(c("1986-12-31", "1987-12-31")),
    gvkey_j = c("001019", "001020"),
    acctcomp = c(-1.06, -0.94)
  )
  saveRDS(pair, pair_path)
  saveRDS(ref, firm_year_path)

  checks <- validate_against_verdi(
    pair_path = pair_path,
    firm_year_path = firm_year_path,
    reference_firm_year_path = verdi_fixture_path,
    mode = "adaptation",
    min_firm_year_correlation = 0.999,
    min_firm_year_near_exact_rate = 1
  )

  expect_equal(
    checks[check == "reference_firm_year_m4_acctcomp_overlap_rows", as.numeric(value)],
    nrow(ref)
  )
  expect_equal(
    checks[check == "reference_firm_year_m4_acctcomp_near_exact_rate", as.numeric(value)],
    1
  )
})

test_that("firm-year reference column mapping supports author data with renamed columns", {
  cleanup_validation_reports()
  on.exit(cleanup_validation_reports(), add = TRUE)

  ref <- fread(verdi_fixture_path, colClasses = c(gvkey = "character"))
  ref[, datadate := as_idate(datadate, "fixture.datadate")]
  renamed <- copy(ref)
  setnames(
    renamed,
    c("gvkey", "datadate", "m4_acctcomp", "m10_acctcomp", "ind_acctcomp", "indmd_acctcomp"),
    c("GVKEY", "DATADATE", "M4", "M10", "IND_MEAN", "IND_MEDIAN")
  )

  ref_path <- tempfile(fileext = ".csv")
  pair_path <- tempfile(fileext = ".rds")
  firm_year_path <- tempfile(fileext = ".rds")
  fwrite(renamed, ref_path)
  saveRDS(ref, firm_year_path)
  saveRDS(data.table(
    gvkey_i = "001011",
    datadate_i = as.IDate("1986-12-31"),
    gvkey_j = "001019",
    acctcomp = -1.06
  ), pair_path)

  checks <- validate_against_verdi(
    pair_path = pair_path,
    firm_year_path = firm_year_path,
    reference_firm_year_path = ref_path,
    mode = "adaptation",
    reference_firm_year_map = c(
      gvkey = "GVKEY",
      datadate = "DATADATE",
      m4_acctcomp = "M4",
      m10_acctcomp = "M10",
      ind_acctcomp = "IND_MEAN",
      indmd_acctcomp = "IND_MEDIAN"
    ),
    min_firm_year_correlation = 0.999,
    min_firm_year_near_exact_rate = 1
  )

  expect_equal(checks[check == "reference_firm_year_m10_acctcomp_near_exact_rate", as.numeric(value)], 1)
})

test_that("full bundled SAS firm-year reference can be read when haven is available", {
  skip_if_not_installed("haven")
  sas_path <- file.path(repo_root, "data_raw", "verdi_sas", "Verdi_2011_JN_BenefitsFinancial_DATA.sas7bdat")
  skip_if_not(file.exists(sas_path), "Bundled Verdi SAS dataset is not present.")

  ref <- read_table_auto(sas_path)
  expect_named(ref, c("gvkey", "datadate", "m4_acctcomp", "m10_acctcomp", "n_acctcomp", "ind_acctcomp", "indmd_acctcomp", "year"))
  expect_equal(nrow(ref), 74465L)
  expect_equal(range(as.integer(ref$year), na.rm = TRUE), c(1981L, 2009L))
})
