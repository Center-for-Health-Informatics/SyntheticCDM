-- Staging schema for the raw Synthea CSVs; dropped again in 90-cleanup.sql.
IF SCHEMA_ID('synthea') IS NULL EXEC('CREATE SCHEMA synthea');
GO
