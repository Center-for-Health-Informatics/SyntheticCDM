-- PAGE-compress every dbo table and index. The vocabulary compresses well, and
-- this roughly halves the data files shipped in the image. Runs after the CDM
-- primary keys and indices (vendor/cdm/primary_keys.sql, indices.sql).
SET NOCOUNT ON;
DECLARE @t sysname, @sql nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
  SELECT t.name FROM sys.tables t WHERE t.schema_id = SCHEMA_ID('dbo') ORDER BY t.name;
OPEN c;
FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
  -- Heap or clustered index first, then the nonclustered indexes.
  SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@t) + N' REBUILD WITH (DATA_COMPRESSION = PAGE);'
    + CASE WHEN EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.' + QUOTENAME(@t)) AND type = 2)
           THEN N'ALTER INDEX ALL ON dbo.' + QUOTENAME(@t) + N' REBUILD WITH (DATA_COMPRESSION = PAGE);' ELSE N'' END;
  EXEC sp_executesql @sql;
  FETCH NEXT FROM c INTO @t;
END
CLOSE c; DEALLOCATE c;
GO
