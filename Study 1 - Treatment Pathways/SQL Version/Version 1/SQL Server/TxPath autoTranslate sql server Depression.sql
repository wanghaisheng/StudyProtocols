/*********************************************************************************
# Copyright 2014 Observational Health Data Sciences and Informatics
#
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
********************************************************************************/


/************************                                                                     

script to create treatment patterns among patients with a disease

last revised: 30 November 2014

author:  Patrick Ryan

description:

create cohort of patients with index at first treatment.  
patients must have >365d prior observation and >1095d of follow-up. 
patients must have >1 diagnosis during their observation. 
patients must have >1 treatment every 120d from index through 1095d.

for each patient, we summarize the sequence of treatments (active ingredients, ordered by first date of dispensing)

we then count the number of persons with the same sequence of treatments

the results queries allow you to remove small cell counts before producing the final summary tables as needed


*************************/

  /*cdmSchema:  cdm_schema*/
  /*resultsSchema:  results_schema*/
 /*studyName:  Depression*/
 /*sourceName:  source_name*/
 /*txlist:  21604686, 21500526*/
 /*dxlist: 440383*/
 /*excludedxlist:  444094,432876,435783*/
 /*smallcellcount:  5*/


--create index population (persons with >1 treatment with >365d observation prior and >1095d observation after)

USE results_schema;

--For Oracle: drop temp tables if they already exist
IF OBJECT_ID('#Depression_indexcohort', 'U') IS NOT NULL
	DROP TABLE #Depression_indexcohort;

IF OBJECT_ID('#Depression_e0', 'U') IS NOT NULL
	DROP TABLE #Depression_e0;

IF OBJECT_ID('#Depression_t0', 'U') IS NOT NULL
	DROP TABLE #Depression_t0;

IF OBJECT_ID('#Depression_t1', 'U') IS NOT NULL
	DROP TABLE #Depression_t1;

IF OBJECT_ID('#Depression_t2', 'U') IS NOT NULL
	DROP TABLE #Depression_t2;

IF OBJECT_ID('#Depression_t3', 'U') IS NOT NULL
	DROP TABLE #Depression_t3;

IF OBJECT_ID('#Depression_t4', 'U') IS NOT NULL
	DROP TABLE #Depression_t4;

IF OBJECT_ID('#Depression_t5', 'U') IS NOT NULL
	DROP TABLE #Depression_t5;

IF OBJECT_ID('#Depression_t6', 'U') IS NOT NULL
	DROP TABLE #Depression_t6;

IF OBJECT_ID('#Depression_t7', 'U') IS NOT NULL
	DROP TABLE #Depression_t7;

IF OBJECT_ID('#Depression_t8', 'U') IS NOT NULL
	DROP TABLE #Depression_t8;

IF OBJECT_ID('#Depression_t9', 'U') IS NOT NULL
	DROP TABLE #Depression_t9;

IF OBJECT_ID('#Depression_matchcohort', 'U') IS NOT NULL
	DROP TABLE #Depression_matchcohort;

IF OBJECT_ID('#Depression_drug_seq', 'U') IS NOT NULL
	DROP TABLE #Depression_drug_seq;

IF OBJECT_ID('#Depression_drug_seq_summary', 'U') IS NOT NULL
	DROP TABLE #Depression_drug_seq_summary;

IF OBJECT_ID('Depression_person_count', 'U') IS NOT NULL
	DROP TABLE Depression_person_count;

IF OBJECT_ID('Depression_person_count_year', 'U') IS NOT NULL
	DROP TABLE Depression_person_count_year;

IF OBJECT_ID('Depression_seq_count', 'U') IS NOT NULL
	DROP TABLE Depression_seq_count;	

IF OBJECT_ID('Depression_seq_count_year', 'U') IS NOT NULL
	DROP TABLE Depression_seq_count_year;
	
create table #Depression_IndexCohort
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	COHORT_END_DATE date not null,
	OBSERVATION_PERIOD_START_DATE date not null,
	OBSERVATION_PERIOD_END_DATE date not null
);

INSERT INTO #Depression_IndexCohort (PERSON_ID, INDEX_DATE, COHORT_END_DATE, OBSERVATION_PERIOD_START_DATE, OBSERVATION_PERIOD_END_DATE)
select  person_id, INDEX_DATE,COHORT_END_DATE, observation_period_start_date, observation_period_end_date
FROM 
(
	select ot.PERSON_ID, ot.INDEX_DATE, MIN(e.END_DATE) as COHORT_END_DATE, ot.OBSERVATION_PERIOD_START_DATE, ot.OBSERVATION_PERIOD_END_DATE, ROW_NUMBER() OVER (PARTITION BY ot.PERSON_ID ORDER BY ot.INDEX_DATE) as RowNumber
	from 
	(
		select dt.PERSON_ID, dt.DRUG_EXPOSURE_START_DATE as index_date, op.OBSERVATION_PERIOD_START_DATE, op.OBSERVATION_PERIOD_END_DATE
		from  
		(
			select de.PERSON_ID, de.DRUG_CONCEPT_ID, de.DRUG_EXPOSURE_START_DATE
			FROM 
			(
				select d.PERSON_ID, d.DRUG_CONCEPT_ID, d.DRUG_EXPOSURE_START_DATE,
				COALESCE(d.DRUG_EXPOSURE_END_DATE, DATEADD(dd,d.DAYS_SUPPLY,d.DRUG_EXPOSURE_START_DATE), DATEADD(dd,1,d.DRUG_EXPOSURE_START_DATE)) as DRUG_EXPOSURE_END_DATE,
				ROW_NUMBER() OVER (PARTITION BY d.PERSON_ID ORDER BY DRUG_EXPOSURE_START_DATE) as RowNumber
				FROM cdm_schema.dbo.DRUG_EXPOSURE d
				JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca 
				on d.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
			) de
			JOIN cdm_schema.dbo.PERSON p on p.PERSON_ID = de.PERSON_ID
			WHERE de.RowNumber = 1
		) dt
		JOIN cdm_schema.dbo.observation_period op 
			on op.PERSON_ID = dt.PERSON_ID and (dt.DRUG_EXPOSURE_START_DATE between op.OBSERVATION_PERIOD_START_DATE and op.OBSERVATION_PERIOD_END_DATE)
		WHERE DATEADD(dd,365, op.OBSERVATION_PERIOD_START_DATE) <= dt.DRUG_EXPOSURE_START_DATE AND DATEADD(dd,1095, dt.DRUG_EXPOSURE_START_DATE) <= op.OBSERVATION_PERIOD_END_DATE

	) ot
	join
	(
		select PERSON_ID, DATEADD(dd,-31,EVENT_DATE) as END_DATE -- subtract 30 days to end dates to resove back to the 'true' dates
		FROM
		(
			select PERSON_ID, EVENT_DATE, EVENT_TYPE, START_ORDINAL, 
			ROW_NUMBER() OVER (PARTITION BY PERSON_ID ORDER BY EVENT_DATE, EVENT_TYPE) AS EVENT_ORDINAL,
			MAX(START_ORDINAL) OVER (PARTITION BY PERSON_ID ORDER BY EVENT_DATE, EVENT_TYPE ROWS UNBOUNDED PRECEDING) as STARTS
			from
			(
				Select PERSON_ID, DRUG_EXPOSURE_START_DATE AS EVENT_DATE, 1 as EVENT_TYPE, ROW_NUMBER() OVER (PARTITION BY PERSON_ID ORDER BY DRUG_EXPOSURE_START_DATE) as START_ORDINAL
				from 
			
				(
					select d.PERSON_ID, d.DRUG_CONCEPT_ID, d.DRUG_EXPOSURE_START_DATE,
					COALESCE(d.DRUG_EXPOSURE_END_DATE, DATEADD(dd,d.DAYS_SUPPLY,d.DRUG_EXPOSURE_START_DATE), DATEADD(dd,1,d.DRUG_EXPOSURE_START_DATE)) as DRUG_EXPOSURE_END_DATE,
					ROW_NUMBER() OVER (PARTITION BY d.PERSON_ID ORDER BY DRUG_EXPOSURE_START_DATE) as RowNumber
					FROM cdm_schema.dbo.DRUG_EXPOSURE d
					JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca 
						on d.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
				)
				cteExposureData
				UNION ALL
				select PERSON_ID, DATEADD(dd,31,DRUG_EXPOSURE_END_DATE), 0 as EVENT_TYPE, NULL
				FROM 
				(
					select d.PERSON_ID, d.DRUG_CONCEPT_ID, d.DRUG_EXPOSURE_START_DATE,
					COALESCE(d.DRUG_EXPOSURE_END_DATE, DATEADD(dd,d.DAYS_SUPPLY,d.DRUG_EXPOSURE_START_DATE), DATEADD(dd,1,d.DRUG_EXPOSURE_START_DATE)) as DRUG_EXPOSURE_END_DATE,
					ROW_NUMBER() OVER (PARTITION BY d.PERSON_ID ORDER BY DRUG_EXPOSURE_START_DATE) as RowNumber
					FROM cdm_schema.dbo.DRUG_EXPOSURE d
					JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca 
						on d.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
				) cteExposureData
			) RAWDATA
		) E
		WHERE 2 * E.STARTS - E.EVENT_ORDINAL = 0
	) e on e.PERSON_ID = ot.PERSON_ID and e.END_DATE >= ot.INDEX_DATE
	GROUP BY ot.PERSON_ID, ot.INDEX_DATE, ot.OBSERVATION_PERIOD_START_DATE, ot.OBSERVATION_PERIOD_END_DATE
) r
WHERE r.RowNumber = 1
;




--find persons with no excluding conditions
create table #Depression_E0
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);


INSERT INTO #Depression_E0
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select co.PERSON_ID, co.CONDITION_CONCEPT_ID
	FROM cdm_schema.dbo.condition_occurrence co
	JOIN #Depression_IndexCohort ip on co.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on co.CONDITION_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (444094,432876,435783)
	WHERE (co.CONDITION_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.CONDITION_CONCEPT_ID) <= 0
;




--find persons in indexcohort with no treatments before index
create table #Depression_T0
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);


INSERT INTO #Depression_T0
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and DATEADD(dd,-1,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) <= 0
;

--find persons in indexcohort with diagnosis
create table #Depression_T1
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T1
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN 
(
	select ce.PERSON_ID, ce.CONDITION_CONCEPT_ID
	FROM cdm_schema.dbo.CONDITION_ERA ce
	JOIN #Depression_IndexCohort ip on ce.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on ce.CONDITION_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (440383)
	WHERE (ce.CONDITION_ERA_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		--cteConditionTargetClause	
) ct on ct.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(ct.CONDITION_CONCEPT_ID) >= 1
;

--find persons in indexcohort with >1 treatments in 4mo interval after index
create table #Depression_T2
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T2
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between DATEADD(dd,121,ip.INDEX_DATE) and DATEADD(dd,240,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) >= 1
;

--find persons in indexcohort with >1 treatments in 4mo interval after index
create table #Depression_T3
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T3
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between DATEADD(dd,241,ip.INDEX_DATE) and DATEADD(dd,360,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) >= 1
;

--find persons in indexcohort with >1 treatments in 4mo interval after index
create table #Depression_T4
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T4
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between DATEADD(dd,361,ip.INDEX_DATE) and DATEADD(dd,480,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) >= 1
;

--find persons in indexcohort with >1 treatments in 4mo interval after index
create table #Depression_T5
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T5
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between DATEADD(dd,481,ip.INDEX_DATE) and DATEADD(dd,600,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) >= 1
;

--find persons in indexcohort with >1 treatments in 4mo interval after index
create table #Depression_T6
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T6
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between DATEADD(dd,601,ip.INDEX_DATE) and DATEADD(dd,720,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) >= 1
;


--find persons in indexcohort with >1 treatments in 4mo interval after index
create table #Depression_T7
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T7
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between DATEADD(dd,721,ip.INDEX_DATE) and DATEADD(dd,840,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) >= 1
;

--find persons in indexcohort with >1 treatments in 4mo interval after index
create table #Depression_T8
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T8
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between DATEADD(dd,841,ip.INDEX_DATE) and DATEADD(dd,960,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) >= 1
;

--find persons in indexcohort with >1 treatments in 4mo interval after index
create table #Depression_T9
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	OBSERVATION_END_DATE date not null
);

INSERT INTO #Depression_T9
select ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
from #Depression_IndexCohort ip
LEFT JOIN
(
	select de.PERSON_ID, de.DRUG_CONCEPT_ID
	FROM cdm_schema.dbo.DRUG_EXPOSURE de
	JOIN #Depression_IndexCohort ip on de.PERSON_ID = ip.PERSON_ID
	JOIN cdm_schema.dbo.CONCEPT_ANCESTOR ca on de.DRUG_CONCEPT_ID = ca.DESCENDANT_CONCEPT_ID and ca.ANCESTOR_CONCEPT_ID in (21604686, 21500526)
	WHERE (de.DRUG_EXPOSURE_START_DATE between ip.OBSERVATION_PERIOD_START_DATE and ip.OBSERVATION_PERIOD_END_DATE)
		 AND de.DRUG_EXPOSURE_START_DATE between DATEADD(dd,961,ip.INDEX_DATE) and DATEADD(dd,1080,ip.INDEX_DATE)	
) dt on dt.PERSON_ID = ip.PERSON_ID
GROUP BY  ip.PERSON_ID, ip.INDEX_DATE, ip.COHORT_END_DATE
HAVING COUNT(dt.DRUG_CONCEPT_ID) >= 1
;


--find persons that qualify for final cohort (meeting all inclusion criteria)
create table #Depression_MatchCohort
(
	PERSON_ID bigint not null primary key,
	INDEX_DATE date not null,
	COHORT_END_DATE date not null,
	OBSERVATION_PERIOD_START_DATE date not null,
	OBSERVATION_PERIOD_END_DATE date not null
);


INSERT INTO #Depression_MatchCohort (PERSON_ID, INDEX_DATE, COHORT_END_DATE, OBSERVATION_PERIOD_START_DATE, OBSERVATION_PERIOD_END_DATE)
select c.person_id, c.index_date, c.cohort_end_date, c.observation_period_start_date, c.observation_period_end_date
FROM #Depression_IndexCohort C
INNER JOIN
(
SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID
FROM
(
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_E0
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T0
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T1
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T2
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T3
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T4
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T5
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T6
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T7
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T8
	INTERSECT
	SELECT INDEX_DATE, OBSERVATION_END_DATE, PERSON_ID FROM #Depression_T9
) TopGroup
) I 
ON C.PERSON_ID = I.PERSON_ID
and c.index_date = i.INDEX_DATE
;



--find all drugs that the matching cohort had taken
create table #Depression_drug_seq
(
	person_id bigint,
	index_year int,
	drug_concept_id int,
	concept_name varchar(255),
	drug_seq int
);

insert into #Depression_drug_seq (person_id, index_year, drug_concept_id, concept_name, drug_seq)
select de1.person_id, de1.index_year, de1.drug_concept_id, c1.concept_name, row_number() over (partition by de1.person_id order by de1.drug_start_date, de1.drug_concept_id) as rn1
from
(select de0.person_id, de0.drug_concept_id, year(c1.index_date) as index_year, min(de0.drug_era_start_date) as drug_start_date
from cdm_schema.dbo.drug_era de0
inner join #Depression_MatchCohort c1
on de0.person_id = c1.person_id
where drug_concept_id in (select descendant_concept_id from cdm_schema.dbo.concept_ancestor where ancestor_concept_id in (21604686, 21500526))
group by de0.person_id, de0.drug_concept_id, year(c1.index_date)
) de1
inner join cdm_schema.dbo.concept c1
on de1.drug_concept_id = c1.concept_id
;




--summarize the unique treatment sequences observed
create table #Depression_drug_seq_summary
(
	index_year int,
	d1_concept_id int,
	d2_concept_id int,
	d3_concept_id int,
	d4_concept_id int,
	d5_concept_id int,
	d6_concept_id int,
	d7_concept_id int,
	d8_concept_id int,
	d9_concept_id int,
	d10_concept_id int,
	d11_concept_id int,
	d12_concept_id int,
	d13_concept_id int,
	d14_concept_id int,
	d15_concept_id int,
	d16_concept_id int,
	d17_concept_id int,
	d18_concept_id int,
	d19_concept_id int,
	d20_concept_id int,
	d1_concept_name varchar(255),
	d2_concept_name varchar(255),
	d3_concept_name varchar(255),
	d4_concept_name varchar(255),
	d5_concept_name varchar(255),
	d6_concept_name varchar(255),
	d7_concept_name varchar(255),
	d8_concept_name varchar(255),
	d9_concept_name varchar(255),
	d10_concept_name varchar(255),
	d11_concept_name varchar(255),
	d12_concept_name varchar(255),
	d13_concept_name varchar(255),
	d14_concept_name varchar(255),
	d15_concept_name varchar(255),
	d16_concept_name varchar(255),
	d17_concept_name varchar(255),
	d18_concept_name varchar(255),
	d19_concept_name varchar(255),
	d20_concept_name varchar(255),
	num_persons int
);

insert into #Depression_drug_seq_summary (index_year, d1_concept_id, d2_concept_id, d3_concept_id, d4_concept_id, d5_concept_id, d6_concept_id, d7_concept_id, d8_concept_id, d9_concept_id, d10_concept_id, d11_concept_id, d12_concept_id, d13_concept_id, d14_concept_id, d15_concept_id, d16_concept_id, d17_concept_id, d18_concept_id, d19_concept_id, d20_concept_id, d1_concept_name, d2_concept_name, d3_concept_name, d4_concept_name, d5_concept_name, d6_concept_name, d7_concept_name, d8_concept_name, d9_concept_name, d10_concept_name, d11_concept_name, d12_concept_name, d13_concept_name, d14_concept_name, d15_concept_name, d16_concept_name, d17_concept_name, d18_concept_name, d19_concept_name, d20_concept_name, num_persons)
select d1.index_year,
	d1.drug_concept_id as d1_concept_id,
	d2.drug_concept_id as d2_concept_id,
	d3.drug_concept_id as d3_concept_id,
	d4.drug_concept_id as d4_concept_id,
	d5.drug_concept_id as d5_concept_id,
	d6.drug_concept_id as d6_concept_id,
	d7.drug_concept_id as d7_concept_id,
	d8.drug_concept_id as d8_concept_id,
	d9.drug_concept_id as d9_concept_id,
	d10.drug_concept_id as d10_concept_id,
	d11.drug_concept_id as d11_concept_id,
	d12.drug_concept_id as d12_concept_id,
	d13.drug_concept_id as d13_concept_id,
	d14.drug_concept_id as d14_concept_id,
	d15.drug_concept_id as d15_concept_id,
	d16.drug_concept_id as d16_concept_id,
	d17.drug_concept_id as d17_concept_id,
	d18.drug_concept_id as d18_concept_id,
	d19.drug_concept_id as d19_concept_id,
	d20.drug_concept_id as d20_concept_id,
	d1.concept_name as d1_concept_name,
	 d2.concept_name as d2_concept_name,
	 d3.concept_name as d3_concept_name,
	 d4.concept_name as d4_concept_name,
	 d5.concept_name as d5_concept_name,
	 d6.concept_name as d6_concept_name,
	 d7.concept_name as d7_concept_name,
	 d8.concept_name as d8_concept_name,
	 d9.concept_name as d9_concept_name,
	 d10.concept_name as d10_concept_name,
	 d11.concept_name as d11_concept_name,
	 d12.concept_name as d12_concept_name,
	 d13.concept_name as d13_concept_name,
	 d14.concept_name as d14_concept_name,
	 d15.concept_name as d15_concept_name,
	 d16.concept_name as d16_concept_name,
	 d17.concept_name as d17_concept_name,
	 d18.concept_name as d18_concept_name,
	 d19.concept_name as d19_concept_name,
	 d20.concept_name as d20_concept_name,
	count(distinct d1.person_id) as num_persons
from
(select *
from #Depression_drug_seq
where drug_seq = 1) d1
left join
(select *
from #Depression_drug_seq
where drug_seq = 2) d2
on d1.person_id = d2.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 3) d3
on d1.person_id = d3.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 4) d4
on d1.person_id = d4.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 5) d5
on d1.person_id = d5.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 6) d6
on d1.person_id = d6.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 7) d7
on d1.person_id = d7.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 8) d8
on d1.person_id = d8.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 9) d9
on d1.person_id = d9.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 10) d10
on d1.person_id = d10.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 11) d11
on d1.person_id = d11.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 12) d12
on d1.person_id = d12.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 13) d13
on d1.person_id = d13.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 14) d14
on d1.person_id = d14.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 15) d15
on d1.person_id = d15.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 16) d16
on d1.person_id = d16.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 17) d17
on d1.person_id = d17.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 18) d18
on d1.person_id = d18.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 19) d19
on d1.person_id = d19.person_id
left join
(select *
from #Depression_drug_seq
where drug_seq = 20) d20
on d1.person_id = d20.person_id
group by 
	d1.index_year,
	d1.drug_concept_id,
	d2.drug_concept_id,
	d3.drug_concept_id,
	d4.drug_concept_id,
	d5.drug_concept_id,
	d6.drug_concept_id,
	d7.drug_concept_id,
	d8.drug_concept_id,
	d9.drug_concept_id,
	d10.drug_concept_id,
	d11.drug_concept_id,
	d12.drug_concept_id,
	d13.drug_concept_id,
	d14.drug_concept_id,
	d15.drug_concept_id,
	d16.drug_concept_id,
	d17.drug_concept_id,
	d18.drug_concept_id,
	d19.drug_concept_id,
	d20.drug_concept_id,
	d1.concept_name,
	 d2.concept_name,
	 d3.concept_name,
	 d4.concept_name,
	 d5.concept_name,
	 d6.concept_name,
	 d7.concept_name,
	 d8.concept_name,
	 d9.concept_name,
	 d10.concept_name,
	 d11.concept_name,
	 d12.concept_name,
	 d13.concept_name,
	 d14.concept_name,
	 d15.concept_name,
	 d16.concept_name,
	 d17.concept_name,
	 d18.concept_name,
	 d19.concept_name,
	 d20.concept_name;




/*****

Final tables for export:  

save these results and report back with the central coordinating center

*****/


USE results_schema;

--1.  count total persons with a treatment

IF OBJECT_ID('Depression_source_name_person_count', 'U') IS NOT NULL
	DROP TABLE Depression_source_name_person_count;

create table results_schema.dbo.Depression_source_name_person_count
(
	num_persons int
);


insert into results_schema.dbo.Depression_source_name_person_count (num_persons)
select num_persons
from
(
select sum(num_persons) as num_persons
from #Depression_drug_seq_summary
) t1
where num_persons > 5;

--2.  count total persons with a treatment, by year
IF OBJECT_ID('Depression_source_name_person_count_year', 'U') IS NOT NULL
	DROP TABLE Depression_source_name_person_count_year;

create table results_schema.dbo.Depression_source_name_person_count_year
(
	index_year int,
	num_persons int
);

insert into results_schema.dbo.Depression_source_name_person_count_year (index_year, num_persons)
select index_year, num_persons
from
(
select index_year, sum(num_persons) as num_persons
from #Depression_drug_seq_summary
group by index_year
) t1
where num_persons > 5;

--3.  overall summary (group by year):   edit the where clause if you need to remove cell counts < minimum number (here 1 as example)
IF OBJECT_ID('Depression_source_name_seq_count', 'U') IS NOT NULL
	DROP TABLE Depression_source_name_seq_count;

create table results_schema.dbo.Depression_source_name_seq_count
(
	d1_concept_id int, 
	d2_concept_id int, 
	d3_concept_id int, 
	d4_concept_id int, 
	d5_concept_id int, 
	d6_concept_id int, 
	d7_concept_id int, 
	d8_concept_id int, 
	d9_concept_id int, 
	d10_concept_id int, 
	d11_concept_id int, 
	d12_concept_id int, 
	d13_concept_id int, 
	d14_concept_id int, 
	d15_concept_id int, 
	d16_concept_id int, 
	d17_concept_id int, 
	d18_concept_id int, 
	d19_concept_id int, 
	d20_concept_id int, 
	d1_concept_name varchar(255), 
	d2_concept_name varchar(255), 
	d3_concept_name varchar(255), 
	d4_concept_name varchar(255), 
	d5_concept_name varchar(255), 
	d6_concept_name varchar(255), 
	d7_concept_name varchar(255), 
	d8_concept_name varchar(255), 
	d9_concept_name varchar(255), 
	d10_concept_name varchar(255), 
	d11_concept_name varchar(255), 
	d12_concept_name varchar(255), 
	d13_concept_name varchar(255), 
	d14_concept_name varchar(255), 
	d15_concept_name varchar(255), 
	d16_concept_name varchar(255), 
	d17_concept_name varchar(255), 
	d18_concept_name varchar(255), 
	d19_concept_name varchar(255), 
	d20_concept_name varchar(255),
	num_persons int
);

insert into results_schema.dbo.Depression_source_name_seq_count (d1_concept_id, d2_concept_id, d3_concept_id, d4_concept_id, d5_concept_id, d6_concept_id, d7_concept_id, d8_concept_id, d9_concept_id, d10_concept_id, d11_concept_id, d12_concept_id, d13_concept_id, d14_concept_id, d15_concept_id, d16_concept_id, d17_concept_id, d18_concept_id, d19_concept_id, d20_concept_id, d1_concept_name, d2_concept_name, d3_concept_name, d4_concept_name, d5_concept_name, d6_concept_name, d7_concept_name, d8_concept_name, d9_concept_name, d10_concept_name, d11_concept_name, d12_concept_name, d13_concept_name, d14_concept_name, d15_concept_name, d16_concept_name, d17_concept_name, d18_concept_name, d19_concept_name, d20_concept_name, num_persons)
select *
from
(
select d1_concept_id, d2_concept_id, d3_concept_id, d4_concept_id, d5_concept_id, d6_concept_id, d7_concept_id, d8_concept_id, d9_concept_id, d10_concept_id, d11_concept_id, d12_concept_id, d13_concept_id, d14_concept_id, d15_concept_id, d16_concept_id, d17_concept_id, d18_concept_id, d19_concept_id, d20_concept_id, d1_concept_name, d2_concept_name, d3_concept_name, d4_concept_name, d5_concept_name, d6_concept_name, d7_concept_name, d8_concept_name, d9_concept_name, d10_concept_name, d11_concept_name, d12_concept_name, d13_concept_name, d14_concept_name, d15_concept_name, d16_concept_name, d17_concept_name, d18_concept_name, d19_concept_name, d20_concept_name, 
	sum(num_persons) as num_persons
from #Depression_drug_seq_summary
group by d1_concept_id, d2_concept_id, d3_concept_id, d4_concept_id, d5_concept_id, d6_concept_id, d7_concept_id, d8_concept_id, d9_concept_id, d10_concept_id, d11_concept_id, d12_concept_id, d13_concept_id, d14_concept_id, d15_concept_id, d16_concept_id, d17_concept_id, d18_concept_id, d19_concept_id, d20_concept_id, d1_concept_name, d2_concept_name, d3_concept_name, d4_concept_name, d5_concept_name, d6_concept_name, d7_concept_name, d8_concept_name, d9_concept_name, d10_concept_name, d11_concept_name, d12_concept_name, d13_concept_name, d14_concept_name, d15_concept_name, d16_concept_name, d17_concept_name, d18_concept_name, d19_concept_name, d20_concept_name
) t1
where num_persons > 5;

--4.  summary by year:   edit the where clause if you need to remove cell counts < minimum number
IF OBJECT_ID('Depression_source_name_seq_count_year', 'U') IS NOT NULL
	DROP TABLE Depression_source_name_seq_count_year;


create table results_schema.dbo.Depression_source_name_seq_count_year
(
	index_year int,
	d1_concept_id int, 
	d2_concept_id int, 
	d3_concept_id int, 
	d4_concept_id int, 
	d5_concept_id int, 
	d6_concept_id int, 
	d7_concept_id int, 
	d8_concept_id int, 
	d9_concept_id int, 
	d10_concept_id int, 
	d11_concept_id int, 
	d12_concept_id int, 
	d13_concept_id int, 
	d14_concept_id int, 
	d15_concept_id int, 
	d16_concept_id int, 
	d17_concept_id int, 
	d18_concept_id int, 
	d19_concept_id int, 
	d20_concept_id int, 
	d1_concept_name varchar(255), 
	d2_concept_name varchar(255), 
	d3_concept_name varchar(255), 
	d4_concept_name varchar(255), 
	d5_concept_name varchar(255), 
	d6_concept_name varchar(255), 
	d7_concept_name varchar(255), 
	d8_concept_name varchar(255), 
	d9_concept_name varchar(255), 
	d10_concept_name varchar(255), 
	d11_concept_name varchar(255), 
	d12_concept_name varchar(255), 
	d13_concept_name varchar(255), 
	d14_concept_name varchar(255), 
	d15_concept_name varchar(255), 
	d16_concept_name varchar(255), 
	d17_concept_name varchar(255), 
	d18_concept_name varchar(255), 
	d19_concept_name varchar(255), 
	d20_concept_name varchar(255),
	num_persons int
);

insert into results_schema.dbo.Depression_source_name_seq_count_year (index_year, d1_concept_id, d2_concept_id, d3_concept_id, d4_concept_id, d5_concept_id, d6_concept_id, d7_concept_id, d8_concept_id, d9_concept_id, d10_concept_id, d11_concept_id, d12_concept_id, d13_concept_id, d14_concept_id, d15_concept_id, d16_concept_id, d17_concept_id, d18_concept_id, d19_concept_id, d20_concept_id, d1_concept_name, d2_concept_name, d3_concept_name, d4_concept_name, d5_concept_name, d6_concept_name, d7_concept_name, d8_concept_name, d9_concept_name, d10_concept_name, d11_concept_name, d12_concept_name, d13_concept_name, d14_concept_name, d15_concept_name, d16_concept_name, d17_concept_name, d18_concept_name, d19_concept_name, d20_concept_name, num_persons)
select index_year, d1_concept_id, d2_concept_id, d3_concept_id, d4_concept_id, d5_concept_id, d6_concept_id, d7_concept_id, d8_concept_id, d9_concept_id, d10_concept_id, d11_concept_id, d12_concept_id, d13_concept_id, d14_concept_id, d15_concept_id, d16_concept_id, d17_concept_id, d18_concept_id, d19_concept_id, d20_concept_id, d1_concept_name, d2_concept_name, d3_concept_name, d4_concept_name, d5_concept_name, d6_concept_name, d7_concept_name, d8_concept_name, d9_concept_name, d10_concept_name, d11_concept_name, d12_concept_name, d13_concept_name, d14_concept_name, d15_concept_name, d16_concept_name, d17_concept_name, d18_concept_name, d19_concept_name, d20_concept_name, num_persons
from #Depression_drug_seq_summary
where num_persons > 5;

--For Oracle: cleanup temp tables:
TRUNCATE TABLE #Depression_indexcohort;
DROP TABLE #Depression_indexcohort;
TRUNCATE TABLE #Depression_e0;
DROP TABLE #Depression_e0;
TRUNCATE TABLE #Depression_t0;
DROP TABLE #Depression_t0;
TRUNCATE TABLE #Depression_t1;
DROP TABLE #Depression_t1;
TRUNCATE TABLE #Depression_t2;
DROP TABLE #Depression_t2;
TRUNCATE TABLE #Depression_t3;
DROP TABLE #Depression_t3;
TRUNCATE TABLE #Depression_t4;
DROP TABLE #Depression_t4;
TRUNCATE TABLE #Depression_t5;
DROP TABLE #Depression_t5;
TRUNCATE TABLE #Depression_t6;
DROP TABLE #Depression_t6;
TRUNCATE TABLE #Depression_t7;
DROP TABLE #Depression_t7;
TRUNCATE TABLE #Depression_t8;
DROP TABLE #Depression_t8;
TRUNCATE TABLE #Depression_t9;
DROP TABLE #Depression_t9;
TRUNCATE TABLE #Depression_matchcohort;
DROP TABLE #Depression_matchcohort;
TRUNCATE TABLE #Depression_drug_seq;
DROP TABLE #Depression_drug_seq;
TRUNCATE TABLE #Depression_drug_seq_summary;
DROP TABLE #Depression_drug_seq_summary;
