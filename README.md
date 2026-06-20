# Accounting Comparability Port

This repository ports the De Franco, Kothari, and Verdi (2011) SAS implementation of financial statement comparability into an auditable R pipeline using `data.table`.

The objective is behavioral equivalence with the original SAS implementation, not a compact re-write. Raw Verdi files are kept under `data_raw/verdi_sas/` and should not be edited.

## Structure

```text
data_raw/verdi_sas/        Raw SAS source, listing, and reference data snapshot
data_intermediate/         Step-level R outputs and diagnostics
data_output/               Final firm-pair-year and firm-year outputs
R/                         Modular R implementation
python/comparability/      Lightweight Python package stubs for future parity tools
tests/                     testthat unit tests
reports/                   SAS logic map, assumptions, validation reports
```

## Required R Packages

- `data.table`
- `lubridate`
- `haven` for reading SAS reference datasets
- `testthat` for tests

Optional, depending on your input format:

- `arrow` for parquet inputs

## Input Schema

The baseline R pipeline expects source extracts equivalent to the SAS inputs:

- `ccmxpf_linktable`: `gvkey`, `lpermno`, `linktype`, `usedflag`, `linkdt`, `linkenddt`
- `funda`: `gvkey`, `datadate`, `sich`, `indfmt`, `datafmt`, `popsrc`, `consol`, `fyr`
- `fundq`: `gvkey`, `datadate`, `ibq`, `conm`, `datacqtr`
- `msf`: `permno`, `date`, `prc`, `shrout`, `ret`

Place files in `data_raw/` as `.rds`, `.csv`, or `.parquet` using those base names, for example `data_raw/funda.rds`.

## Run

From the repository root:

```r
source("R/01_prepare_inputs.R")
source("R/02_estimate_accounting_functions.R")
source("R/03_build_firm_pairs.R")
source("R/04_compute_comparability.R")
source("R/05_validate_against_verdi.R")
```

Or run each script with `Rscript` in order.

Expected outputs:

- `data_intermediate/step1_firm_quarter.rds`
- `data_intermediate/step2_accounting_windows.rds`
- `data_intermediate/accounting_coefficients.rds`
- `data_intermediate/firm_pairs.rds`
- `data_output/acctcomp_firmpairyear.rds`
- `data_output/acctcomp_firmyear.rds`
- `reports/validation_summary.csv`

## Known Differences From SAS

Known assumptions and unresolved ambiguities are tracked in `reports/porting_assumptions.md`. The most important current limitation is that the public snapshot copied here contains one SAS dataset file whose exact table identity is not self-describing from the filename alone; validation code therefore accepts explicit reference pair-year or firm-year paths when available.

## Adapting To Non-US Data

For non-US data such as Vietnam, keep the DKV measurement contract fixed and adapt only the input mapping layer:

- Map local firm identifiers to `gvkey`-like stable firm ids.
- Map local fiscal-year-end dates to `datadate`.
- Provide quarterly earnings before extraordinary items or the closest documented analogue as `ibq`.
- Provide beginning-of-quarter market value or enough price/share data to construct it.
- Provide three monthly returns per fiscal quarter where possible.
- Replace SIC2 with a documented, stable local industry classification, then keep the same-industry peer rule and the minimum 11 firms per industry-year rule unless explicitly changing the research design.

Any schema adaptation should be documented before running validation.
