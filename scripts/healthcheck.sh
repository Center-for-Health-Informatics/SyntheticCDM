#!/bin/bash
# Healthy once entrypoint.sh has finished setup and SQL Server answers.
# (Docker/Podman HEALTHCHECK; Apple container ignores it, so watch the log for
# "syntheticcdm ready" instead.)
[[ -e /tmp/cdm-ready ]] || exit 1
SQLCMDPASSWORD=$MSSQL_SA_PASSWORD exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -No -l 5 -Q "SELECT 1" >/dev/null
