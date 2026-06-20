# Porting Assumptions

This file records behavior that is explicit in SAS but requires a reproducible R choice, plus any unresolved ambiguity.

1. SAS date special missing values `.B` and `.E` in `linkdt` and `linkenddt` are represented as open-ended link ranges in R. Missing `linkdt` is treated as no lower bound; missing `linkenddt` is treated as no upper bound.
2. SAS `PROC RANK GROUPS=1000` is approximated with a deterministic within-year rank group helper. This is intended to match SAS rank groups for ordinary non-tied numeric data. Large tie blocks should be inspected during validation.
3. SAS `PROC UNIVARIATE pctlpts=1 99` percentile calculation can differ subtly from R quantile types. The baseline uses R `quantile(..., type = 5)` because it is commonly closest to SAS percentile behavior for empirical distributions, but this remains validation-sensitive.
4. SAS `round(x, 0.001)` and `round(x, 0.01)` are implemented as `round(x / unit) * unit`. Halfway behavior can differ from R's IEC 60559 rounding in rare exact-half cases.
5. The copied public Verdi raw folder contains one SAS dataset file, `Verdi_2011_JN_BenefitsFinancial_DATA.sas7bdat`. Its filename does not identify whether it is a firm-pair-year, firm-year, or auxiliary dataset. Validation code therefore accepts explicit reference dataset paths and reports what columns overlap.
6. The R input reader does not connect directly to WRDS/CRSP/Compustat. It expects local extracts that preserve the SAS input variables named in `reports/sas_logic_map.md`.
