suppressPackageStartupMessages({
  library(data.table)
})

repo_path <- function(...) {
  file.path(getwd(), ...)
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(path)
}

require_columns <- function(dt, cols, data_name = deparse(substitute(dt))) {
  missing_cols <- setdiff(cols, names(dt))
  if (length(missing_cols)) {
    stop(
      sprintf("%s is missing required columns: %s", data_name, paste(missing_cols, collapse = ", ")),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

as_idate <- function(x,
                     field_name = deparse(substitute(x)),
                     diagnostics_path = file.path("reports", "date_diagnostics.csv"),
                     min_date = as.IDate("1900-01-01"),
                     max_date = as.IDate("2100-12-31"),
                     fail_on_invalid = TRUE) {
  ensure_dir(dirname(diagnostics_path))
  original <- x
  parser <- rep(NA_character_, length(x))
  parsed <- rep(as.IDate(NA), length(x))

  if (inherits(x, "IDate")) {
    parsed <- x
    parser[] <- "IDate"
  } else if (inherits(x, "Date")) {
    parsed <- as.IDate(x)
    parser[] <- "Date"
  } else if (is.numeric(x)) {
    is_missing <- is.na(x)
    is_yyyymmdd <- !is_missing & is.finite(x) & x == floor(x) & nchar(sprintf("%.0f", x)) == 8L
    parser[is_missing] <- "missing_numeric"
    parser[is_yyyymmdd] <- "numeric_YYYYMMDD"
    parser[!is_missing & !is_yyyymmdd] <- "unsupported_numeric_serial_or_non_YYYYMMDD"
    parsed[is_yyyymmdd] <- as.IDate(sprintf("%08.0f", x[is_yyyymmdd]), format = "%Y%m%d")
  } else if (is.character(x)) {
    sx <- trimws(x)
    is_missing <- is.na(sx) | sx == ""
    is_yyyymmdd <- !is_missing & grepl("^\\d{8}$", sx)
    is_iso <- !is_missing & grepl("^\\d{4}-\\d{2}-\\d{2}$", sx)
    parser[is_missing] <- "missing_character"
    parser[is_yyyymmdd] <- "character_YYYYMMDD"
    parser[is_iso] <- "character_ISO_YYYY_MM_DD"
    parser[!is_missing & !is_yyyymmdd & !is_iso] <- "unsupported_character_date"
    parsed[is_yyyymmdd] <- as.IDate(sx[is_yyyymmdd], format = "%Y%m%d")
    parsed[is_iso] <- as.IDate(sx[is_iso])
  } else {
    parser[] <- sprintf("unsupported_type_%s", paste(class(x), collapse = "_"))
  }

  invalid <- !is.na(original) & is.na(parsed)
  suspicious <- !is.na(parsed) & (parsed < min_date | parsed > max_date)
  if (any(invalid | suspicious)) {
    diag <- data.table(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      field = field_name,
      row = which(invalid | suspicious),
      original_value = as.character(original[invalid | suspicious]),
      parser = parser[invalid | suspicious],
      parsed_date = as.character(parsed[invalid | suspicious]),
      issue = fifelse(invalid[invalid | suspicious], "invalid_or_unsupported", "outside_plausible_range")
    )
    fwrite(diag, diagnostics_path, append = file.exists(diagnostics_path))
  }
  if (fail_on_invalid && any(invalid | suspicious)) {
    stop(sprintf("Invalid or suspicious dates detected in '%s'; see %s", field_name, diagnostics_path), call. = FALSE)
  }
  parsed
}

month_begin_shift <- function(date, months) {
  d <- as.IDate(date)
  lt <- as.POSIXlt(as.Date(d))
  lt$mday <- 1L
  lt$mon <- lt$mon + months
  as.IDate(as.Date(lt))
}

month_end_shift <- function(date, months) {
  start_next <- month_begin_shift(date, months + 1L)
  as.IDate(as.Date(start_next) - 1L)
}

sas_round <- function(x, unit) {
  round(x / unit) * unit
}

read_table_auto <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "rds") return(readRDS(path))
  if (ext == "csv") return(fread(path, keepLeadingZeros = TRUE))
  if (ext == "parquet") {
    if (!requireNamespace("arrow", quietly = TRUE)) {
      stop("Package 'arrow' is required to read parquet inputs.", call. = FALSE)
    }
    return(as.data.table(arrow::read_parquet(path)))
  }
  if (ext == "sas7bdat") {
    if (!requireNamespace("haven", quietly = TRUE)) {
      stop("Package 'haven' is required to read sas7bdat inputs.", call. = FALSE)
    }
    return(as.data.table(haven::read_sas(path)))
  }
  stop(sprintf("Unsupported input extension for %s", path), call. = FALSE)
}

find_input_file <- function(base_name, input_dir = "data_raw") {
  candidates <- file.path(input_dir, paste0(base_name, c(".rds", ".csv", ".parquet", ".sas7bdat")))
  hit <- candidates[file.exists(candidates)]
  if (!length(hit)) {
    stop(sprintf("No input file found for '%s' in %s", base_name, input_dir), call. = FALSE)
  }
  hit[[1]]
}

read_named_input <- function(base_name, input_dir = "data_raw") {
  as.data.table(read_table_auto(find_input_file(base_name, input_dir)))
}

write_rds <- function(x, path) {
  ensure_dir(dirname(path))
  saveRDS(x, path)
  invisible(path)
}

append_diagnostic <- function(step, metric, value, path = "reports/validation_summary.csv") {
  ensure_dir(dirname(path))
  row <- data.table(
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    step = step,
    metric = metric,
    value = as.character(value)
  )
  fwrite(row, path, append = file.exists(path))
  invisible(row)
}

rank_groups_1000 <- function(x) {
  out <- rep(NA_integer_, length(x))
  ok <- !is.na(x)
  n <- sum(ok)
  if (!n) return(out)
  ranks <- frank(x[ok], ties.method = "average", na.last = "keep")
  out[ok] <- pmin(999L, floor((ranks - 1) * 1000 / n))
  out
}

trim_sas_rank_005_995 <- function(dt, value_col, by_col = "year") {
  value_col <- as.character(value_col)
  by_col <- as.character(by_col)
  dt[, paste0("r_", value_col) := rank_groups_1000(get(value_col)), by = by_col]
  dt[get(paste0("r_", value_col)) <= 4L | get(paste0("r_", value_col)) >= 995L, (value_col) := NA_real_]
  dt[, paste0("r_", value_col) := NULL]
  invisible(dt)
}

delete_outside_percentiles <- function(dt, value_col, by_col = "year", probs = c(0.01, 0.99)) {
  value_col <- as.character(value_col)
  by_col <- as.character(by_col)
  cuts <- dt[!is.na(get(value_col)), as.list(stats::quantile(get(value_col), probs = probs, type = 5, na.rm = TRUE)), by = by_col]
  setnames(cuts, c(by_col, "p01", "p99"))
  dt[cuts, on = by_col, `:=`(p01 = i.p01, p99 = i.p99)]
  dt[!is.na(get(value_col)) & (get(value_col) < p01 | get(value_col) > p99), (value_col) := NA_real_]
  dt[, c("p01", "p99") := NULL]
  invisible(dt)
}

holding_company_flag <- function(conm) {
  firm_name <- toupper(ifelse(is.na(conm), "", conm))
  tokens <- c("HOLDINGS", "HOLDING", "HLDGS", "HLDG", "GROUP", "GRP", "ADR", "-ADR", "-LP")
  Reduce(`|`, lapply(tokens, function(tok) grepl(sprintf("\\b%s\\b", tok), firm_name)))
}

quarter_index <- function(date) {
  d <- as.IDate(date)
  data.table::year(d) * 4L + ((data.table::month(d) - 1L) %/% 3L) + 1L
}

build_window_diagnostics <- function(windows) {
  require_columns(windows, c("gvkey1", "datadate1", "fqenddt", "dnibe", "bhr"), "windows")
  d <- copy(windows)
  d[, valid_obs := !is.na(dnibe) & !is.na(bhr)]
  d_valid <- d[valid_obs == TRUE]
  if (!nrow(d_valid)) {
    return(data.table())
  }
  d_valid[, q_index := quarter_index(fqenddt)]
  d_valid[
    ,
    {
      uq <- sort(unique(q_index))
      gaps <- diff(uq)
      expected_n <- if (length(uq)) max(uq) - min(uq) + 1L else 0L
      .(
        n_valid_obs = .N,
        n_distinct_fqenddt = uniqueN(fqenddt),
        duplicate_fqenddt_rows = .N - uniqueN(fqenddt),
        irregular_quarter_spacing = length(gaps) > 0L && any(gaps != 1L),
        missing_fiscal_quarter_sequence = expected_n > uniqueN(fqenddt),
        expected_quarters_between_min_max = expected_n,
        min_fqenddt = min(fqenddt),
        max_fqenddt = max(fqenddt)
      )
    },
    by = .(gvkey1, datadate1)
  ][
    ,
    window_count_ok := n_valid_obs >= 14L & n_valid_obs <= 16L
  ][]
}

ols_intercept_slope <- function(y, x) {
  ok <- is.finite(y) & is.finite(x)
  n <- sum(ok)
  if (n < 2L) return(list(a_i = NA_real_, b_i = NA_real_))
  vx <- stats::var(x[ok])
  if (is.na(vx) || vx == 0) return(list(a_i = NA_real_, b_i = NA_real_))
  fit <- stats::lm.fit(cbind(Intercept = 1, bhr = x[ok]), y[ok])
  list(a_i = unname(fit$coefficients[[1]]), b_i = unname(fit$coefficients[[2]]))
}
