if (!requireNamespace("testthat", quietly = TRUE)) {
  stop("Package 'testthat' is required to run tests.")
}

testthat::test_dir("tests/testthat")
