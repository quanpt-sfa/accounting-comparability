# Accounting Comparability Port

This repository ports the De Franco, Kothari, and Verdi (2011) SAS implementation of financial statement comparability into an auditable R pipeline using `data.table`.

The objective is behavioral equivalence with the original SAS implementation. Raw Verdi files are kept under `data_raw/verdi_sas/` and should not be edited.

## Structure

```text
data_raw/verdi_sas/        Raw SAS source, listing, and reference data snapshot
data_intermediate/         Step-level R outputs and diagnostics
data_output/               Final firm-pair-year and firm-year outputs
R/                         Modular R implementation
python/comparability/      Lightweight Python package stubs for future parity tools
tests/                     testthat unit tests
reports/                   SAS logic map, assumptions, validation reports
run.R                      Top-level pipeline runner
```

## Required R Packages

- `data.table`
- `haven` for `.sas7bdat` reference files
- `testthat` for tests

Optional:

- `arrow` for parquet inputs

## Input Schema

The baseline R pipeline expects source extracts equivalent to the SAS inputs:

- `ccmxpf_linktable`: `gvkey`, `lpermno`, `linktype`, `usedflag`, `linkdt`, `linkenddt`
- `funda`: `gvkey`, `datadate`, `sich`, `indfmt`, `datafmt`, `popsrc`, `consol`, `fyr`
- `fundq`: `gvkey`, `datadate`, `ibq`, `conm`, `datacqtr`
- `msf`: `permno`, `date`, `prc`, `shrout`, `ret`

Place files in `data_raw/` as `.rds`, `.csv`, `.parquet`, or `.sas7bdat` using those base names, for example `data_raw/funda.rds`.

Dates should be `Date`, `IDate`, `YYYYMMDD` numeric, `YYYYMMDD` character, or ISO `YYYY-MM-DD` character. Unsupported numeric serial dates are rejected and reported in `reports/date_diagnostics.csv`.

## Running The Pipeline

Adaptation mode runs the DKV logic without requiring Verdi reference outputs:

```powershell
Rscript run.R --mode=adaptation --begyear=1981 --endyear=2009
```

Replication mode requires explicit Verdi reference pair-year and firm-year outputs and fails with non-zero exit status if validation thresholds are not met:

```powershell
Rscript run.R `
  --mode=replication `
  --reference-pair-path=data_raw/verdi_sas/firm_pair_year_dataset.rds `
  --reference-firm-year-path=data_raw/verdi_sas/firm_year_dataset.rds
```

If reference column names differ, pass mappings as `target:source` pairs:

```powershell
Rscript run.R `
  --mode=replication `
  --reference-pair-path=ref_pair.csv `
  --reference-firm-year-path=ref_fy.csv `
  --reference-pair-map=gvkey_i:GVKEY_I,datadate_i:DATE_I,gvkey_j:GVKEY_J,acctcomp:ACCTCOMP `
  --reference-firm-year-map=gvkey:GVKEY,datadate:DATADATE,m4_acctcomp:M4
```

Default validation gates:

- Pair-year correlation at least `0.99`
- Pair-year near-exact rate at least `0.95` within `0.001`
- Firm-year correlation at least `0.99`
- Firm-year near-exact rate at least `0.95` within `0.01`
- Zero overlap against either reference file is a validation failure

These can be adjusted with `--min-pair-correlation`, `--min-pair-near-exact-rate`, `--min-firm-year-correlation`, `--min-firm-year-near-exact-rate`, `--pair-tolerance`, and `--firm-year-tolerance`.

## Expected Outputs

- `data_intermediate/step1_firm_quarter.rds`
- `data_intermediate/step2_accounting_windows.rds`
- `data_intermediate/accounting_coefficients.rds`
- `data_intermediate/firm_pairs.rds`
- `data_output/acctcomp_firmpairyear.rds`
- `data_output/acctcomp_firmyear.rds`
- `reports/date_diagnostics.csv` when invalid or suspicious dates are found
- `reports/excluded_holding_company_rows.csv`
- `reports/window_diagnostics.csv`
- `reports/validation_checks.csv`
- `reports/validation_failures.csv` when replication validation fails

## Replication Mode Vs Adaptation Mode

Replication mode is for checking behavioral equivalence against Verdi reference outputs. It requires both reference datasets and enforces overlap, correlation, difference, and near-exact checks.

Adaptation mode is for applying the DKV measurement contract to a new market or schema. It still uses the same measurement logic and writes diagnostics, but it does not require Verdi reference outputs.

## Known Assumptions

Known assumptions and unresolved ambiguities are tracked in `reports/porting_assumptions.md`.

Important current points:

- The holding-company, group, ADR, and LP exclusion is copied from the original SAS code and is enabled by default. Use `--exclude-holding-companies=false` only for an explicitly documented adaptation.
- The public raw snapshot copied here contains one SAS dataset file, `Verdi_2011_JN_BenefitsFinancial_DATA.sas7bdat`. Inspection shows it is the firm-year reference output. It can validate `acctcomp_firmyear`; direct firm-pair-year validation still requires a separate pair-year reference file.
- SAS date special missing values `.B` and `.E` are represented as open-ended link ranges when they arrive as missing dates in R.
- Percentile and rank trimming are implemented transparently but should be checked against reference outputs in replication mode.

## Vietnam Data Mapping Guidance

For Vietnam or other non-US data, keep the DKV measurement contract fixed and adapt only the input mapping layer:

- Map local firm identifiers to a stable `gvkey` analogue.
- Map fiscal-year-end dates to `datadate`.
- Provide quarterly earnings before extraordinary items as `ibq`, or document the closest reproducible analogue before use.
- Provide beginning-of-quarter market value or enough price/share data to construct it.
- Provide three monthly returns per fiscal quarter whenever possible.
- Replace SIC2 with a documented, stable local industry classification, then keep the same-industry peer rule and minimum 11 firms per industry-year unless the research design explicitly changes.
- Keep adaptation-specific deviations in `reports/porting_assumptions.md`.

## Tests

Run:

```powershell
Rscript tests/testthat.R
```

The tests cover date parsing, rolling-window diagnostics, same-industry pair construction, score sign convention, top-peer aggregation, and replication-mode validation failure for missing references.

The repository also includes `tests/fixtures/verdi_firmyear_reference_sample.csv`, a small CSV fixture extracted from the bundled Verdi firm-year SAS dataset. These tests check the firm-year reference schema, known values, validation overlap, near-exact rates, and reference column mapping without requiring `haven`. If `haven` is installed, an additional test reads the full bundled `.sas7bdat` and checks its row count and year range.

For the 2013 SAS extension, `tests/fixtures/verdi_2013_firmpair_reference_sample.csv` and `tests/fixtures/verdi_2013_firmyear_reference_sample.csv` are sampled from the 2013 pair-year and firm-year reference outputs. They exercise the replication validation gate with both required reference files and explicitly check that the terminal output year is 2013, even though the SAS2013 input macro uses `endyear = 2014`. The full pair-year `.sas7bdat` is intentionally not tracked because it is too large for normal GitHub storage; place it at `data_raw/acctcomp_firmpairyear_2013.sas7bdat` locally when direct full-reference checks are needed.
