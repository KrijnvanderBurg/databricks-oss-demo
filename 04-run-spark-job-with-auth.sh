#!/usr/bin/env bash
# Submits spark-job.py to the Spark cluster, authenticated as
# the data-eng-pipeline service account (Keycloak client-credentials grant,
# never tied to one team member). The job creates a schema in Unity Catalog
# and writes + reads back a Delta table on SeaweedFS, proving both the
# governance (UC) and storage (S3) auth paths work end to end. Run after
# 03-create-catalog.sh.
#
#   ./04-run-spark-job-with-auth.sh
set -euo pipefail
cd "$(dirname "$0")"

KC="http://localhost:8180"
UC_URL="http://localhost:8080"
S3_URL="http://localhost:28333"

ACCESS_TOKEN=$(curl -sf -X POST "${KC}/realms/lakehouse/protocol/openid-connect/token" \
  -d grant_type=client_credentials -d client_id=data-eng-pipeline -d client_secret=data-eng-pipeline-secret \
  | jq -r .access_token)

UC_TOKEN=$(curl -sf -X POST "${UC_URL}/api/1.0/unity-control/auth/tokens" \
  --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  --data-urlencode requested_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode subject_token="${ACCESS_TOKEN}" | jq -r .access_token)

STS_XML=$(curl -sf -X POST "${S3_URL}/" \
  --data-urlencode Action=AssumeRoleWithWebIdentity --data-urlencode Version=2011-06-15 \
  --data-urlencode RoleArn=arn:aws:iam::role/LakehouseWriteRole --data-urlencode RoleSessionName=data-eng-pipeline \
  --data-urlencode WebIdentityToken="${ACCESS_TOKEN}" --data-urlencode DurationSeconds=3600)
S3_ACCESS_KEY=$(grep -oP '(?<=<AccessKeyId>)[^<]+' <<< "${STS_XML}")
S3_SECRET_KEY=$(grep -oP '(?<=<SecretAccessKey>)[^<]+' <<< "${STS_XML}")
S3_SESSION_TOKEN=$(grep -oP '(?<=<SessionToken>)[^<]+' <<< "${STS_XML}")

docker compose exec -T spark-client /opt/spark/bin/spark-submit \
  --master "spark://spark-master:7077" \
  --conf spark.sql.catalog.lakehouse.token="${UC_TOKEN}" \
  --conf spark.hadoop.fs.s3a.access.key="${S3_ACCESS_KEY}" \
  --conf spark.hadoop.fs.s3a.secret.key="${S3_SECRET_KEY}" \
  --conf spark.hadoop.fs.s3a.session.token="${S3_SESSION_TOKEN}" \
  /opt/spark-apps/spark-job.py
