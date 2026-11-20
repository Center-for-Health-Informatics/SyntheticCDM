# syntheticcdm: SQL Server 2025 with an OMOP CDM 5.4 database (full vocabulary
# + Synthea patients) baked in. Build with ./build.sh, which assembles the
# context (this file, sql/, vendor/, scripts/, and the vocabulary as vocab/).
#
# linux/amd64 only: Microsoft ships no arm64 SQL Server. On Apple Silicon, run
# it under Rosetta (container run --platform linux/amd64 --rosetta ...).

ARG MSSQL_IMAGE=mcr.microsoft.com/mssql/server:2025-CU11-ubuntu-24.04@sha256:05644dad1266ca3d445d1e8f6d2ebb9a6a03df9a39376e0f7b48917356dca9d9
ARG JRE_IMAGE=eclipse-temurin:21-jre-noble

# --- 1. Generate the Synthea population (CSV is arch-neutral: run natively) ---
FROM --platform=$BUILDPLATFORM ${JRE_IMAGE} AS synthea
ARG SYNTHEA_VERSION=3.3.0
ARG SYNTHEA_SHA256=8ba04f7d73abadd5a377e41edf24c5c83935a1cb07c6d982cd5db731ef1cf445
ARG SYNTHEA_SEED=42
ARG SYNTHEA_POPULATION=1000
ARG SYNTHEA_DATE=20250101
ARG SYNTHEA_STATE=Ohio
ARG SYNTHEA_CITY=Cincinnati
ADD https://github.com/synthetichealth/synthea/releases/download/v${SYNTHEA_VERSION}/synthea-with-dependencies.jar /opt/synthea/synthea.jar
RUN echo "${SYNTHEA_SHA256}  /opt/synthea/synthea.jar" | sha256sum -c -
WORKDIR /work
# Fixed seeds plus a fixed reference *and* end date make the output
# reproducible (without -e the simulation runs up to "now").
RUN java -XX:MaxRAMPercentage=60 -jar /opt/synthea/synthea.jar \
      -s "${SYNTHEA_SEED}" -cs "${SYNTHEA_SEED}" -r "${SYNTHEA_DATE}" -e "${SYNTHEA_DATE}" -p "${SYNTHEA_POPULATION}" \
      --exporter.baseDirectory=/work/out --exporter.csv.export=true --exporter.fhir.export=false \
      --exporter.hospital.fhir.export=false --exporter.practitioner.fhir.export=false \
      --generate.log_patients.detail=none \
      "${SYNTHEA_STATE}" "${SYNTHEA_CITY}" > /work/synthea.log 2>&1 \
 || { tail -50 /work/synthea.log; exit 1; } ; \
    tail -3 /work/synthea.log && test -s /work/out/csv/patients.csv

# --- 2. Load the CDM (runs SQL Server inside the build) -----------------------
FROM ${MSSQL_IMAGE} AS load
ARG CDM_DATABASE=Testing
# Least-changing inputs first, for layer caching.
COPY vocab /build/vocab
COPY --from=synthea /work/out/csv /build/synthea
COPY vendor /build/vendor
COPY sql /build/sql
COPY scripts/load.sh /build/scripts/load.sh
RUN CDM_DATABASE="${CDM_DATABASE}" /build/scripts/load.sh

# --- 3. Final image: base SQL Server + the loaded data files -----------------
FROM ${MSSQL_IMAGE}
ARG CDM_DATABASE=Testing
ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED
ARG VOCAB_VERSION=unknown
ARG SYNTHEA_VERSION=3.3.0
ARG SYNTHEA_SEED=42
ARG SYNTHEA_POPULATION=1000
ARG SYNTHEA_DATE=20250101
ENV ACCEPT_EULA=Y \
    MSSQL_PID=Developer \
    CDM_DATABASE=${CDM_DATABASE}
COPY --from=load --chown=mssql:mssql /var/opt/mssql /var/opt/mssql
COPY --chmod=0755 scripts/entrypoint.sh scripts/healthcheck.sh /opt/syntheticcdm/
COPY --chmod=0644 scripts/app-login.sql /opt/syntheticcdm/
EXPOSE 1433
HEALTHCHECK --interval=10s --timeout=10s --start-period=90s --retries=6 CMD ["/opt/syntheticcdm/healthcheck.sh"]
ENTRYPOINT ["/opt/syntheticcdm/entrypoint.sh"]
CMD []
LABEL org.opencontainers.image.title="syntheticcdm" \
      org.opencontainers.image.description="SQL Server 2025 with an OMOP CDM 5.4 database (${CDM_DATABASE}) of Synthea ${SYNTHEA_VERSION} patients and the full OMOP vocabulary" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.ohdsi.cdm.version="5.4" \
      org.ohdsi.cdm.database="${CDM_DATABASE}" \
      org.ohdsi.vocabulary.version="${VOCAB_VERSION}" \
      org.synthea.version="${SYNTHEA_VERSION}" \
      org.synthea.seed="${SYNTHEA_SEED}" \
      org.synthea.population="${SYNTHEA_POPULATION}" \
      org.synthea.reference-date="${SYNTHEA_DATE}"
