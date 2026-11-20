#!/bin/bash
#
# Build-time loader (Containerfile "load" stage). Starts SQL Server, builds the
# CDM 5.4 database from the vocabulary and the Synthea CSVs, then shuts SQL
# Server down cleanly so /var/opt/mssql can be copied into the final image.
#
# Inputs (under /build): sql/, vendor/, vocab/*.csv, synthea/*.csv
# Env: CDM_DATABASE (default Testing)
set -euo pipefail

B=/build
DB=${CDM_DATABASE:-Testing}
SQLCMD=/opt/mssql-tools18/bin/sqlcmd

# Throwaway sa password: never stored, and replaced at container start by
# entrypoint.sh (mssql-conf set-sa-password).
MSSQL_SA_PASSWORD="Load-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')-aA1"
export MSSQL_SA_PASSWORD SQLCMDPASSWORD=$MSSQL_SA_PASSWORD ACCEPT_EULA=Y

start=$SECONDS
stamp() { printf '[%s +%ds] %s\n' "$(date -u +%H:%M:%S)" $((SECONDS - start)) "$*"; }

stamp "starting SQL Server"
/opt/mssql/bin/sqlservr >/tmp/sqlservr.out 2>&1 &
pid=$!
for _ in $(seq 1 120); do
  kill -0 $pid 2>/dev/null || { cat /tmp/sqlservr.out; echo "load.sh: sqlservr exited" >&2; exit 1; }
  $SQLCMD -S localhost -U sa -No -Q "SELECT 1" >/dev/null 2>&1 && break
  sleep 1
done
$SQLCMD -S localhost -U sa -No -h -1 -Q "SET NOCOUNT ON; SELECT @@VERSION" | head -1

# run DATABASE FILE [sqlcmd args...]
#   -b stop on error, -I QUOTED_IDENTIFIER ON (the ETL quotes identifiers),
#   -x for vendored files (no sqlcmd $(var) substitution).
run() {
  local db=$1 f=$2; shift 2
  stamp "$f"
  $SQLCMD -S localhost -U sa -No -b -I -d "$db" -i "$B/$f" "$@"
}

run master sql/00-database.sql -v CDM_DATABASE="$DB"
run "$DB" vendor/cdm/ddl.sql -x
run "$DB" sql/10-vocab.sql -v VOCAB_DIR="$B/vocab"
run "$DB" sql/20-synthea-schema.sql
for f in "$B"/vendor/etl/[0-9]*.sql; do
  run "$DB" "vendor/etl/${f##*/}" -x
  if [[ ${f##*/} == 01-* ]]; then
    run "$DB" sql/21-synthea-load.sql -v SYNTHEA_DIR="$B/synthea"
  fi
done
run "$DB" sql/60-drop-etl-staging.sql
run "$DB" vendor/cdm/primary_keys.sql -x
run "$DB" vendor/cdm/indices.sql -x
run "$DB" sql/75-compress.sql
run "$DB" sql/80-schemas.sql
run "$DB" vendor/webapi/results-ddl.sql -x
run "$DB" sql/90-finish.sql

stamp "shutting down"
$SQLCMD -S localhost -U sa -No -Q "SHUTDOWN" >/dev/null || true
wait $pid || true

# Don't ship the build's logs.
rm -rf /var/opt/mssql/log/* /tmp/sqlservr.out
stamp "done"
