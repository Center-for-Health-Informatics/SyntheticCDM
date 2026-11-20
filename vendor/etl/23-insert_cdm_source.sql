
insert into dbo.cdm_source (
cdm_source_name,
cdm_source_abbreviation,
cdm_holder,
source_description,
source_documentation_reference,
cdm_etl_reference,
source_release_date,
cdm_release_date,
cdm_version,
vocabulary_version,
cdm_version_concept_id
)
select
'SyntheticCDM: Synthea 3.3.0 synthetic health database',
'SyntheticCDM',
'OHDSI',
'Synthea version: 3.3.0. SyntheaTM is a Synthetic Patient Population Simulator. Generated and loaded by syntheticcdm.',
'https://synthetichealth.github.io/synthea/',
'https://github.com/OHDSI/ETL-Synthea',
getdate(), -- NB: Set this value to the day the source data was pulled
getdate(),
'5.4',
vocabulary_version,
756265
from dbo.vocabulary
where vocabulary_id = 'None';
GO

