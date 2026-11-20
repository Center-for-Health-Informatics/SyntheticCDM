#!/usr/bin/env bash
#
# Run the syntheticcdm image locally with Apple's `container` tool.
#
#   MSSQL_SA_PASSWORD='...' ./run.sh            start (detached) as "syntheticcdm"
#   CDM_LOGIN=ohdsi CDM_PASSWORD='...' MSSQL_SA_PASSWORD='...' ./run.sh
#
# Environment overrides: IMAGE, NAME, PORT (host port, default 1433), MEMORY,
# CPUS, NETWORK (e.g. ohdsi, to sit beside WebAPI/Atlas containers).
# SQL Server needs >= 2 GB; the container default (1 GB) is too small.
set -euo pipefail

IMAGE=${IMAGE:-chi-tools.uc.edu/syntheticcdm:latest}
NAME=${NAME:-syntheticcdm}
PORT=${PORT:-1433}
MEMORY=${MEMORY:-4g}
CPUS=${CPUS:-4}

die() { echo "run.sh: $*" >&2; exit 1; }
[[ -n ${MSSQL_SA_PASSWORD:-} ]] || die "set MSSQL_SA_PASSWORD"

ARGS=(--detach --name "$NAME" --platform linux/amd64 --memory "$MEMORY" --cpus "$CPUS"
      --publish "${PORT}:1433" --env MSSQL_SA_PASSWORD)
# Rosetta runs the amd64 SQL Server binaries on Apple Silicon.
[[ $(uname -m) == arm64 ]] && ARGS+=(--rosetta)
[[ -n ${CDM_LOGIN:-} ]] && ARGS+=(--env CDM_LOGIN --env CDM_PASSWORD)
[[ -n ${NETWORK:-} ]] && ARGS+=(--network "$NETWORK")

container run "${ARGS[@]}" "$IMAGE" >/dev/null
echo "started $NAME; waiting for SQL Server..."
for _ in $(seq 1 120); do
  if container logs "$NAME" 2>/dev/null | grep -q 'syntheticcdm ready'; then
    container logs "$NAME" | grep 'syntheticcdm' 
    echo "connect: localhost,${PORT}  (TrustServerCertificate=true)"
    exit 0
  fi
  container ls -q | grep -qx "$NAME" || die "container exited; see: container logs $NAME"
  sleep 1
done
die "not ready after 120s; see: container logs $NAME"
