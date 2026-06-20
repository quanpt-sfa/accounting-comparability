source(file.path("R", "00_helpers.R"))

summarize_distribution <- function(dt, value_col) {
  x <- dt[[value_col]]
  data.table(
    variable = value_col,
    n = sum(!is.na(x)),
    mean = mean(x, na.rm = TRUE),
    sd = stats::sd(x, na.rm = TRUE),
    p01 = as.numeric(stats::quantile(x, 0.01, na.rm = TRUE)),
    p50 = stats::median(x, na.rm = TRUE),
    p99 = as.numeric(stats::quantile(x, 0.99, na.rm = TRUE))
  )
}

validate_against_verdi <- function(pair_path = file.path("data_output", "acctcomp_firmpairyear.rds"),
                                   firm_year_path = file.path("data_output", "acctcomp_firmyear.rds"),
                                   reference_pair_path = NULL,
                                   reference_firm_year_path = NULL,
                                   sample_n = 10L) {
  pairs <- as.data.table(readRDS(pair_path))
  firm_year <- as.data.table(readRDS(firm_year_path))

  checks <- list(
    data.table(check = "firm_pair_year_rows", value = nrow(pairs)),
    data.table(check = "firm_year_rows", value = nrow(firm_year)),
    summarize_distribution(pairs, "acctcomp")[, .(check = paste0("pair_", variable, "_", c("n", "mean", "sd", "p01", "p50", "p99")), value = unlist(.SD)), .SDcols = c("n", "mean", "sd", "p01", "p50", "p99")],
    summarize_distribution(firm_year, "m4_acctcomp")[, .(check = paste0("firm_year_", variable, "_", c("n", "mean", "sd", "p01", "p50", "p99")), value = unlist(.SD)), .SDcols = c("n", "mean", "sd", "p01", "p50", "p99")]
  )

  if (!is.null(reference_pair_path) && file.exists(reference_pair_path)) {
    ref_pair <- as.data.table(read_table_auto(reference_pair_path))
    common_keys <- intersect(c("gvkey_i", "datadate_i", "gvkey_j"), names(ref_pair))
    if (length(common_keys) == 3L && "acctcomp" %in% names(ref_pair)) {
      ref_pair[, datadate_i := as_idate(datadate_i)]
      cmp <- merge(pairs, ref_pair[, c(common_keys, "acctcomp"), with = FALSE], by = common_keys, suffixes = c("_r", "_sas"))
      checks[[length(checks) + 1L]] <- data.table(check = "reference_pair_overlap_rows", value = nrow(cmp))
      checks[[length(checks) + 1L]] <- data.table(check = "reference_pair_acctcomp_correlation", value = stats::cor(cmp$acctcomp_r, cmp$acctcomp_sas, use = "complete.obs"))
      checks[[length(checks) + 1L]] <- data.table(check = "reference_pair_near_exact_001", value = mean(abs(cmp$acctcomp_r - cmp$acctcomp_sas) <= 0.001, na.rm = TRUE))
    }
  }

  if (!is.null(reference_firm_year_path) && file.exists(reference_firm_year_path)) {
    ref_fy <- as.data.table(read_table_auto(reference_firm_year_path))
    common_keys <- intersect(c("gvkey", "datadate"), names(ref_fy))
    overlap_metric <- intersect(c("m4_acctcomp", "m10_acctcomp", "ind_acctcomp", "indmd_acctcomp"), names(ref_fy))
    overlap_metric <- intersect(overlap_metric, names(firm_year))
    if (length(common_keys) == 2L && length(overlap_metric)) {
      ref_fy[, datadate := as_idate(datadate)]
      cmp <- merge(firm_year, ref_fy[, c(common_keys, overlap_metric), with = FALSE], by = common_keys, suffixes = c("_r", "_sas"))
      checks[[length(checks) + 1L]] <- data.table(check = "reference_firm_year_overlap_rows", value = nrow(cmp))
      for (metric in overlap_metric) {
        checks[[length(checks) + 1L]] <- data.table(
          check = paste0("reference_firm_year_", metric, "_correlation"),
          value = stats::cor(cmp[[paste0(metric, "_r")]], cmp[[paste0(metric, "_sas")]], use = "complete.obs")
        )
      }
    }
  }

  set.seed(2011)
  hand_pairs <- pairs[sample(.N, min(sample_n, .N))]
  hand_fy <- firm_year[sample(.N, min(sample_n, .N))]
  write_rds(hand_pairs, file.path("reports", "hand_check_firm_pair_year_sample.rds"))
  write_rds(hand_fy, file.path("reports", "hand_check_firm_year_sample.rds"))

  out <- rbindlist(checks, fill = TRUE)
  ensure_dir("reports")
  fwrite(out, file.path("reports", "validation_checks.csv"))
  invisible(out)
}

if (sys.nframe() == 0L) {
  validate_against_verdi()
}
