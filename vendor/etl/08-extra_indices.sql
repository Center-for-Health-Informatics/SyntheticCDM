/*
@targetDialect Optional indices to speed up ETL.
*/

CREATE INDEX source_to_standard_vocab_map_sctditvisvitsctir ON dbo.source_to_standard_vocab_map (
	source_code,
	target_domain_id,
 	target_vocabulary_id,
	source_vocabulary_id,
	target_standard_concept,
	target_invalid_reason
);
GO


CREATE INDEX source_to_standard_vocab_map_scsvsd ON dbo.source_to_standard_vocab_map (
	source_code,
	source_vocabulary_id,
	source_domain_id
);
GO


CREATE INDEX source_to_source_vocab_map_scsvisdi ON dbo.source_to_source_vocab_map (
	source_code,
	source_vocabulary_id,
	source_domain_id
);
GO


CREATE INDEX provider_psv ON dbo.provider (
	provider_source_value
);
GO


CREATE INDEX person_psv ON dbo.person (
	person_source_value
);
GO



  CREATE INDEX claims_transactions_cpap ON synthea.claims_transactions (
  	claimid,
  	patientid,
  	appointmentid,
  	providerid
  );
GO


