-- Drop ETL-Synthea's helper tables from dbo and the raw Synthea staging schema,
-- leaving dbo as a plain CDM 5.4 + vocabulary.
SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.source_to_standard_vocab_map, dbo.source_to_source_vocab_map, dbo.states_map,
  dbo.ip_visits, dbo.er_visits, dbo.op_visits, dbo.all_visits, dbo.assign_all_visit_ids, dbo.final_visit_ids;
GO

DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'DROP TABLE synthea.' + QUOTENAME(name) + N';' FROM sys.tables WHERE schema_id = SCHEMA_ID('synthea');
EXEC sp_executesql @sql;
IF SCHEMA_ID('synthea') IS NOT NULL DROP SCHEMA synthea;
GO

SELECT 'person' AS [table], COUNT_BIG(*) AS [rows] FROM dbo.person
UNION ALL SELECT 'observation_period', COUNT_BIG(*) FROM dbo.observation_period
UNION ALL SELECT 'visit_occurrence', COUNT_BIG(*) FROM dbo.visit_occurrence
UNION ALL SELECT 'visit_detail', COUNT_BIG(*) FROM dbo.visit_detail
UNION ALL SELECT 'condition_occurrence', COUNT_BIG(*) FROM dbo.condition_occurrence
UNION ALL SELECT 'drug_exposure', COUNT_BIG(*) FROM dbo.drug_exposure
UNION ALL SELECT 'procedure_occurrence', COUNT_BIG(*) FROM dbo.procedure_occurrence
UNION ALL SELECT 'measurement', COUNT_BIG(*) FROM dbo.measurement
UNION ALL SELECT 'observation', COUNT_BIG(*) FROM dbo.observation
UNION ALL SELECT 'device_exposure', COUNT_BIG(*) FROM dbo.device_exposure
UNION ALL SELECT 'death', COUNT_BIG(*) FROM dbo.death
UNION ALL SELECT 'condition_era', COUNT_BIG(*) FROM dbo.condition_era
UNION ALL SELECT 'drug_era', COUNT_BIG(*) FROM dbo.drug_era
UNION ALL SELECT 'payer_plan_period', COUNT_BIG(*) FROM dbo.payer_plan_period
UNION ALL SELECT 'cost', COUNT_BIG(*) FROM dbo.cost
UNION ALL SELECT 'cdm_source', COUNT_BIG(*) FROM dbo.cdm_source;
GO
