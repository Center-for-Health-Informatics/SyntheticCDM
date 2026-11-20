# syntheticcdm

An OCI image of **SQL Server 2025 with a ready-to-use OMOP CDM 5.4 database**: the full OMOP vocabulary plus about 1,200 [Synthea](https://github.com/synthetichealth/synthea) patients. It is built for developing and testing tools that run against a CDM, such as Achilles (`~/Projects/achilles`) and WebAPI (`~/Projects/webapi`).

The data is loaded when the image is built, so every container starts with the same database, ready in seconds.

## Quick start

```sh
MSSQL_SA_PASSWORD='Choose-a-Str0ng-one' ./run.sh
sqlcmd -S localhost,1433 -U sa -P "$MSSQL_SA_PASSWORD" -C -d Testing -Q "SELECT COUNT(*) FROM person"
```

`run.sh` wraps `container run`:

```sh
container run -d --name syntheticcdm --platform linux/amd64 --rosetta -m 4g -c 4 \
  -p 1433:1433 -e MSSQL_SA_PASSWORD chi-tools.uc.edu/syntheticcdm:latest
```

The container is ready when its log prints `syntheticcdm ready`. Docker and Podman can also use the image's `HEALTHCHECK`.

### Platforms

Microsoft only publishes SQL Server for **linux/amd64**, so this image is amd64 only.

| Host | How it runs |
|---|---|
| Linux amd64 | Natively |
| Mac, Apple Silicon | Under Rosetta. With `container`, pass `--rosetta`. Docker Desktop needs "Use Rosetta for x86/amd64 emulation" turned on. |
| Mac, Intel | Natively, under the container VM |
| Linux arm64 | Only under qemu-user emulation. SQL Server is not reliable there, so this is unsupported. |

Give the container at least 2 GB of memory; 4 GB is comfortable. Apple `container` defaults to 1 GB, which is too little.

## Environment

| Variable | |
|---|---|
| `MSSQL_SA_PASSWORD` | **Required.** Sets the `sa` password on every start. SQL Server's complexity rules apply: 8 or more characters, with at least three of uppercase, lowercase, digit and symbol. |
| `CDM_LOGIN`, `CDM_PASSWORD` | Optional. Creates (or updates) a least-privilege login. It can read `dbo` and can create, alter, read and write tables in the results and temp schemas below. This matches what WebAPI needs in production. |

## What's in the database

The database is `Testing`, chosen so `chi/testing` configs work unchanged. Set it at build time with `CDM_DATABASE`. The collation is `Latin1_General_100_CI_AS_SC_UTF8`.

| Schema | Contents |
|---|---|
| `dbo` | CDM 5.4 clinical tables and the vocabulary. It has primary keys and the standard CDM indexes, all page-compressed. It has no foreign keys. |
| `results`, `temp` | Empty. For Achilles (default results schema) and the CHI Node WebAPI / `chi/testing`. |
| `webapi_results`, `webapi_temp` | For OHDSI WebAPI 3 daimons. `webapi_results` already has WebAPI 3.0's results tables, and `concept_hierarchy` is filled. |
| `chi_achilles`, `ohdsi_achilles` | Empty. For comparing Achilles (Node) with R Achilles (`compare.js`). |

`cdm_source` has one row, which Achilles analysis 0 reads.

**Patients:** Synthea 3.3.0 generated 1,000 living patients plus those who died, in Cincinnati, Ohio. It used seed 42 and both a reference date and an end date of 2025-01-01, so rebuilding the image gives identical data.

**Vocabulary:** whatever Athena download the build was given. The default is v5.0 27-FEB-25; see the image label `org.ohdsi.vocabulary.version`. There are two known differences from the raw files:
- **CPT4 names:** CPT4 concepts are named `CPT4 <code> (name unavailable)`. Their real names were never reconstituted, which needs `cpt4.jar` and a UMLS key.
- **Synonyms:** a few dozen synonyms longer than the CDM's 1,000 characters are truncated.

### Connecting

| Client | Connection |
|---|---|
| JDBC (WebAPI) | `jdbc:sqlserver://localhost:1433;databaseName=Testing;encrypt=true;trustServerCertificate=true` |
| Node `mssql` / ADO | `Server=localhost,1433;Database=Testing;User Id=sa;Password=...;Encrypt=true;TrustServerCertificate=true` |
| sqlcmd | `sqlcmd -S localhost,1433 -U sa -C -d Testing` |

The server certificate is self-signed, so clients must trust it explicitly.

### Achilles

```sh
node ~/Projects/achilles/index.js --server localhost --database Testing \
  --cdm-schema dbo --results-schema results --username sa --password "$MSSQL_SA_PASSWORD"
```

Set `ACHILLES_TRUST_SERVER_CERTIFICATE=true` as well.

### WebAPI 3

Register a source with the JDBC URL above, and these daimons:

| Daimon | Schema |
|---|---|
| CDM | `dbo` |
| Vocabulary | `dbo` |
| Results | `webapi_results` |
| Temp | `webapi_temp` |

To run beside WebAPI and Atlas containers, put this container on the same network, for example `NETWORK=ohdsi ./run.sh`, and connect to it by its name.

## Building

```sh
./build.sh                  # -> chi-tools.uc.edu/syntheticcdm:{VERSION, VERSION-a<rev>, latest}
./test.sh                   # smoke test: data, logins, restart, sa password from env
PUSH=1 ./build.sh           # also scans (trivy), writes an SBOM (syft), and pushes
```

**Requirements:**
- Apple `container`, with the builder given memory. SQL Server will not start in the builder with less than 2 GB, and 8 GB is much faster. Run this once **from a GUI terminal**:

  ```sh
  container builder stop && container builder delete && container builder start --memory 8g --cpus 4
  ```

  `build.sh` never stops or starts `container` services on its own. Over SSH, the launchd domain is `user/<uid>` rather than `gui/<uid>`, so services started there get registered in the wrong place. `RESTART_BUILDER=1` lets the script resize the builder, but it refuses to do so over SSH.
- An Athena vocabulary download in `VOCAB_DIR`. The default is `~/Projects/ohdsi/OMOP-Synthea/work/vocab`, and it must contain `CONCEPT.csv`, `CONCEPT_CPT4.csv` and the rest. `build.sh` copies it into the build context as APFS clones, which takes no time or extra space.

To change the database name, use `CDM_DATABASE=MyCdm ./build.sh`. To change the Synthea population, seed or place, edit the `ARG`s in the `Containerfile`. Bump `VERSION` for every image you push.

### How the build works

The `Containerfile` has three stages:

1. **synthea** runs on the build host's native architecture. It downloads the pinned Synthea jar (checking its SHA-256) and generates the CSVs.
2. **load** runs on amd64. It starts SQL Server and runs [`scripts/load.sh`](scripts/load.sh), which does the following, in order:
   - creates the database (`sql/00`) and the CDM DDL;
   - bulk-loads the vocabulary (`sql/10`) and the Synthea CSVs (`sql/20-21`);
   - runs the ETL-Synthea SQL (`vendor/etl`);
   - drops the ETL staging tables (`sql/60`);
   - adds primary keys and indexes, then compresses everything (`sql/75`);
   - creates the schemas (`sql/80`) and the WebAPI results tables;
   - shrinks the files (`sql/90`) and shuts SQL Server down cleanly.
3. **final** is the stock SQL Server image plus `/var/opt/mssql` from the load stage, along with [`scripts/entrypoint.sh`](scripts/entrypoint.sh).

The build uses no R. ETL-Synthea's SQL Server scripts are rendered once from their SqlRender templates and committed, so the image build needs no network access for SQL.

### Vendored SQL

`vendor/` is generated. To change it, edit [`tools/vendor.sh`](tools/vendor.sh) and the patches, then regenerate:

```sh
tools/vendor.sh   # re-fetch the pinned commits, render, apply patches/; then commit vendor/
```

| Path | Source |
|---|---|
| `vendor/cdm/` | OHDSI CommonDataModel 5.4 SQL Server DDL, primary keys and indices (Apache-2.0) |
| `vendor/etl/` | OHDSI ETL-Synthea SQL Server scripts for CDM 5.4 and Synthea 3.3.0 (Apache-2.0), in run order |
| `vendor/webapi/` | The WebAPI 3.0 results-schema DDL from `~/Projects/webapi` (branch `chi/3.0.x`) |

[`tools/sqlrender.py`](tools/sqlrender.py) renders templates the way SqlRender would. It substitutes `@params` and evaluates `{cond} ? {a} : {b}`. It also puts each statement in its own `sqlcmd` batch, to match how DatabaseConnector ran them.

Two upstream statements are not valid T-SQL without SqlRender's translation step. [`patches/`](patches/) fixes them:
- `final_visit_ids` uses `CREATE TABLE … AS SELECT`;
- `insert_person` puts a CTE after `INSERT`.

Each vendored directory has an `UPSTREAM` file that records its commit.
