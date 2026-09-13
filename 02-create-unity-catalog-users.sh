#!/usr/bin/env bash
# Registers the 3 demo principals (alice, pietje, the data-eng-pipeline
# service account) in Unity Catalog, and grants alice metastore-wide
# CREATE CATALOG so she can self-serve the next step. Run once, after
# 01-create-keycloak-users.sh.
#
#   ./02-create-unity-catalog-users.sh
set -euo pipefail
cd "$(dirname "$0")"

SYS_TOKEN=$(docker compose exec -T unity-catalog cat /home/unitycatalog/etc/conf/token.txt)

uc() {
  local token=$1; shift
  docker compose exec -T unity-catalog bin/uc --server http://localhost:8080 --auth_token "${token}" "$@"
}

uc "${SYS_TOKEN}" user create --name "Alice Admin" --email alice@lakehouse.local
uc "${SYS_TOKEN}" user create --name "Pietje Puk" --email pietje@lakehouse.local
# externalId links this principal to the Keycloak service-account client id,
# since its tokens carry no personal email claim to match on.
uc "${SYS_TOKEN}" user create --name "Data Eng Pipeline" --email data-eng-pipeline@lakehouse.local \
  --external_id data-eng-pipeline

uc "${SYS_TOKEN}" permission create --securable_type metastore --name metastore \
  --privilege "CREATE CATALOG" --principal alice@lakehouse.local
