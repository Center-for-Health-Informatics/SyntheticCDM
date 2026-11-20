-- Final tidy-up before the image's data files are captured: fresh statistics,
-- shrink the data and log files, and checkpoint so recovery at first start is
-- instant.
SET NOCOUNT ON;
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'UPDATE STATISTICS ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name) + N';'
FROM sys.tables WHERE is_ms_shipped = 0;
EXEC sp_executesql @sql;
GO
CHECKPOINT;
DBCC SHRINKDATABASE (0, 5) WITH NO_INFOMSGS;
GO
DECLARE @log sysname = (SELECT name FROM sys.database_files WHERE type_desc = 'LOG');
DBCC SHRINKFILE (@log, 64) WITH NO_INFOMSGS;
GO
SELECT CAST(name AS varchar(30)) AS name, CAST(type_desc AS varchar(10)) AS type, size * 8 / 1024 AS size_mb FROM sys.database_files;
GO
