#!/bin/bash
#
# Container entrypoint. The CDM database is already in /var/opt/mssql (baked in
# at build time); this only sets credentials and starts SQL Server.
#
# Env:
#   MSSQL_SA_PASSWORD  required; sa's password (SQL Server complexity rules apply)
#   CDM_LOGIN, CDM_PASSWORD  optional; a least-privilege login for apps: read
#                      dbo (CDM + vocabulary), create/alter/read/write tables in
#                      the results/temp schemas
#   ACCEPT_EULA        Y (preset; Developer edition)
set -euo pipefail

SQLCMD=/opt/mssql-tools18/bin/sqlcmd
DB=${CDM_DATABASE:-Testing}
READY=/tmp/cdm-ready
rm -f "$READY"

die() { echo "syntheticcdm: $*" >&2; exit 1; }
[[ -n ${MSSQL_SA_PASSWORD:-} ]] || die "set MSSQL_SA_PASSWORD (8+ chars; 3 of upper, lower, digit, symbol)"
if [[ -n ${CDM_LOGIN:-} || -n ${CDM_PASSWORD:-} ]]; then
  [[ -n ${CDM_LOGIN:-} && -n ${CDM_PASSWORD:-} ]] || die "set both CDM_LOGIN and CDM_PASSWORD, or neither"
  [[ $CDM_LOGIN =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "CDM_LOGIN must be a simple identifier"
  [[ $CDM_PASSWORD != *'"'* ]] || die 'CDM_PASSWORD must not contain a double quote (")'
fi

# The baked master database has the build's random sa password, and
# MSSQL_SA_PASSWORD is only honoured on first-time setup, so reset it
# (with SQL Server stopped) on every start.
/opt/mssql/bin/mssql-conf -n set-sa-password >/tmp/set-sa-password.log 2>&1 ||
  { cat /tmp/set-sa-password.log >&2; die "could not set the sa password"; }
rm -f /tmp/set-sa-password.log

/opt/mssql/bin/sqlservr &
pid=$!
trap 'kill -TERM $pid 2>/dev/null; wait $pid' TERM INT

export SQLCMDPASSWORD=$MSSQL_SA_PASSWORD
for _ in $(seq 1 180); do
  kill -0 $pid 2>/dev/null || die "sqlservr exited during startup"
  $SQLCMD -S localhost -U sa -No -d "$DB" -Q "SELECT 1" >/dev/null 2>&1 && break
  sleep 1
done
$SQLCMD -S localhost -U sa -No -d "$DB" -Q "SELECT 1" >/dev/null 2>&1 || die "database $DB did not come online"

if [[ -n ${CDM_LOGIN:-} ]]; then
  # app-login.sql puts the password in an N'...' literal, so double any single
  # quotes; it builds the CREATE/ALTER LOGIN with QUOTENAME server-side.
  $SQLCMD -S localhost -U sa -No -b -d "$DB" -v CDM_LOGIN="$CDM_LOGIN" CDM_PASSWORD="${CDM_PASSWORD//\'/\'\'}" \
    -i /opt/syntheticcdm/app-login.sql >/dev/null ||
    die "could not create login $CDM_LOGIN"
  echo "syntheticcdm: login $CDM_LOGIN ready"
fi
unset SQLCMDPASSWORD

touch "$READY"
echo "syntheticcdm ready: database $DB on port 1433"
wait $pid
