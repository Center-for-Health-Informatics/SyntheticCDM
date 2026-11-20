-- Empty schemas for the tools this image is used to develop and test:
--   results, temp                 CHI Node WebAPI / chi/testing; Achilles default
--   webapi_results, webapi_temp   OHDSI WebAPI 3 source daimons (Results, Temp)
--   chi_achilles, ohdsi_achilles  Achilles (Node) vs. R Achilles comparison
IF SCHEMA_ID('results')        IS NULL EXEC('CREATE SCHEMA results AUTHORIZATION dbo');
IF SCHEMA_ID('temp')           IS NULL EXEC('CREATE SCHEMA temp AUTHORIZATION dbo');
IF SCHEMA_ID('webapi_results') IS NULL EXEC('CREATE SCHEMA webapi_results AUTHORIZATION dbo');
IF SCHEMA_ID('webapi_temp')    IS NULL EXEC('CREATE SCHEMA webapi_temp AUTHORIZATION dbo');
IF SCHEMA_ID('chi_achilles')   IS NULL EXEC('CREATE SCHEMA chi_achilles AUTHORIZATION dbo');
IF SCHEMA_ID('ohdsi_achilles') IS NULL EXEC('CREATE SCHEMA ohdsi_achilles AUTHORIZATION dbo');
GO
