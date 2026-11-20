-- Load the Synthea CSV export into the synthea staging tables
-- (vendor/etl/01-create_synthea_tables.sql). Column order matches the CSV
-- headers exactly. Synthea's ISO-8601 timestamps (2010-07-02T07:36:09Z) load
-- directly into the staging tables' date columns.
SET NOCOUNT ON;
PRINT 'synthea: allergies';
BULK INSERT synthea.allergies FROM '$(SYNTHEA_DIR)/allergies.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: careplans';
BULK INSERT synthea.careplans FROM '$(SYNTHEA_DIR)/careplans.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: claims';
BULK INSERT synthea.claims FROM '$(SYNTHEA_DIR)/claims.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: claims_transactions';
BULK INSERT synthea.claims_transactions FROM '$(SYNTHEA_DIR)/claims_transactions.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: conditions';
BULK INSERT synthea.conditions FROM '$(SYNTHEA_DIR)/conditions.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: devices';
BULK INSERT synthea.devices FROM '$(SYNTHEA_DIR)/devices.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: encounters';
BULK INSERT synthea.encounters FROM '$(SYNTHEA_DIR)/encounters.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: imaging_studies';
BULK INSERT synthea.imaging_studies FROM '$(SYNTHEA_DIR)/imaging_studies.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: immunizations';
BULK INSERT synthea.immunizations FROM '$(SYNTHEA_DIR)/immunizations.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: medications';
BULK INSERT synthea.medications FROM '$(SYNTHEA_DIR)/medications.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: observations';
BULK INSERT synthea.observations FROM '$(SYNTHEA_DIR)/observations.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: organizations';
BULK INSERT synthea.organizations FROM '$(SYNTHEA_DIR)/organizations.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: patients';
BULK INSERT synthea.patients FROM '$(SYNTHEA_DIR)/patients.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: payer_transitions';
BULK INSERT synthea.payer_transitions FROM '$(SYNTHEA_DIR)/payer_transitions.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: payers';
BULK INSERT synthea.payers FROM '$(SYNTHEA_DIR)/payers.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: procedures';
BULK INSERT synthea.procedures FROM '$(SYNTHEA_DIR)/procedures.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: providers';
BULK INSERT synthea.providers FROM '$(SYNTHEA_DIR)/providers.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
PRINT 'synthea: supplies';
BULK INSERT synthea.supplies FROM '$(SYNTHEA_DIR)/supplies.csv' WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK, BATCHSIZE = 500000);
GO
