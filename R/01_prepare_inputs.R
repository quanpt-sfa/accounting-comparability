source(file.path("R", "00_helpers.R"))

prepare_inputs <- function(input_dir = "data_raw", begyear = 1981L, endyear = 2009L) {
  link <- read_named_input("ccmxpf_linktable", input_dir)
  funda <- read_named_input("funda", input_dir)
  fundq <- read_named_input("fundq", input_dir)
  msf <- read_named_input("msf", input_dir)

  require_columns(link, c("gvkey", "lpermno", "linktype", "usedflag", "linkdt", "linkenddt"), "ccmxpf_linktable")
  require_columns(funda, c("gvkey", "datadate", "sich", "indfmt", "datafmt", "popsrc", "consol", "fyr"), "funda")
  require_columns(fundq, c("gvkey", "datadate", "ibq", "conm", "datacqtr"), "fundq")
  require_columns(msf, c("permno", "date", "prc", "shrout", "ret"), "msf")

  setDT(link); setDT(funda); setDT(fundq); setDT(msf)
  link[, `:=`(linkdt = as_idate(linkdt), linkenddt = as_idate(linkenddt), permno = lpermno)]
  funda[, datadate := as_idate(datadate)]
  fundq[, datadate := as_idate(datadate)]
  msf[, date := as_idate(date)]

  link <- link[
    linktype %chin% c("LU", "LC", "LD", "LN", "LO", "LS", "LX") &
      usedflag == 1 & !is.na(permno) & !is.na(gvkey)
  ]
  setorder(link, gvkey, linkdt)

  funda_screen <- funda[
    indfmt == "INDL" & datafmt == "STD" & popsrc == "D" & consol == "C" &
      fyr %in% c(3, 6, 9, 12) &
      data.table::year(datadate) >= begyear - 4L &
      data.table::year(datadate) <= endyear,
    .(gvkey, datadate, sich)
  ]

  temp <- merge(link, funda_screen, by = "gvkey", allow.cartesian = TRUE)
  temp <- temp[(is.na(linkdt) | linkdt <= datadate) & (is.na(linkenddt) | datadate <= linkenddt)]
  temp <- temp[, .(permno, gvkey, datadate, sich)]

  first_sic <- funda[
    indfmt == "INDL" & datafmt == "STD" & popsrc == "D" & consol == "C" & !is.na(sich),
    .(datadate, sich),
    by = gvkey
  ][order(gvkey, datadate)][, .SD[1], by = gvkey][, .(gvkey, sic = sich)]

  temp <- merge(temp, first_sic, by = "gvkey", all.x = TRUE)
  temp[is.na(sich), sich := sic]
  temp[, `:=`(sic = NULL, sic2 = as.integer(sich %/% 100))]
  temp <- temp[!is.na(gvkey) & !is.na(permno) & !is.na(datadate) & !is.na(sic2)]
  temp[, begdate := month_begin_shift(datadate, -11L)]

  fq <- fundq[, .(gvkey, fqenddt = datadate, nibe = ibq, conm, datacqtr)]
  temp <- merge(temp, fq, by = "gvkey", allow.cartesian = TRUE)
  temp <- temp[begdate <= fqenddt & fqenddt <= datadate]
  setorder(temp, gvkey, datadate, fqenddt)

  temp[, holding_co := holding_company_flag(conm)]
  append_diagnostic("step1", "holding_company_rows", temp[holding_co == TRUE, .N])
  temp <- temp[holding_co != TRUE]
  temp[, c("holding_co", "conm", "begdate") := NULL]

  temp[, l2fqenddt := month_end_shift(fqenddt, -3L)]
  msf_mv <- msf[, .(permno, msf_month = data.table::month(date), msf_year = data.table::year(date), prc, shrout)]
  temp[, `:=`(msf_month = data.table::month(l2fqenddt), msf_year = data.table::year(l2fqenddt))]
  temp <- merge(temp, msf_mv, by = c("permno", "msf_month", "msf_year"), all.x = TRUE, allow.cartesian = TRUE)
  temp[!is.na(prc) & shrout > 0, bmve := abs(prc) * shrout / 1000]
  temp[, c("prc", "shrout", "l2fqenddt", "msf_month", "msf_year") := NULL]

  temp[, lfqenddt := month_begin_shift(fqenddt, -2L)]
  ret_rows <- merge(temp, msf[, .(permno, date, ret)], by = "permno", all.x = TRUE, allow.cartesian = TRUE)
  ret_rows <- ret_rows[lfqenddt < date & date <= fqenddt & !is.na(ret)]
  ret_rows[, cont_ret := log(ret + 1)]
  setkey(ret_rows, gvkey, datadate, fqenddt, date)
  ret_rows <- unique(ret_rows, by = key(ret_rows))
  qret <- ret_rows[, .(n = .N, sum_cont_ret = sum(cont_ret)), by = .(gvkey, datadate, fqenddt)]
  append_diagnostic("step1", "quarter_return_month_counts", paste(capture.output(print(qret[, .N, by = n][order(n)])), collapse = " | "))
  qret <- qret[n == 3L, .(gvkey, datadate, fqenddt, bhr = exp(sum_cont_ret) - 1)]

  temp <- unique(temp, by = c("gvkey", "datadate", "fqenddt"))
  temp <- merge(temp, qret, by = c("gvkey", "datadate", "fqenddt"), all.x = TRUE)
  temp[, dnibe := nibe / bmve]
  temp[, c("nibe", "bmve", "lfqenddt") := NULL]
  temp <- temp[!is.na(dnibe) & !is.na(bhr)]
  temp[, year := data.table::year(datadate)]

  trim_sas_rank_005_995(temp, "dnibe", "year")
  trim_sas_rank_005_995(temp, "bhr", "year")
  step1 <- temp[!is.na(dnibe) & !is.na(bhr)]
  setorder(step1, gvkey, datadate, fqenddt)

  append_diagnostic("step1", "firm_quarter_rows", nrow(step1))
  append_diagnostic("step1", "firm_years", uniqueN(step1, by = c("gvkey", "datadate")))
  write_rds(step1, file.path("data_intermediate", "step1_firm_quarter.rds"))
  invisible(step1)
}

if (sys.nframe() == 0L) {
  prepare_inputs()
}
