#!/usr/bin/env bash
#
# Build the syntheticcdm image (linux/amd64) with Apple's `container` tool and,
# with PUSH=1, push it to the CHI registry.
#
#   ./build.sh              build only
#   PUSH=1 ./build.sh       build, scan, and push to $REGISTRY
#
# The build generates Synthea patients, then runs SQL Server *inside the build*
# to load the vocabulary and ETL the patients into an OMOP CDM 5.4 database, and
# ships the resulting data files. Expect ~30-60 min under Rosetta.
# The version is VERSION (e.g. 1.0.0): bump it for every image you push; tags
# are never reused.
#
# One-time setup (from a GUI terminal, not over SSH -- see "Builder" below):
#   container system start
#   container builder start --memory 8g --cpus 4
#   container registry login chi-tools.uc.edu
#   skopeo login chi-tools.uc.edu       (pushing only)
# Pushing also needs trivy (vulnerability gate) and syft (SBOM).
#
# Environment overrides: REGISTRY, PUSH, FORCE (push from a dirty tree),
# VOCAB_DIR (Athena vocabulary CSVs), CDM_DATABASE (default Testing),
# RESTART_BUILDER (let this script resize the builder; refused over SSH).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD

REGISTRY=${REGISTRY:-chi-tools.uc.edu}
NAME=syntheticcdm
PLATFORM=linux/amd64          # Microsoft publishes SQL Server for amd64 only
PUSH=${PUSH:-0}
VOCAB_DIR=${VOCAB_DIR:-$HOME/Projects/ohdsi/OMOP-Synthea/work/vocab}
CDM_DATABASE=${CDM_DATABASE:-Testing}
BUILDER_MIN_MB=2048           # SQL Server refuses to start below ~2 GB
BUILDER_WANT_MB=8192
BUILDER_WANT_CPUS=4

die() { echo "build.sh: $*" >&2; exit 1; }
warn() { echo "build.sh: warning: $*" >&2; }

VERSION=$(tr -d '[:space:]' < VERSION)
REVISION=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
[[ -z $(git status --porcelain 2>/dev/null) ]] || REVISION="${REVISION}-dirty"

IMAGE="${REGISTRY}/${NAME}"
TAGS=("${VERSION}" "${VERSION}-a${REVISION%-dirty}" latest)

command -v container >/dev/null 2>&1 || die "Apple's container tool is required"
# Probe the apiserver with a real request: over SSH, `container system status`
# looks in launchd's user/<uid> domain and reports "not registered" even when
# the apiserver is running in gui/<uid>.
container list --quiet >/dev/null 2>&1 || die "container system is not running (container system start, from a GUI terminal)"

# --- Vocabulary --------------------------------------------------------------
VOCAB_FILES=(CONCEPT CONCEPT_ANCESTOR CONCEPT_CLASS CONCEPT_CPT4 CONCEPT_RELATIONSHIP
             CONCEPT_SYNONYM DOMAIN DRUG_STRENGTH RELATIONSHIP VOCABULARY)
for f in "${VOCAB_FILES[@]}"; do
  [[ -s "$VOCAB_DIR/$f.csv" ]] || die "missing $VOCAB_DIR/$f.csv (set VOCAB_DIR to an Athena download)"
done
VOCAB_VERSION=$(awk -F'\t' '$1 == "None" { print $4 }' "$VOCAB_DIR/VOCABULARY.csv")
[[ -n $VOCAB_VERSION ]] || die "no 'None' row in $VOCAB_DIR/VOCABULARY.csv"

# --- Builder -----------------------------------------------------------------
# Never stop/start container services implicitly: over SSH the launchd domain
# is user/<uid> rather than gui/<uid>, and services started from there end up
# registered in the wrong domain.
builder_status() { container builder status 2>/dev/null | awk 'NR == 2 { print $3, $(NF-2), $(NF-1) }'; }
read -r b_state b_cpus b_mem <<<"$(builder_status)" || true
over_ssh() { [[ -n ${SSH_CONNECTION:-}${SSH_TTY:-} ]]; }
resize_cmd="container builder stop && container builder delete && container builder start --memory ${BUILDER_WANT_MB}m --cpus ${BUILDER_WANT_CPUS}"
if [[ ${b_state:-} != running ]]; then
  over_ssh && die "the builder is not running; start it from a GUI terminal: container builder start --memory ${BUILDER_WANT_MB}m --cpus ${BUILDER_WANT_CPUS}"
  echo "starting builder (${BUILDER_WANT_MB} MB, ${BUILDER_WANT_CPUS} CPUs)"
  container builder start --memory "${BUILDER_WANT_MB}m" --cpus "$BUILDER_WANT_CPUS"
  read -r b_state b_cpus b_mem <<<"$(builder_status)"
elif (( b_mem < BUILDER_WANT_MB || b_cpus < BUILDER_WANT_CPUS )); then
  if [[ ${RESTART_BUILDER:-0} == 1 ]]; then
    over_ssh && [[ ${FORCE:-0} != 1 ]] && die "refusing to restart the builder over SSH (launchd domain); run from a GUI terminal: $resize_cmd"
    echo "restarting builder with ${BUILDER_WANT_MB} MB, ${BUILDER_WANT_CPUS} CPUs"
    container builder stop; container builder delete
    container builder start --memory "${BUILDER_WANT_MB}m" --cpus "$BUILDER_WANT_CPUS"
    read -r b_state b_cpus b_mem <<<"$(builder_status)"
  else
    (( b_mem >= BUILDER_MIN_MB )) || die "the builder has ${b_mem} MB; SQL Server needs >= ${BUILDER_MIN_MB}. From a GUI terminal: $resize_cmd"
    warn "the builder has ${b_mem} MB / ${b_cpus} CPUs; ${BUILDER_WANT_MB} MB / ${BUILDER_WANT_CPUS} CPUs is much faster."
    warn "  from a GUI terminal: $resize_cmd   (or RESTART_BUILDER=1 ./build.sh)"
  fi
fi

# --- Push preflight ----------------------------------------------------------
if [[ $PUSH == 1 ]]; then
  [[ "$REVISION" != *-dirty || ${FORCE:-0} == 1 ]] ||
    die "refusing to push from a dirty working tree. Commit first, or set FORCE=1."
  for t in trivy syft skopeo; do command -v $t >/dev/null 2>&1 || die "$t is required to push"; done
  if out=$(skopeo inspect --raw "docker://${IMAGE}:${VERSION}" 2>&1); then
    die "${IMAGE}:${VERSION} already exists in the registry. Bump VERSION."
  elif ! grep -qiE 'manifest unknown|not found' <<<"$out"; then
    die "could not check ${IMAGE}:${VERSION} in the registry: ${out}"
  fi
fi

# --- Context: repo files plus an APFS clone (cp -c: instant, no extra space)
# of the vocabulary. ----------------------------------------------------------
CTX="${ROOT}/build/context"
rm -rf "$CTX" && mkdir -p "$CTX/vocab"
cp Containerfile "$CTX/"
cp -R sql vendor scripts "$CTX/"
for f in "${VOCAB_FILES[@]}"; do cp -c "$VOCAB_DIR/$f.csv" "$CTX/vocab/" 2>/dev/null || cp "$VOCAB_DIR/$f.csv" "$CTX/vocab/"; done

echo "building ${IMAGE}:${VERSION} @ ${REVISION} (vocabulary ${VOCAB_VERSION}, database ${CDM_DATABASE})"
container build --platform "$PLATFORM" -f "$CTX/Containerfile" -t "${IMAGE}:${VERSION}" \
  --build-arg VERSION="$VERSION" --build-arg REVISION="$REVISION" \
  --build-arg CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg VOCAB_VERSION="$VOCAB_VERSION" --build-arg CDM_DATABASE="$CDM_DATABASE" \
  "$CTX"
for TAG in "${TAGS[@]:1}"; do container image tag "${IMAGE}:${VERSION}" "${IMAGE}:${TAG}"; done
echo; for TAG in "${TAGS[@]}"; do echo "built ${IMAGE}:${TAG}"; done

if [[ $PUSH != 1 ]]; then echo; echo "not pushed (set PUSH=1 to push to ${REGISTRY})"; exit 0; fi

OUT="${ROOT}/build"
ARCHIVE="${OUT}/${NAME}-${VERSION}-amd64.tar"
LAYOUT="${OUT}/${NAME}-${VERSION}-amd64"
rm -rf "$ARCHIVE" "$LAYOUT"
container image save --platform "$PLATFORM" -o "$ARCHIVE" "${IMAGE}:${VERSION}"
mkdir "$LAYOUT" && tar -xf "$ARCHIVE" -C "$LAYOUT"

echo "scanning (fails on fixable HIGH/CRITICAL)"
trivy image --quiet --input "$LAYOUT" --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1
syft -q "oci-dir:${LAYOUT}" -o "spdx-json=${OUT}/${NAME}-${VERSION}.spdx.json"

for TAG in "${TAGS[@]}"; do echo "pushing ${IMAGE}:${TAG}"; container image push "${IMAGE}:${TAG}"; done
rm -rf "$ARCHIVE" "$LAYOUT"
echo; echo "SBOM: ${OUT}/${NAME}-${VERSION}.spdx.json"
