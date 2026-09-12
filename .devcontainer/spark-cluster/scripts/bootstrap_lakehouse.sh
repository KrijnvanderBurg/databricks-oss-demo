#!/usr/bin/env bash
# One-time lakehouse setup for this demo's 3 fixed principals: alice (admin),
# pietje (data engineer), and the data-eng-pipeline service account.
# Run once from a terminal INSIDE the devcontainer (needs spark-network DNS
# for keycloak/unity-catalog, and docker CLI access via the
# docker-outside-of-docker feature to exec into other containers).
# Idempotent; safe to re-run.
#
#   cd .devcontainer/spark-cluster
#   ./scripts/bootstrap_lakehouse.sh
set -eu

TOKEN_FILE=/home/unitycatalog/etc/conf/token.txt
echo "Waiting for UC admin token..."
for _ in $(seq 1 60); do
  docker exec unity-catalog test -s "${TOKEN_FILE}" && break
  sleep 2
done
SYS_TOKEN=$(docker exec unity-catalog cat "${TOKEN_FILE}")
[ -n "${SYS_TOKEN}" ] || { echo "ERROR: UC admin token never appeared" >&2; exit 1; }

uc() {
  local token=$1
  shift
  docker exec unity-catalog bin/uc --server http://localhost:8080 --auth_token "${token}" "$@"
}

# --- Register the 3 demo principals in Unity Catalog (idempotent).
uc "${SYS_TOKEN}" user create --name "Alice Admin" --email alice@lakehouse.local \
  || echo "user alice@lakehouse.local already exists"
uc "${SYS_TOKEN}" user create --name "Pietje Puk" --email pietje@lakehouse.local \
  || echo "user pietje@lakehouse.local already exists"
# externalId links this principal to the Keycloak service-account client id,
# since its tokens have no personal email claim to match on.
uc "${SYS_TOKEN}" user create --name "Data Eng Pipeline" --email data-eng-pipeline@lakehouse.local \
  --external_id data-eng-pipeline \
  || echo "user data-eng-pipeline@lakehouse.local already exists"

# --- Let alice self-serve: grant metastore-wide CREATE CATALOG.
# NOTE: verify the metastore securable name for your UC version, e.g. via
# `docker exec unity-catalog bin/uc metastore list`.
uc "${SYS_TOKEN}" permission create --securable_type metastore --name metastore \
  --privilege "CREATE CATALOG" --principal alice@lakehouse.local || true

# --- Act as alice: create the catalog and grant pietje + the pipeline access to it.
# Plain curl/jq, same as spark-submit.sh - no separate auth script.
ALICE_ID_TOKEN=$(curl -sf -X POST http://keycloak:8080/realms/lakehouse/protocol/openid-connect/token \
  -d grant_type=password \
  -d client_id=lakehouse-client \
  -d client_secret=lakehouse-client-secret \
  -d username=alice \
  -d password=alice123 \
  -d scope="openid profile email" | jq -r .id_token)

ADMIN_TOKEN=$(curl -sf -X POST http://unity-catalog:8080/api/1.0/unity-control/auth/tokens \
  --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  --data-urlencode requested_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode subject_token_type=urn:ietf:params:oauth:token-type:id_token \
  --data-urlencode subject_token="${ALICE_ID_TOKEN}" | jq -r .access_token)
[ -n "${ADMIN_TOKEN}" ] && [ "${ADMIN_TOKEN}" != "null" ] || { echo "ERROR: alice login failed" >&2; exit 1; }

uc "${ADMIN_TOKEN}" catalog create --name lakehouse --comment "Created by admin" \
  || echo "catalog lakehouse already exists"

uc "${ADMIN_TOKEN}" permission create --securable_type catalog --name lakehouse \
  --privilege "USE CATALOG" --principal pietje@lakehouse.local || true
uc "${ADMIN_TOKEN}" permission create --securable_type catalog --name lakehouse \
  --privilege "CREATE SCHEMA" --principal pietje@lakehouse.local || true
uc "${ADMIN_TOKEN}" permission create --securable_type catalog --name lakehouse \
  --privilege "USE CATALOG" --principal data-eng-pipeline@lakehouse.local || true
uc "${ADMIN_TOKEN}" permission create --securable_type catalog --name lakehouse \
  --privilege "CREATE SCHEMA" --principal data-eng-pipeline@lakehouse.local || true

# --- Create the SeaweedFS bucket backing the catalog's data.
docker exec seaweedfs-master sh -c \
  "printf 'lock\ns3.bucket.create -name lakehouse\nunlock\nexit\n' | weed shell -master=seaweedfs-master:9333 -filer=seaweedfs-filer:8888" \
  || echo "bucket lakehouse already exists (or shell reported an error above)"

echo "Lakehouse bootstrap complete."

uc "${ADMIN_TOKEN}" permission create --securable_type catalog --name lakehouse \
  --privilege "USE CATALOG" --principal pietje@lakehouse.local || true
uc "${ADMIN_TOKEN}" permission create --securable_type catalog --name lakehouse \
  --privilege "CREATE SCHEMA" --principal pietje@lakehouse.local || true
uc "${ADMIN_TOKEN}" permission create --securable_type catalog --name lakehouse \
  --privilege "USE CATALOG" --principal data-eng-pipeline@lakehouse.local || true
uc "${ADMIN_TOKEN}" permission create --securable_type catalog --name lakehouse \
  --privilege "CREATE SCHEMA" --principal data-eng-pipeline@lakehouse.local || true

# --- Create the SeaweedFS bucket backing the catalog's data.
docker exec seaweedfs-master sh -c \
  "printf 'lock\ns3.bucket.create -name lakehouse\nunlock\nexit\n' | weed shell -master=seaweedfs-master:9333 -filer=seaweedfs-filer:8888" \
  || echo "bucket lakehouse already exists (or shell reported an error above)"

echo "Lakehouse bootstrap complete."
