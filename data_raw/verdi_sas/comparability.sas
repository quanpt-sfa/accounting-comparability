*********************************************************************************************************************************
*																								*
*		JOB:			ACCTCOMP.SAS																	*
*		DATE:			4/19/2011																		*
*		PROJECT:		FINANCIAL STATEMENT COMPARABILITY													*
*		INPUT:			CRSP.CCMXPF_LINKTABLE		(CRSP/COMPUSTAT Merged - Link History w/ Used Flag)				*
*						COMP.FUNDA					(COMPUSTAT Merged Fundamental Annual File)					*
*						COMP.FUNDQ					(COMPUSTAT Merged Fundamental Quarterly File)				*
*						CRSP.MSF					(CRSP Monthly Stock - Securities)						*
*		OUTPUT:			ACCTCOMP_FIRMPAIRYEAR															*
*						ACCTCOMP_FIRMYEAR															*
*		DESCRIPTION:	This job creates the empirical measure of financial statement comparability developed				*
*						in De Franco, Kothari and Verdi (2011, JAR). It contains four steps. In the first step,		*
*						we get data from COMPUSTAT and CRSP. In the second step, we estimate the firm-specific		*
*						accounting system each year. In the third step, we compute the measure of financial			*
*						statement comparability for all firm pairs.	In the last step, we compute the firm-year 	*
*						measure of financial statement comparability.										*
*																								*
*********************************************************************************************************************************;

LIBNAME out '~/acctcomp_website/output';

%let begyear = 1981;	
%let endyear = 2009;
/* You can change the above restriction to get wider date range. */


/*******************************		STEP1: GETTING DATA			************************************************/

/* Link CRSP and COMPUSTAT and perform some screening. */
PROC SORT DATA = crsp.ccmxpf_linktable out=lnk;
	WHERE linktype in ("LU", "LC", "LD", "LN", "LO", "LS", "LX") AND usedflag = 1
	AND NOT MISSING(lpermno) AND NOT MISSING(gvkey);
	BY gvkey linkdt;

PROC SQL;
	CREATE TABLE temp 
	AS SELECT lnk.lpermno AS permno, two.gvkey, two.datadate, two.sich
  	FROM lnk, comp.funda AS two
  	WHERE lnk.gvkey = two.gvkey 
	AND (linkdt <= two.datadate or linkdt = .B) 
	AND (two.datadate <= linkenddt or linkenddt= .E)
/* The above requires the fiscal year end date (datadate) to be within the link date range. */
	AND two.indfmt='INDL' and two.datafmt='STD' and two.popsrc='D' and two.consol='C'
	AND (two.fyr = 3 OR two.fyr = 6 OR two.fyr = 9 OR two.fyr = 12)
/* The above requires the fiscal year end month to be March, June, September or December.*/
	AND (&begyear - 4) <= year(datadate) <= &endyear;
QUIT;

/* Extract first year with historical SIC codes. Used to fill earlier years */

DATA comp; SET comp.funda (keep = gvkey datadate sich indfmt datafmt popsrc consol);
	WHERE indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C';
	drop indfmt datafmt popsrc consol;

data comp; set comp;
if not missing(sich);

proc sort; by gvkey datadate;

proc sort nodupkey; by gvkey;

data sic; set comp;
rename sich = sic;

data sic; set sic;
keep gvkey sic;

proc sort data = sic; by gvkey;
proc sort data = temp; by gvkey;

data temp; merge temp sic; by gvkey;


/* We use historical SIC; if it is missing, we use the first-year SIC extracted above.*/

data temp; set temp;
if sich =. then sich = sic;
drop sic;

data temp; set temp;
	sic2 = int(sich/100);

PROC SORT; BY gvkey datadate;

DATA temp; SET temp;
	IF NOT MISSING (gvkey);
	IF NOT MISSING (permno);
	IF NOT MISSING (datadate);
	IF NOT MISSING (sic2);
	drop sich;

	begdate = intnx('month', datadate, -11, 'beginning'); 
	FORMAT begdate date9.; /* intnx(interval, from, n, 'aligment') */

/* Extract quarterly data from COMPUSTAT. */
PROC SQL;
	CREATE TABLE temp AS SELECT
	temp.*, two.ibq AS nibe, two.conm, two.datadate AS fqenddt, two.datacqtr
	FROM temp LEFT JOIN comp.fundq AS two
	ON temp.gvkey = two.gvkey
	AND temp.begdate <= two.datadate <= temp.datadate;	
QUIT;

PROC SORT; BY gvkey datadate fqenddt;

/* Exclude holding firms, ADRs and limited partnerships. */

data temp; set temp;
firm_name=upcase(conm);
holding_co=0; 
if indexw(firm_name,'HOLDINGS')>0 then holding_co=1;
if indexw(firm_name,'HOLDING')>0 then holding_co=1;
if indexw(firm_name,'HLDGS')>0 then holding_co=1;
if indexw(firm_name,'HLDG')>0 then holding_co=1;
if indexw(firm_name,'GROUP')>0 then holding_co=1;
if indexw(firm_name,'GRP')>0 then holding_co=1;
if indexw(firm_name,'ADR')>0 then holding_co=1;
if indexw(firm_name,'-ADR')>0 then holding_co=1;
if indexw(firm_name,'-LP')>0 then holding_co=1;
run;

proc freq; table holding_co; 

data temp; set temp; if holding_co = 1 then delete; 
/* 92% firm-year retained. */
drop holding_co conm firm_name begdate;

/* Obtain the beginning-of-period market value of equity from CRSP. */

DATA temp; SET temp;
l2fqenddt = intnx('month', fqenddt, -3, 'end'); FORMAT l2fqenddt date9.;

PROC SQL;
	CREATE TABLE temp AS SELECT
	temp.*, msf.prc, msf.shrout
	FROM temp LEFT JOIN crsp.msf
	ON (temp.permno = msf.permno) 
	AND MONTH(temp.l2fqenddt) = MONTH(msf.date)
	AND YEAR(temp.l2fqenddt) = YEAR(msf.date);
QUIT;

DATA temp; SET temp;
	IF prc ~= . AND shrout > 0 THEN bmve = (ABS(prc)*shrout) / 1000; /* shrout is in thousands. So bmve is in millions now. */
	DROP prc shrout l2fqenddt;

/* Obtain the stock return during the quarter. */

DATA temp; SET temp;
	lfqenddt = intnx('month', fqenddt, -2, 'beginning'); FORMAT lfqenddt date9.;

PROC SQL;
	CREATE TABLE temp AS SELECT
	temp.*, msf.ret, msf.date
	FROM temp LEFT JOIN crsp.msf
	ON (temp.permno = msf.permno) 
	AND temp.lfqenddt < msf.date <= temp.fqenddt;
QUIT;

DATA temp; SET temp;
	IF NOT MISSING (ret);
	cont_ret = LOG(ret + 1);
	
PROC SORT NODUPKEY; BY gvkey datadate fqenddt date;

PROC MEANS NOPRINT;
	BY gvkey datadate fqenddt;
	VAR cont_ret;
	OUTPUT OUT = univ N = n SUM = sum_cont_ret;

PROC FREQ; TABLE n; 

DATA univ; SET univ;
	bhr = EXP(sum_cont_ret) - 1;
	if n = 3; /* This requires that each quarter contain three observations of monthly stock returns. */
	/* 98% observations retained. */
	KEEP gvkey datadate fqenddt bhr;

PROC SORT; BY gvkey datadate fqenddt;

PROC SORT NODUPKEY DATA=temp; BY gvkey datadate fqenddt;

DATA temp; MERGE temp (in=a) univ; BY gvkey datadate fqenddt; if a;
	dnibe = nibe / bmve; /* The dependent variable (Earnings) is the ratio of quarterly net income before extraordinary items to
							the beginning-of-period market value of equity.*/
	DROP ret cont_ret nibe bmve lfqenddt date;

	IF NOT MISSING (dnibe);
	IF NOT MISSING (bhr);
	
	year = YEAR(datadate);

/* Truncate dnibe and bhr at the 0.5 percentile and 99.5 percentile. Avoid data errors. */

DATA temp; SET temp;

%macro trim99(varname);

PROC SORT; BY year;

PROC RANK GROUPS = 1000 OUT = temp;
     BY year;
     VAR &varname; 
     RANKS r_&varname;

DATA temp; SET temp; 
IF r_&varname <= 4 THEN &varname= .;
IF r_&varname >= 995 THEN &varname= .;
DROP r_&varname;

%mend trim99;

%trim99(dnibe);
%trim99(bhr);

DATA step1; SET temp;

	IF NOT MISSING (dnibe);
	IF NOT MISSING (bhr);

PROC SORT; BY gvkey datadate fqenddt;

PROC MEANS N MEAN;

PROC PRINT DATA = step1 (OBS=5); /* Firm-quarter observations */



/***********************		STEP2: Estimating Firm-Specific Accounting System			************************/


data temp; set step1;  


/* Retain only quarters that coincide with fiscal year end */
data temp1; set temp; WHERE datadate = fqenddt;
keep gvkey datadate fqenddt datacqtr sic2;

PROC SORT NODUPKEY; BY gvkey datadate fqenddt;

data temp1; set temp1; 								
rename gvkey = gvkey1;
rename datadate = datadate1;
rename fqenddt = fqenddt1;
rename datacqtr = datacqtr1;

/* For each firm-quarter, we estimate the firm-specific accounting system using the 16 previous quarters of data. */
data temp1; set temp1; 								
bfqenddt = intnx('month', fqenddt1, -47, 'beginning'); FORMAT bfqenddt date9.;

PROC SQL;
	CREATE TABLE temp1 AS SELECT
	temp1.*, temp.fqenddt, temp.dnibe, temp.bhr
	FROM temp1, temp
	WHERE temp1.gvkey1 = temp.gvkey
	AND temp1.bfqenddt  <= temp.fqenddt <= temp1.fqenddt1;	
QUIT;

data temp1; set temp1; 
if not missing (dnibe);
if not missing (bhr);
year=year(datadate1);
drop bfqenddt;
											
proc sort; by gvkey1 datadate1 fqenddt1 fqenddt;


PROC UNIVARIATE NOPRINT; by gvkey1 datadate1 fqenddt1;
VAR dnibe;
OUTPUT OUT = univ N=n ; 


data temp1; MERGE temp1 univ; by gvkey1 datadate1 fqenddt1 ;
if 14 <= n <= 16; /* This requires that for each firm-quarter, we have at least 14 previous quarters of data. */
drop n;

data temp1; set temp1; 

proc reg noprint outest = est data = temp1; 
	by gvkey1 datadate1 fqenddt1 ; 
	model dnibe = bhr;

data est; set est;
keep gvkey1 datadate1 fqenddt1 datacqtr1 sic2 Intercept bhr;
rename Intercept = a_i;
rename bhr = b_i;

/* We truncate the a_i b_i at the 1 percentile and 99 percentile. */

DATA est; SET est;
year=year(datadate1);

%macro trim(varname);

proc sort; by year;

PROC UNIVARIATE NOPRINT; by year;
var &varname;
output out=new pctlpts = 1 99 pctlpre=end;

data new; set new; 

data est; merge est new; by year; 

data est; set est;
if (&varname ne '.') and (&varname lt end1) then do;
&varname=.;
end;

if (&varname ne '.') and (&varname gt end99) then do;
&varname=.;
end;

drop end1 end99;
%mend trim;

%trim(a_i);
%trim(b_i);

data est1; set est; 

proc sort; by gvkey1 datadate1 fqenddt1;

data temp1; merge temp1 est1;  by gvkey1 datadate1 fqenddt1; where &begyear <= year(datadate1) <= &endyear;
	if not missing (a_i);
	if not missing (b_i);

/* Requiring Industry-Years with at least 11 firms. So each firm has at least 10 peers. */

data temp1; set temp1;

data one; set temp1;
keep gvkey1 year sic2;

proc sort nodupkey; by gvkey1 year;

proc freq; table sic2*year/list noprint out=freq;

data freq; set freq; 
keep sic2 year count;

proc sort data = freq; by sic2 year;
proc sort data = temp1; by sic2 year;

data temp1; merge temp1 freq; by sic2 year;

data temp1; set temp1;
if count >= 11;

data descriptive; set temp1; /* Descriptive statistics for number of firm-year. */

PROC SORT NODUPKEY; by gvkey1 datadate1 fqenddt1 ;

proc freq; table year; /* Number of firms used in the loop below */
proc means n mean;

data step2; set temp1;

proc print data =step2(obs=20);


/******************************		STEP3: Computing the Comparability Measure for All Firm i-j Pairs	************************/

data temp1; set step2;

proc sort; by year;

%macro loop(year, nfirms); 
/* Loop by firm &i for year &year. This will generate a dataset of firm i-j AcctComp for each year. */

data temp1a; set temp1; if year(datadate1)=&year;
proc sort; by gvkey1;

data nfirms; set temp1a;
keep gvkey1;
proc sort nodupkey; by gvkey1;

data nfirms; set nfirms; id = _N_;

data temp1a; merge temp1a nfirms; by gvkey1;

%do i= 1 %to &nfirms;

data est1; set temp1a;
proc sort nodupkey; by gvkey1;

data est2; set temp1a; if id = &i; 

PROC SQL;
	CREATE TABLE est2 AS SELECT
	est2.*, est1.gvkey1 AS gvkey_j, est1.a_i AS a_j, est1.b_i AS b_j
	FROM est2 LEFT JOIN est1
	ON est2.gvkey1 ~= est1.gvkey1
	AND est2.sic2 = est1.sic2;	
QUIT;

data est2; set est2;
a_dif = a_i - a_j;
b_dif = b_i - b_j;
drop a_i a_j b_i b_j;

proc sort; by gvkey1 datadate1 fqenddt1 datacqtr1 gvkey_j;

data est2; set est2;

proc sort; by gvkey1 datadate1 fqenddt1 datacqtr1 gvkey_j fqenddt;

data est2; set est2;
error = ABS(a_dif + bhr * b_dif);

proc sort; by gvkey1 datadate1 gvkey_j fqenddt;

PROC UNIVARIATE NOPRINT; by gvkey1 datadate1 gvkey_j;
VAR error ;
OUTPUT OUT = univ N=n MEAN = me_error ; 

data univ; set univ; 
acctcomp = -1 * me_error*100;
acctcomp = round(acctcomp, 0.001);

rename gvkey1 = gvkey_i;
rename datadate1 = datadate_i;

if not missing (acctcomp);
if 14 <= n <= 16;

drop me_error n;

PROC APPEND BASE = final data = univ; RUN;

%end ;

data out.acctcomp&year; set final;

proc sort; by gvkey_i datadate_i gvkey_j; 

%mend loop;

%loop(1981, 959); proc datasets library = work; delete final;
%loop(1982, 988); proc datasets library = work; delete final;
%loop(1983, 1018); proc datasets library = work; delete final;
%loop(1984, 1378); proc datasets library = work; delete final;
%loop(1985, 1728); proc datasets library = work; delete final;
%loop(1986, 1884); proc datasets library = work; delete final;
%loop(1987, 2192); proc datasets library = work; delete final;
%loop(1988, 2201); proc datasets library = work; delete final;
%loop(1989, 2246); proc datasets library = work; delete final;

%loop(1990, 2408); proc datasets library = work; delete final;
%loop(1991, 2506); proc datasets library = work; delete final;
%loop(1992, 2545); proc datasets library = work; delete final;
%loop(1993, 2614); proc datasets library = work; delete final;
%loop(1994, 2627); proc datasets library = work; delete final;
%loop(1995, 2784); proc datasets library = work; delete final;
%loop(1996, 2981); proc datasets library = work; delete final;
%loop(1997, 3346); proc datasets library = work; delete final;
%loop(1998, 3299); proc datasets library = work; delete final;
%loop(1999, 3328); proc datasets library = work; delete final;

%loop(2000, 3308); proc datasets library = work; delete final;
%loop(2001, 3360); proc datasets library = work; delete final;
%loop(2002, 3292); proc datasets library = work; delete final;
%loop(2003, 3425); proc datasets library = work; delete final;
%loop(2004, 3421); proc datasets library = work; delete final;
%loop(2005, 3287); proc datasets library = work; delete final;
%loop(2006, 3103); proc datasets library = work; delete final;
%loop(2007, 2967); proc datasets library = work; delete final;
%loop(2008, 2905); proc datasets library = work; delete final;
%loop(2009, 2909); proc datasets library = work; delete final;

/*
                                 Cumulative    Cumulative
year    Frequency     Percent     Frequency      Percent
---------------------------------------------------------
1981         959        1.28           959         1.28  
1982         988        1.32          1947         2.60  
1983        1018        1.36          2965         3.95  
1984        1378        1.84          4343         5.79  
1985        1728        2.30          6071         8.09  
1986        1884        2.51          7955        10.61  
1987        2192        2.92         10147        13.53  
1988        2201        2.93         12348        16.46  
1989        2246        2.99         14594        19.46  
1990        2408        3.21         17002        22.67  
1991        2506        3.34         19508        26.01  
1992        2545        3.39         22053        29.40  
1993        2614        3.48         24667        32.89  
1994        2627        3.50         27294        36.39  
1995        2784        3.71         30078        40.10  
1996        2981        3.97         33059        44.07  
1997        3346        4.46         36405        48.53  
1998        3299        4.40         39704        52.93  
1999        3328        4.44         43032        57.37  
2000        3308        4.41         46340        61.78  
2001        3360        4.48         49700        66.26  
2002        3292        4.39         52992        70.65  
2003        3425        4.57         56417        75.21  
2004        3421        4.56         59838        79.77  
2005        3287        4.38         63125        84.16  
2006        3103        4.14         66228        88.29  
2007        2967        3.96         69195        92.25  
2008        2905        3.87         72100        96.12  
2009        2909        3.88         75009       100.00  
*/

/******************************		STEP4: Computing the Comparability Measure for All Firm-Year	************************/

data acctcomp; set out.acctcomp1981 out.acctcomp1982 out.acctcomp1983 out.acctcomp1984 out.acctcomp1985 out.acctcomp1986 out.acctcomp1987 
out.acctcomp1988 out.acctcomp1989 out.acctcomp1990 out.acctcomp1991 out.acctcomp1992 out.acctcomp1993 out.acctcomp1994 out.acctcomp1995
out.acctcomp1996 out.acctcomp1997 out.acctcomp1998 out.acctcomp1999 out.acctcomp2000 out.acctcomp2001 out.acctcomp2002 out.acctcomp2003
out.acctcomp2004 out.acctcomp2005 out.acctcomp2006 out.acctcomp2007 out.acctcomp2008 out.acctcomp2009;

data out.acctcomp_firmpairyear; set acctcomp;

proc means n mean median;

data acctcomp; set acctcomp;
year = year(datadate_i);

proc freq; table year;

proc print data = acctcomp (obs = 20);

data acctcomp; set out.acctcomp_firmpairyear; 
rename gvkey_i = gvkey;
rename datadate_i = datadate;
if not missing (acctcomp);

data acctcomp; set acctcomp;

proc freq; table gvkey*datadate/list noprint out = id;

data id; set id;
id = _N_;
keep gvkey datadate id;

proc sort data = id; by gvkey datadate;
proc sort data = acctcomp; by gvkey datadate;

data acctcomp; merge acctcomp id; by gvkey datadate;

proc sort; by id descending acctcomp;

data acctcomp; set acctcomp; by id;
retain rank;
if first.id then do;
	rank = 0;
end;
rank = rank + 1;

data acctcompa; set acctcomp; if rank <= 4;
proc sort; by gvkey datadate;

PROC UNIVARIATE NOPRINT; by gvkey datadate ;
VAR acctcomp;
OUTPUT OUT = est1a MEAN = m4_acctcomp;

data acctcompa; set acctcomp; if rank <= 10;
proc sort; by gvkey datadate;

PROC UNIVARIATE NOPRINT; by gvkey datadate ;
VAR acctcomp;
OUTPUT OUT = est1b MEAN = m10_acctcomp;

data acctcompa; set acctcomp; 
proc sort; by gvkey datadate;

PROC UNIVARIATE NOPRINT; by gvkey datadate ;
VAR acctcomp;
OUTPUT OUT = est1c N = n_acctcomp MEAN = ind_acctcomp MEDIAN = indmd_acctcomp;

data acctcomp; merge est1a est1b est1c; by gvkey datadate;
m4_acctcomp = round(m4_acctcomp, 0.01);
m10_acctcomp = round(m10_acctcomp, 0.01);
ind_acctcomp = round(ind_acctcomp, 0.01);
indmd_acctcomp = round(indmd_acctcomp, 0.01);

data out.acctcomp_firmyear; set acctcomp; 
year = year(datadate);

proc sort; by gvkey datadate;

proc means n mean median;

proc freq; table year;

proc print data=out.acctcomp_firmyear(obs=5);

endsas;
