-- Create or update the least-privilege application login (entrypoint.sh, when
-- CDM_LOGIN/CDM_PASSWORD are set). Mirrors WebAPI's chi/deploy 10-schemas.sql:
-- read dbo; create, alter, read and write tables in the results/temp schemas.
SET NOCOUNT ON;
DECLARE @login sysname = N'$(CDM_LOGIN)', @pw nvarchar(128) = N'$(CDM_PASSWORD)', @sql nvarchar(max);

IF SUSER_ID(@login) IS NULL
  SET @sql = N'CREATE LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = ' + QUOTENAME(@pw, '''') + N', CHECK_POLICY = OFF, DEFAULT_DATABASE = ' + QUOTENAME(DB_NAME());
ELSE
  SET @sql = N'ALTER LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = ' + QUOTENAME(@pw, '''');
EXEC sp_executesql @sql;

IF DATABASE_PRINCIPAL_ID(@login) IS NULL
BEGIN
  SET @sql = N'CREATE USER ' + QUOTENAME(@login) + N' FOR LOGIN ' + QUOTENAME(@login) + N' WITH DEFAULT_SCHEMA = dbo';
  EXEC sp_executesql @sql;
END

SET @sql = N'GRANT SELECT ON SCHEMA::dbo TO ' + QUOTENAME(@login) + N'; GRANT CREATE TABLE, CREATE VIEW TO ' + QUOTENAME(@login) + N';';
SELECT @sql += N'GRANT ALTER, SELECT, INSERT, UPDATE, DELETE, REFERENCES, EXECUTE ON SCHEMA::' + QUOTENAME(name) + N' TO ' + QUOTENAME(@login) + N';'
FROM sys.schemas WHERE name IN (N'results', N'temp', N'webapi_results', N'webapi_temp', N'chi_achilles', N'ohdsi_achilles');
EXEC sp_executesql @sql;
