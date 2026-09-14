#!/usr/bin/env bash
# As alice (the metastore admin), creates the "lakehouse" catalog, grants
# pietje and the data-eng-pipeline service account access to it, and creates
# the backing SeaweedFS bucket. Run once, after 02-create-unity-catalog-users.sh.
#
#   ./03-create-catalog.sh
set -euo pipefail
cd "$(dirname "$0")"

KC="http://localhost:8180"
UC_URL="http://localhost:8080"

# Keycloak password grant (alice is a real person at a keyboard) -> Unity
# Catalog token exchange, same pattern as 04-run-spark-job-with-auth.sh.
ALICE_ID_TOKEN=$(curl -sf -X POST "${KC}/realms/lakehouse/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=lakehouse-client -d client_secret=lakehouse-client-secret \
  -d username=alice -d password=alice123 -d scope="openid profile email" | jq -r .id_token)

ALICE_TOKEN=$(curl -sf -X POST "${UC_URL}/api/1.0/unity-control/auth/tokens" \
  --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  --data-urlencode requested_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode subject_token_type=urn:ietf:params:oauth:token-type:id_token \
  --data-urlencode subject_token="${ALICE_ID_TOKEN}" | jq -r .access_token)

uc() { docker compose exec -T unity-catalog bin/uc --server http://localhost:8080 --auth_token "${ALICE_TOKEN}" "$@"; }

uc catalog create --name lakehouse --comment "Created by alice"

for principal in pietje@lakehouse.local data-eng-pipeline@lakehouse.local; do
  uc permission create --securable_type catalog --name lakehouse --privilege "USE CATALOG" --principal "${principal}"
  uc permission create --securable_type catalog --name lakehouse --privilege "CREATE SCHEMA" --principal "${principal}"
done

# Data lives in SeaweedFS, not in Unity Catalog itself - create the bucket.
docker compose exec -T seaweedfs-master sh -c \
  "printf 'lock\ns3.bucket.create -name lakehouse\nunlock\nexit\n' | weed shell -master=seaweedfs-master:9333 -filer=seaweedfs-filer:8888"
