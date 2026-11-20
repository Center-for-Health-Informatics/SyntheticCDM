#!/usr/bin/env bash
#
# Smoke-test a built syntheticcdm image with Apple's `container` tool:
# start it, check the data, the app login, and that a restart with a new sa
# password works. Leaves nothing running.
#
#   ./test.sh                       tests chi-tools.uc.edu/syntheticcdm:latest
#   IMAGE=... ./test.sh
set -euo pipefail

IMAGE=${IMAGE:-chi-tools.uc.edu/syntheticcdm:latest}
NAME=syntheticcdm-test-$$
DB=${CDM_DATABASE:-Testing}
pw() { echo "T$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')-aA1"; }
SA1=$(pw); SA2=$(pw); APP=$(pw)
ROSETTA=(); [[ $(uname -m) == arm64 ]] && ROSETTA=(--rosetta)

fail=0
check() { # description expected actual
  if [[ "$2" == "$3" ]]; then echo "  ok   $1 ($3)"; else echo "  FAIL $1: expected $2, got $3"; fail=1; fi
}
cleanup() { container rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

start() { # sa-password
  cleanup
  container run -d --name "$NAME" --platform linux/amd64 "${ROSETTA[@]}" -m 4g -c 4 \
    -e MSSQL_SA_PASSWORD="$1" -e CDM_LOGIN=ohdsi -e CDM_PASSWORD="$APP" "$IMAGE" >/dev/null
  local t0=$SECONDS
  until container logs "$NAME" 2>/dev/null | grep -q 'syntheticcdm ready'; do
    container ls -q | grep -qx "$NAME" || { container logs "$NAME"; echo "container exited" >&2; exit 1; }
    (( SECONDS - t0 < 180 )) || { container logs "$NAME"; echo "not ready after 180s" >&2; exit 1; }
    sleep 1
  done
  echo "ready in $((SECONDS - t0))s"
}
q() { # user password sql  -> first column of first row
  container exec -e SQLCMDPASSWORD="$2" "$NAME" /opt/mssql-tools18/bin/sqlcmd -S localhost -U "$1" -No -d "$DB" \
    -h -1 -W -b -Q "SET NOCOUNT ON; $3" 2>&1 | head -1
}

echo "== start ($IMAGE)"
start "$SA1"
check "sa login"                   1        "$(q sa "$SA1" 'SELECT 1')"
check "concepts"                   3614099  "$(q sa "$SA1" 'SELECT COUNT(*) FROM dbo.concept')"
check "persons > 1000"             1        "$(q sa "$SA1" 'SELECT CASE WHEN COUNT(*) > 1000 THEN 1 ELSE 0 END FROM dbo.person')"
check "every person has an observation_period" 0 \
  "$(q sa "$SA1" 'SELECT COUNT(*) FROM dbo.person p WHERE NOT EXISTS (SELECT 1 FROM dbo.observation_period o WHERE o.person_id = p.person_id)')"
check "visits"                     1        "$(q sa "$SA1" 'SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END FROM dbo.visit_occurrence')"
check "conditions"                 1        "$(q sa "$SA1" 'SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END FROM dbo.condition_occurrence')"
check "drug exposures"             1        "$(q sa "$SA1" 'SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END FROM dbo.drug_exposure')"
check "cdm_source rows"            1        "$(q sa "$SA1" 'SELECT COUNT(*) FROM dbo.cdm_source')"
check "no events after 2025-01-01" 0        "$(q sa "$SA1" "SELECT COUNT(*) FROM dbo.visit_occurrence WHERE visit_start_date > '2025-01-01'")"
check "schemas"                    6        "$(q sa "$SA1" "SELECT COUNT(*) FROM sys.schemas WHERE name IN ('results','temp','webapi_results','webapi_temp','chi_achilles','ohdsi_achilles')")"
check "no synthea staging schema"  0        "$(q sa "$SA1" "SELECT COUNT(*) FROM sys.schemas WHERE name = 'synthea'")"
check "concept_hierarchy filled"   1        "$(q sa "$SA1" 'SELECT CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END FROM webapi_results.concept_hierarchy')"
check "app login reads dbo"        1213     "$(q ohdsi "$APP" 'SELECT COUNT(*) FROM dbo.person')"
check "app login writes results"   1        "$(q ohdsi "$APP" 'CREATE TABLE results.t (i int); INSERT results.t VALUES (1); SELECT COUNT(*) FROM results.t; DROP TABLE results.t')"
q ohdsi "$APP" 'CREATE TABLE dbo.t_denied (i int)' >/dev/null || true
check "app login cannot write dbo" 0        "$(q sa "$SA1" "SELECT COUNT(*) FROM sys.tables WHERE name = 't_denied'")"

echo "== stop and start the same container (entrypoint re-runs; data persists)"
q sa "$SA1" 'CREATE TABLE results.persist (i int); INSERT results.persist VALUES (42)' >/dev/null
container stop "$NAME" >/dev/null
container start "$NAME" >/dev/null
t0=$SECONDS
# (container logs restart with the container, so poll the server instead.)
until [[ $(q sa "$SA1" 'SELECT 1') == 1 ]] && container exec "$NAME" test -e /tmp/cdm-ready 2>/dev/null; do
  (( SECONDS - t0 < 180 )) || { container logs "$NAME"; echo "not ready after restart" >&2; exit 1; }
  sleep 1
done
check "sa login after restart"     1        "$(q sa "$SA1" 'SELECT 1')"
check "app login after restart"    1213     "$(q ohdsi "$APP" 'SELECT COUNT(*) FROM dbo.person')"
check "data persisted"             42       "$(q sa "$SA1" 'SELECT i FROM results.persist')"

echo "== fresh container, different sa password"
start "$SA2"
check "sa password from env"       1        "$(q sa "$SA2" 'SELECT 1')"
check "previous password rejected" 1        "$(q sa "$SA1" 'SELECT 1' | grep -c 'Login failed' || true)"

(( fail == 0 )) && echo "PASS" || { echo "FAILED"; exit 1; }
