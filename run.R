suppressPackageStartupMessages({
  library(data.table)
})

parse_args <- function(args) {
  out <- list()
  for (arg in args) {
    if (!grepl("^--", arg)) next
    kv <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
    key <- kv[[1]]
    value <- if (length(kv) > 1L) paste(kv[-1], collapse = "=") else TRUE
    out[[key]] <- value
  }
  out
}

parse_mapping <- function(x) {
  if (is.null(x) || !nzchar(x)) return(NULL)
  pairs <- strsplit(x, ",", fixed = TRUE)[[1]]
  mapping <- character()
  for (pair in pairs) {
    kv <- strsplit(pair, ":", fixed = TRUE)[[1]]
    if (length(kv) != 2L || !nzchar(kv[[1]]) || !nzchar(kv[[2]])) {
      stop("Mappings must use target:source,target:source syntax.", call. = FALSE)
    }
    mapping[[kv[[1]]]] <- kv[[2]]
  }
  mapping
}

to_integer <- function(x, default) {
  if (is.null(x)) return(default)
  as.integer(x)
}

to_numeric <- function(x, default) {
  if (is.null(x)) return(default)
  as.numeric(x)
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  args <- parse_args(argv)
  mode <- args[["mode"]]
  if (is.null(mode)) mode <- "adaptation"

  source(file.path("R", "01_prepare_inputs.R"))
  source(file.path("R", "02_estimate_accounting_functions.R"))
  source(file.path("R", "03_build_firm_pairs.R"))
  source(file.path("R", "04_compute_comparability.R"))
  source(file.path("R", "05_validate_against_verdi.R"))

  message("Step 1: prepare inputs")
  prepare_inputs(
    input_dir = if (is.null(args[["input-dir"]])) "data_raw" else args[["input-dir"]],
    begyear = to_integer(args[["begyear"]], 1981L),
    endyear = to_integer(args[["endyear"]], 2009L),
    exclude_holding_companies = !identical(tolower(if (is.null(args[["exclude-holding-companies"]])) "true" else args[["exclude-holding-companies"]]), "false")
  )

  message("Step 2: estimate accounting functions")
  estimate_accounting_functions(
    begyear = to_integer(args[["begyear"]], 1981L),
    endyear = to_integer(args[["endyear"]], 2009L)
  )

  message("Step 3: build firm pairs")
  build_firm_pairs()

  message("Step 4: compute comparability")
  compute_pairwise_comparability()
  aggregate_firm_year_comparability()

  message("Step 5: validate")
  validate_against_verdi(
    mode = mode,
    reference_pair_path = args[["reference-pair-path"]],
    reference_firm_year_path = args[["reference-firm-year-path"]],
    reference_pair_map = parse_mapping(args[["reference-pair-map"]]),
    reference_firm_year_map = parse_mapping(args[["reference-firm-year-map"]]),
    pair_tolerance = to_numeric(args[["pair-tolerance"]], 0.001),
    firm_year_tolerance = to_numeric(args[["firm-year-tolerance"]], 0.01),
    min_pair_correlation = to_numeric(args[["min-pair-correlation"]], 0.99),
    min_pair_near_exact_rate = to_numeric(args[["min-pair-near-exact-rate"]], 0.95),
    min_firm_year_correlation = to_numeric(args[["min-firm-year-correlation"]], 0.99),
    min_firm_year_near_exact_rate = to_numeric(args[["min-firm-year-near-exact-rate"]], 0.95)
  )

  message("Pipeline completed successfully.")
}

if (sys.nframe() == 0L) {
  main()
}
