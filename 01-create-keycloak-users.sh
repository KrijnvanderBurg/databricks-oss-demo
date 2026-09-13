#!/usr/bin/env bash
# Creates the two human demo users in Keycloak via the Admin REST API:
# alice (lakehouse-admins) and pietje (data-engineers). Everything else
# (the realm, groups, and OIDC clients) is seeded by realm import at
# container startup - this script shows how a real onboarding automation
# would provision a person. Run once, after `docker compose up -d`.
#
#   ./01-create-keycloak-users.sh
set -euo pipefail

KC="http://localhost:8180"

ADMIN_TOKEN=$(curl -sf -X POST "${KC}/realms/master/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=admin-cli \
  -d username=admin -d password=admin | jq -r .access_token)

create_user() {
  local username=$1 first=$2 last=$3 password=$4 group=$5
  curl -sf -X POST "${KC}/admin/realms/lakehouse/users" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" -H "Content-Type: application/json" \
    -d "$(jq -n --arg u "$username" --arg e "${username}@lakehouse.local" --arg f "$first" --arg l "$last" --arg p "$password" \
      '{username:$u, email:$e, firstName:$f, lastName:$l, enabled:true, emailVerified:true,
        credentials:[{type:"password", value:$p, temporary:false}]}')"

  local user_id group_id
  user_id=$(curl -sf -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KC}/admin/realms/lakehouse/users?username=${username}&exact=true" | jq -r '.[0].id')
  group_id=$(curl -sf -H "Authorization: Bearer ${ADMIN_TOKEN}" "${KC}/admin/realms/lakehouse/groups" \
    | jq -r --arg n "${group}" '.[] | select(.name==$n) | .id')
  curl -sf -X PUT "${KC}/admin/realms/lakehouse/users/${user_id}/groups/${group_id}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}"
  echo "created user ${username} (group: ${group})"
}

create_user alice "Alice" "Admin" alice123 "lakehouse-admins"
create_user pietje "Pietje" "Puk" pietje123 "data-engineers"
