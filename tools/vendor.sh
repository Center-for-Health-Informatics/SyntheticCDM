#!/usr/bin/env bash
#
# Regenerate vendor/ from pinned upstream commits:
#   vendor/cdm/  OHDSI CommonDataModel 5.4 SQL Server DDL (cdmDatabaseSchema=dbo)
#   vendor/etl/  OHDSI ETL-Synthea SQL Server scripts for CDM 5.4 / Synthea 3.3.0
#
# The SqlRender templates are rendered here (tools/sqlrender.py), once, so the
# image build needs neither R nor network access for SQL. patches/*.patch are
# then applied to the rendered output. Run this only when bumping a pin or
# changing a patch, and commit the result.
#
#   tools/vendor.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

CDM_REPO=https://github.com/OHDSI/CommonDataModel.git
CDM_COMMIT=d83d48c2ba1b641879c33958903f630318421cb8   # v1.0.1-60, 2025-11-05
ETL_REPO=https://github.com/OHDSI/ETL-Synthea.git
ETL_COMMIT=9ee6eb1b933c70af7b80711332aa92327af1f7c5   # v2.1.1, 2026-03-23

SYNTHEA_VERSION=3.3.0
CDM_SCHEMA=dbo
SYNTHEA_SCHEMA=synthea

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fetch() { # repo commit dir
  git init -q "$3"
  git -C "$3" fetch -q --depth 1 "$1" "$2"
  git -C "$3" checkout -q FETCH_HEAD
}
fetch "$CDM_REPO" "$CDM_COMMIT" "$TMP/cdm"
fetch "$ETL_REPO" "$ETL_COMMIT" "$TMP/etl"

# --split: one statement per sqlcmd batch, as DatabaseConnector::executeSql runs them.
render() { python3 "$ROOT/tools/sqlrender.py" --split "$@"; }

# --- CommonDataModel ---------------------------------------------------------
rm -rf vendor/cdm && mkdir -p vendor/cdm
D="$TMP/cdm/inst/ddl/5.4/sql_server"
for part in ddl primary_keys indices; do
  render cdmDatabaseSchema=$CDM_SCHEMA < "$D/OMOPCDM_sql_server_5.4_${part}.sql" > "vendor/cdm/${part}.sql"
done
cp "$TMP/cdm/DESCRIPTION" vendor/cdm/DESCRIPTION   # License: Apache License 2.0
printf '%s\n' "repo: $CDM_REPO" "commit: $CDM_COMMIT" "path: inst/ddl/5.4/sql_server" \
  "rendered: cdmDatabaseSchema=$CDM_SCHEMA" > vendor/cdm/UPSTREAM

# --- ETL-Synthea -------------------------------------------------------------
rm -rf vendor/etl && mkdir -p vendor/etl
S="$TMP/etl/inst/sql/sql_server"
P=(cdm_schema=$CDM_SCHEMA synthea_schema=$SYNTHEA_SCHEMA synthea_version=$SYNTHEA_VERSION
   cdmDatabaseSchema=$CDM_SCHEMA syntheaSchema=$SYNTHEA_SCHEMA syntheaVersion=$SYNTHEA_VERSION
   cdm_version=5.4
   "cdm_source_name=SyntheticCDM: Synthea $SYNTHEA_VERSION synthetic health database"
   cdm_source_abbreviation=SyntheticCDM
   cdm_holder=OHDSI
   "source_description=Synthea version: $SYNTHEA_VERSION. SyntheaTM is a Synthetic Patient Population Simulator. Generated and loaded by syntheticcdm.")

# Run order mirrors ETLSyntheaBuilder: CreateSyntheaTables, CreateVocabMapTables,
# CreateVisitRollupTables, CreateExtraIndices, LoadEventTables.
ORDER=(
  synthea_version/v330/create_synthea_tables.sql
  cdm_version/v540/create_source_to_standard_vocab_map.sql
  cdm_version/v540/create_source_to_source_vocab_map.sql
  cdm_version/v540/create_states_map.sql
  cdm_version/v540/AllVisitTable.sql
  cdm_version/v540/AAVITable.sql
  cdm_version/v540/final_visit_ids.sql
  extra_indices.sql
  cdm_version/v540/insert_location.sql
  cdm_version/v540/insert_care_site.sql
  cdm_version/v540/insert_person.sql
  cdm_version/v540/insert_observation_period.sql
  cdm_version/v540/insert_provider.sql
  cdm_version/v540/insert_visit_occurrence.sql
  cdm_version/v540/insert_visit_detail.sql
  cdm_version/v540/insert_condition_occurrence.sql
  cdm_version/v540/insert_observation.sql
  cdm_version/v540/insert_measurement.sql
  cdm_version/v540/insert_procedure_occurrence.sql
  cdm_version/v540/insert_drug_exposure.sql
  cdm_version/v540/insert_condition_era.sql
  cdm_version/v540/insert_drug_era.sql
  cdm_version/v540/insert_cdm_source.sql
  cdm_version/v540/insert_device_exposure.sql
  cdm_version/v540/insert_death.sql
  cdm_version/v540/insert_payer_plan_period.sql
  cdm_version/v540/insert_cost_v300.sql
)
n=0
for f in "${ORDER[@]}"; do
  n=$((n + 1))
  out=$(printf 'vendor/etl/%02d-%s' "$n" "$(basename "$f")")
  render "${P[@]}" < "$S/$f" > "$out"
done
cp "$TMP/etl/DESCRIPTION" vendor/etl/DESCRIPTION   # License: Apache License 2.0
printf '%s\n' "repo: $ETL_REPO" "commit: $ETL_COMMIT" "path: inst/sql/sql_server" \
  "rendered for: CDM 5.4, Synthea $SYNTHEA_VERSION, cdm_schema=$CDM_SCHEMA, synthea_schema=$SYNTHEA_SCHEMA" \
  "patches: patches/etl-*.patch (applied after rendering)" > vendor/etl/UPSTREAM

for p in patches/etl-*.patch; do
  [[ -e $p ]] || continue
  echo "applying $p"
  patch -s -p1 --no-backup-if-mismatch < "$p"
done

echo "vendor/ regenerated: CommonDataModel ${CDM_COMMIT:0:7}, ETL-Synthea ${ETL_COMMIT:0:7}"
