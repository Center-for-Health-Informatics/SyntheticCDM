-- Load the OMOP vocabulary (Athena download) into dbo.
--
-- The files are tab-delimited, unquoted (some names contain a literal "), with a
-- header row, LF line endings, YYYYMMDD dates, and empty fields for NULL.
-- So: plain BULK INSERT, *not* FORMAT='CSV'.
SET NOCOUNT ON;

PRINT 'vocabulary: small tables';
BULK INSERT dbo.vocabulary     FROM '$(VOCAB_DIR)/VOCABULARY.csv'     WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK);
BULK INSERT dbo.domain         FROM '$(VOCAB_DIR)/DOMAIN.csv'         WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK);
BULK INSERT dbo.concept_class  FROM '$(VOCAB_DIR)/CONCEPT_CLASS.csv'  WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK);
BULK INSERT dbo.relationship   FROM '$(VOCAB_DIR)/RELATIONSHIP.csv'   WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK);
BULK INSERT dbo.drug_strength  FROM '$(VOCAB_DIR)/DRUG_STRENGTH.csv'  WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK, BATCHSIZE = 500000);
GO

PRINT 'vocabulary: concept';
BULK INSERT dbo.concept FROM '$(VOCAB_DIR)/CONCEPT.csv' WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK, BATCHSIZE = 500000);
GO

-- CPT4 concepts come separately, with empty names (the UMLS-licensed
-- reconstitution step, cpt4.jar, was never run). concept_name is NOT NULL, so
-- give them a recognisable placeholder.
PRINT 'vocabulary: concept (CPT4)';
CREATE TABLE #concept_cpt4 (
  concept_id int NOT NULL, concept_name varchar(255) NULL, domain_id varchar(20) NOT NULL,
  vocabulary_id varchar(20) NOT NULL, concept_class_id varchar(20) NOT NULL, standard_concept varchar(1) NULL,
  concept_code varchar(50) NOT NULL, valid_start_date date NOT NULL, valid_end_date date NOT NULL, invalid_reason varchar(1) NULL);
BULK INSERT #concept_cpt4 FROM '$(VOCAB_DIR)/CONCEPT_CPT4.csv' WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK);
INSERT INTO dbo.concept WITH (TABLOCK)
SELECT c.concept_id, COALESCE(NULLIF(c.concept_name, ''), 'CPT4 ' + c.concept_code + ' (name unavailable)'),
       c.domain_id, c.vocabulary_id, c.concept_class_id, c.standard_concept, c.concept_code,
       c.valid_start_date, c.valid_end_date, c.invalid_reason
FROM #concept_cpt4 c
WHERE NOT EXISTS (SELECT 1 FROM dbo.concept x WHERE x.concept_id = c.concept_id);
DROP TABLE #concept_cpt4;
GO

PRINT 'vocabulary: concept_relationship';
BULK INSERT dbo.concept_relationship FROM '$(VOCAB_DIR)/CONCEPT_RELATIONSHIP.csv' WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK, BATCHSIZE = 1000000);
GO

PRINT 'vocabulary: concept_ancestor';
BULK INSERT dbo.concept_ancestor FROM '$(VOCAB_DIR)/CONCEPT_ANCESTOR.csv' WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK, BATCHSIZE = 1000000);
GO

-- A few dozen synonyms exceed concept_synonym_name varchar(1000); stage them
-- wide and truncate (an explicit CAST truncates instead of failing).
PRINT 'vocabulary: concept_synonym';
CREATE TABLE #concept_synonym (concept_id int NOT NULL, concept_synonym_name varchar(max) NOT NULL, language_concept_id int NOT NULL);
BULK INSERT #concept_synonym FROM '$(VOCAB_DIR)/CONCEPT_SYNONYM.csv' WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', FIRSTROW = 2, TABLOCK, BATCHSIZE = 1000000);
INSERT INTO dbo.concept_synonym WITH (TABLOCK) (concept_id, concept_synonym_name, language_concept_id)
SELECT concept_id, CAST(concept_synonym_name AS varchar(1000)), language_concept_id FROM #concept_synonym;
DROP TABLE #concept_synonym;
GO

SELECT 'concept' AS [table], COUNT_BIG(*) AS [rows] FROM dbo.concept
UNION ALL SELECT 'concept_relationship', COUNT_BIG(*) FROM dbo.concept_relationship
UNION ALL SELECT 'concept_ancestor', COUNT_BIG(*) FROM dbo.concept_ancestor
UNION ALL SELECT 'concept_synonym', COUNT_BIG(*) FROM dbo.concept_synonym
UNION ALL SELECT 'drug_strength', COUNT_BIG(*) FROM dbo.drug_strength
UNION ALL SELECT 'vocabulary', COUNT_BIG(*) FROM dbo.vocabulary;
GO
