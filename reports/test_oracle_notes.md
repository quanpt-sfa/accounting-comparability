# Test Oracle Notes

The author-data fixture tests use sampled rows from Verdi SAS/reference outputs as fixed oracles. They are intended to catch schema, key, date, rounding, and validation-gate regressions without regenerating expected values from the current R implementation.

## Fixture Sources

- `tests/fixtures/verdi_firmyear_reference_sample.csv` is sampled from `data_raw/verdi_sas/Verdi_2011_JN_BenefitsFinancial_DATA.sas7bdat`, the 1981-2009 Verdi firm-year reference output.
- `tests/fixtures/verdi_2013_firmyear_reference_sample.csv` is sampled from `data_raw/Verdi_2011_JN_BenefitsFinancial_DATA_2013.sas7bdat`, the 1981-2013 Verdi firm-year reference output.
- `tests/fixtures/verdi_2013_firmpair_reference_sample.csv` is sampled from the local `data_raw/acctcomp_firmpairyear_2013.sas7bdat`, the 1981-2013 Verdi firm-pair-year reference output. The full pair-year file is intentionally not committed because it is too large for normal GitHub storage.

## Sample-Level Oracle Tests

The fixture tests check required columns, parseable dates, numeric metrics, year ranges, and exact known rows such as `gvkey = 001020, datadate = 1981-12-31`, `gvkey = 282189, datadate = 2013-06-30`, and selected `gvkey_i = 282189` pair rows. These expected values are hard-coded from the fixture CSVs, not computed by the R port.

Validation-gate tests construct small actual outputs by hand from those fixed oracle values. Separate perturbation tests deliberately alter `acctcomp` or firm-year metrics and require validation to fail.

## Full Local Reference Tests

Optional tests use full local `.sas7bdat` references only when the files and `haven` are available. If `data_raw/acctcomp_firmpairyear_2013.sas7bdat` is absent, tests skip with a clear message because large reference datasets are not committed.

## Limits

These tests do not by themselves prove full behavioral equivalence. They validate sampled author/reference rows and the replication validation gate. Full equivalence still requires running the R pipeline from the correct raw CRSP/Compustat extracts and comparing complete pair-year and firm-year outputs against the Verdi references.
