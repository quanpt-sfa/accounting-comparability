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

normalize_reference_columns <- function(dt, mapping = NULL) {
  dt <- copy(as.data.table(dt))
  if (is.null(mapping) || !length(mapping)) {
    return(dt)
  }
  if (is.null(names(mapping)) || any(names(mapping) == "")) {
    stop("Reference mapping must be a named character vector: target_name = source_name.", call. = FALSE)
  }
  missing_source <- setdiff(unname(mapping), names(dt))
  if (length(missing_source)) {
    stop(sprintf("Reference file is missing mapped source columns: %s", paste(missing_source, collapse = ", ")), call. = FALSE)
  }
  for (target in names(mapping)) {
    source <- unname(mapping[[target]])
    if (target != source) {
      setnames(dt, source, target)
    }
  }
  dt
}

compare_reference_metric <- function(actual,
                                     reference,
                                     keys,
                                     metric,
                                     label,
                                     tolerance,
                                     min_correlation,
                                     min_near_exact_rate) {
  actual <- copy(as.data.table(actual))
  reference <- copy(as.data.table(reference))
  require_columns(actual, c(keys, metric), paste0(label, "_actual"))
  require_columns(reference, c(keys, metric), paste0(label, "_reference"))
  for (key in keys) {
    if (!inherits(actual[[key]], c("Date", "IDate")) && !inherits(reference[[key]], c("Date", "IDate"))) {
      actual[, (key) := as.character(get(key))]
      reference[, (key) := as.character(get(key))]
    }
  }

  cmp <- merge(
    actual[, c(keys, metric), with = FALSE],
    reference[, c(keys, metric), with = FALSE],
    by = keys,
    suffixes = c("_r", "_sas")
  )

  actual_col <- paste0(metric, "_r")
  ref_col <- paste0(metric, "_sas")
  diff <- cmp[[actual_col]] - cmp[[ref_col]]
  complete <- is.finite(cmp[[actual_col]]) & is.finite(cmp[[ref_col]])
  corr <- if (sum(complete) >= 2L) stats::cor(cmp[[actual_col]][complete], cmp[[ref_col]][complete]) else NA_real_
  mad <- if (any(complete)) mean(abs(diff[complete]), na.rm = TRUE) else NA_real_
  max_abs <- if (any(complete)) max(abs(diff[complete]), na.rm = TRUE) else NA_real_
  near_exact <- if (any(complete)) mean(abs(diff[complete]) <= tolerance, na.rm = TRUE) else NA_real_

  result <- data.table(
    check = c(
      paste0(label, "_", metric, "_overlap_rows"),
      paste0(label, "_", metric, "_correlation"),
      paste0(label, "_", metric, "_mean_absolute_difference"),
      paste0(label, "_", metric, "_max_absolute_difference"),
      paste0(label, "_", metric, "_near_exact_rate")
    ),
    value = c(
      nrow(cmp),
      corr,
      mad,
      max_abs,
      near_exact
    )
  )

  failures <- character()
  if (nrow(cmp) == 0L) {
    failures <- c(failures, sprintf("%s/%s has zero overlapping rows", label, metric))
  }
  if (is.na(corr) || corr < min_correlation) {
    failures <- c(failures, sprintf("%s/%s correlation %.6f is below %.6f", label, metric, corr, min_correlation))
  }
  if (is.na(near_exact) || near_exact < min_near_exact_rate) {
    failures <- c(failures, sprintf("%s/%s near-exact rate %.6f is below %.6f", label, metric, near_exact, min_near_exact_rate))
  }

  list(results = result, failures = failures)
}

validate_against_verdi <- function(pair_path = file.path("data_output", "acctcomp_firmpairyear.rds"),
                                   firm_year_path = file.path("data_output", "acctcomp_firmyear.rds"),
                                   reference_pair_path = NULL,
                                   reference_firm_year_path = NULL,
                                   mode = c("adaptation", "replication"),
                                   reference_pair_map = NULL,
                                   reference_firm_year_map = NULL,
                                   pair_tolerance = 0.001,
                                   firm_year_tolerance = 0.01,
                                   min_pair_correlation = 0.99,
                                   min_pair_near_exact_rate = 0.95,
                                   min_firm_year_correlation = 0.99,
                                   min_firm_year_near_exact_rate = 0.95,
                                   sample_n = 10L) {
  mode <- match.arg(mode)
  if (mode == "replication") {
    if (is.null(reference_pair_path) || !file.exists(reference_pair_path)) {
      stop("Replication mode requires an existing reference_pair_path.", call. = FALSE)
    }
    if (is.null(reference_firm_year_path) || !file.exists(reference_firm_year_path)) {
      stop("Replication mode requires an existing reference_firm_year_path.", call. = FALSE)
    }
  }

  pairs <- as.data.table(readRDS(pair_path))
  firm_year <- as.data.table(readRDS(firm_year_path))
  pairs[, datadate_i := as_idate(datadate_i, "acctcomp_firmpairyear.datadate_i")]
  firm_year[, datadate := as_idate(datadate, "acctcomp_firmyear.datadate")]

  checks <- list(
    data.table(check = "mode", value = mode),
    data.table(check = "firm_pair_year_rows", value = nrow(pairs)),
    data.table(check = "firm_year_rows", value = nrow(firm_year)),
    summarize_distribution(pairs, "acctcomp")[, .(check = paste0("pair_", variable, "_", c("n", "mean", "sd", "p01", "p50", "p99")), value = unlist(.SD)), .SDcols = c("n", "mean", "sd", "p01", "p50", "p99")],
    summarize_distribution(firm_year, "m4_acctcomp")[, .(check = paste0("firm_year_", variable, "_", c("n", "mean", "sd", "p01", "p50", "p99")), value = unlist(.SD)), .SDcols = c("n", "mean", "sd", "p01", "p50", "p99")]
  )
  failures <- character()

  if (!is.null(reference_pair_path) && file.exists(reference_pair_path)) {
    ref_pair <- normalize_reference_columns(read_table_auto(reference_pair_path), reference_pair_map)
    ref_pair[, datadate_i := as_idate(datadate_i, "reference_pair.datadate_i")]
    pair_cmp <- compare_reference_metric(
      actual = pairs,
      reference = ref_pair,
      keys = c("gvkey_i", "datadate_i", "gvkey_j"),
      metric = "acctcomp",
      label = "reference_pair",
      tolerance = pair_tolerance,
      min_correlation = min_pair_correlation,
      min_near_exact_rate = min_pair_near_exact_rate
    )
    checks[[length(checks) + 1L]] <- pair_cmp$results
    failures <- c(failures, pair_cmp$failures)
  }

  if (!is.null(reference_firm_year_path) && file.exists(reference_firm_year_path)) {
    ref_fy <- normalize_reference_columns(read_table_auto(reference_firm_year_path), reference_firm_year_map)
    ref_fy[, datadate := as_idate(datadate, "reference_firm_year.datadate")]
    metrics <- intersect(c("m4_acctcomp", "m10_acctcomp", "ind_acctcomp", "indmd_acctcomp"), names(ref_fy))
    metrics <- intersect(metrics, names(firm_year))
    if (mode == "replication" && !length(metrics)) {
      failures <- c(failures, "Reference firm-year file has no comparable firm-year metrics.")
    }
    for (metric in metrics) {
      fy_cmp <- compare_reference_metric(
        actual = firm_year,
        reference = ref_fy,
        keys = c("gvkey", "datadate"),
        metric = metric,
        label = "reference_firm_year",
        tolerance = firm_year_tolerance,
        min_correlation = min_firm_year_correlation,
        min_near_exact_rate = min_firm_year_near_exact_rate
      )
      checks[[length(checks) + 1L]] <- fy_cmp$results
      failures <- c(failures, fy_cmp$failures)
    }
  }

  set.seed(2011)
  hand_pairs <- if (nrow(pairs)) pairs[sample(.N, min(sample_n, .N))] else pairs
  hand_fy <- if (nrow(firm_year)) firm_year[sample(.N, min(sample_n, .N))] else firm_year
  write_rds(hand_pairs, file.path("reports", "hand_check_firm_pair_year_sample.rds"))
  write_rds(hand_fy, file.path("reports", "hand_check_firm_year_sample.rds"))

  out <- rbindlist(checks, fill = TRUE)
  ensure_dir("reports")
  fwrite(out, file.path("reports", "validation_checks.csv"))
  if (length(failures)) {
    fwrite(data.table(failure = failures), file.path("reports", "validation_failures.csv"))
    stop(sprintf("Validation failed: %s", paste(failures, collapse = "; ")), call. = FALSE)
  }
  invisible(out)
}

if (sys.nframe() == 0L) {
  validate_against_verdi()
}
