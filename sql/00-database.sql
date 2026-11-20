-- Create the CDM database. Run in master.
-- UTF-8 collation: BULK INSERT on Linux has no CODEPAGE option, and the
-- vocabulary/Synthea files are UTF-8, so varchar columns must be UTF-8.
IF DB_ID(N'$(CDM_DATABASE)') IS NULL
  CREATE DATABASE [$(CDM_DATABASE)] COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO
ALTER DATABASE [$(CDM_DATABASE)] SET RECOVERY SIMPLE;
GO
