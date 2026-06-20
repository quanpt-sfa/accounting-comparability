# SAS Logic Map

Source reviewed: `data_raw/verdi_sas/comparability.sas`, copied from `D:\Works\accounting-comparability-SAS\Verdi_2011_JN_BenefitsFinancial_SAS.sas`.

## Required Input Variables

- CRSP/Compustat link history (`crsp.ccmxpf_linktable`): `gvkey`, `lpermno`, `linktype`, `usedflag`, `linkdt`, `linkenddt`.
- Compustat annual fundamentals (`comp.funda`): `gvkey`, `datadate`, `sich`, `indfmt`, `datafmt`, `popsrc`, `consol`, `fyr`.
- Compustat quarterly fundamentals (`comp.fundq`): `gvkey`, `datadate`, `ibq`, `conm`, `datacqtr`.
- CRSP monthly stock file (`crsp.msf`): `permno`, `date`, `prc`, `shrout`, `ret`.

## Sample Filters

- Link table: `linktype` in `LU`, `LC`, `LD`, `LN`, `LO`, `LS`, `LX`; `usedflag = 1`; non-missing `lpermno` and `gvkey`.
- Annual Compustat: fiscal-year end date must fall within link date range; `indfmt = INDL`, `datafmt = STD`, `popsrc = D`, `consol = C`; `fyr` in March, June, September, or December; year range from `begyear - 4` through `endyear`.
- Historical SIC: use `sich`; if missing, fill from the first available non-missing firm SIC in Compustat annual data.
- Exclude missing `gvkey`, `permno`, `datadate`, or `sic2`.
- Quarterly Compustat: retain quarters from the 12-month fiscal-year window ending at annual `datadate`.
- Exclude firms whose upper-case `conm` contains holding-company, group, ADR, or LP tokens used in the SAS program.
- Market value: beginning-of-quarter market value is `abs(prc) * shrout / 1000`, using the CRSP month ending three months before the fiscal quarter end; requires non-missing `prc` and positive `shrout`.
- Returns: quarterly buy-and-hold return uses exactly three monthly CRSP returns during the quarter.
- Earnings and returns: require non-missing `dnibe = ibq / bmve` and `bhr`.
- Annual-year trimming: `dnibe` and `bhr` are set missing by SAS rank groups for the bottom 0.5 percent and top 0.5 percent by annual `year(datadate)`.

## Grouping Logic

- Industry is two-digit historical SIC: `sic2 = int(sich / 100)`.
- The accounting-function estimation year is `year(datadate1)`, where `datadate1` is a firm fiscal-year end.
- Same-industry peer groups are formed by `sic2` and fiscal year.
- Industry-years must contain at least 11 distinct firms, giving each firm at least 10 peers.

## Rolling-Window Estimation Logic

- Candidate estimation dates are firm fiscal-year-end quarters: `datadate = fqenddt`.
- For each candidate firm-year, join the same firm's quarterly observations with `bfqenddt <= fqenddt <= fqenddt1`, where `bfqenddt = intnx("month", fqenddt1, -47, "beginning")`.
- The intended window is the 16 fiscal quarters ending at the fiscal-year-end quarter.
- Retain windows with 14 to 16 non-missing observations.

## Accounting-Function Model

For each firm-year window, SAS estimates:

```text
dnibe = a_i + b_i * bhr + error
```

where:

- `dnibe = quarterly ibq / beginning-of-quarter market value of equity`
- `bhr = quarterly buy-and-hold stock return`
- `a_i` is the firm-year intercept
- `b_i` is the firm-year return-response slope

After estimation, `a_i` and `b_i` are winsor-style deleted, not capped: values below the 1st percentile or above the 99th percentile by year are set missing.

## Firm-Pair Construction

- For each fiscal year, assign a sequential firm id after sorting distinct `gvkey1`.
- For each firm `i`, join all other firms `j` in the same `sic2`.
- Self-pairs are excluded with `gvkey1 ~= gvkey_j`.
- Pair direction is retained, so `i,j` and `j,i` are separate observations.

## Pairwise Comparability Formula

For every historical quarter in firm `i`'s rolling window:

```text
error_q = abs((a_i - a_j) + bhr_iq * (b_i - b_j))
acctcomp_ijy = -1 * mean(error_q) * 100
acctcomp_ijy = round(acctcomp_ijy, 0.001)
```

The pair-year is retained only when the mean is based on 14 to 16 quarterly observations.

## Firm-Year Aggregates

For every `gvkey`, `datadate`:

- Sort peer pair scores by descending `acctcomp`, where values closer to zero are more comparable.
- `m4_acctcomp`: mean of the best 4 peer scores, rounded to 0.01.
- `m10_acctcomp`: mean of the best 10 peer scores, rounded to 0.01.
- `n_acctcomp`: number of peer scores.
- `ind_acctcomp`: mean of all same-industry peer scores, rounded to 0.01.
- `indmd_acctcomp`: median of all same-industry peer scores, rounded to 0.01.

## Output Datasets And Key Columns

- SAS yearly pair files: `out.acctcompYYYY`, with `gvkey_i`, `datadate_i`, `gvkey_j`, `acctcomp`.
- SAS combined pair-year file: `out.acctcomp_firmpairyear`, with the same key columns and pair score.
- SAS firm-year file: `out.acctcomp_firmyear`, with `gvkey`, `datadate`, `m4_acctcomp`, `m10_acctcomp`, `n_acctcomp`, `ind_acctcomp`, `indmd_acctcomp`, `year`.
