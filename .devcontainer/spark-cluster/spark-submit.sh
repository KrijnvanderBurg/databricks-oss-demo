# Permission denied? run `chmod +x spark-submit.sh`

#!/bin/bash
# Use first argument as the file to submit, or default to sample_job.py if no argument provided
FILE_TO_SUBMIT=${1}

# Check if file has .py extension
# if [[ "$FILE_TO_SUBMIT" != *.py ]]; then
#   echo "Error: Only Python files (.py) are supported."
#   exit 1
# fi

# Authenticate as the data-eng-pipeline service account, not any one team
# member: Keycloak client-credentials grant -> Unity Catalog token exchange ->
# SeaweedFS STS AssumeRoleWithWebIdentity. Tokens are short-lived, fetched
# fresh on every submit. Plain curl/jq, no separate auth script.
ACCESS_TOKEN=$(curl -sf -X POST http://keycloak:8080/realms/lakehouse/protocol/openid-connect/token \
  -d grant_type=client_credentials \
  -d client_id=data-eng-pipeline \
  -d client_secret=data-eng-pipeline-secret | jq -r .access_token)
[ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ] || { echo "ERROR: Keycloak login failed" >&2; exit 1; }

UC_TOKEN=$(curl -sf -X POST http://unity-catalog:8080/api/1.0/unity-control/auth/tokens \
  --data-urlencode grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  --data-urlencode requested_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode subject_token="$ACCESS_TOKEN" | jq -r .access_token)
[ -n "$UC_TOKEN" ] && [ "$UC_TOKEN" != "null" ] || { echo "ERROR: Unity Catalog token exchange failed" >&2; exit 1; }

STS_XML=$(curl -sf -X POST http://seaweedfs-s3:8333/ \
  --data-urlencode Action=AssumeRoleWithWebIdentity \
  --data-urlencode Version=2011-06-15 \
  --data-urlencode RoleArn=arn:aws:iam::role/LakehouseWriteRole \
  --data-urlencode RoleSessionName=data-eng-pipeline \
  --data-urlencode WebIdentityToken="$ACCESS_TOKEN" \
  --data-urlencode DurationSeconds=3600)
S3_ACCESS_KEY=$(grep -oP '(?<=<AccessKeyId>)[^<]+' <<< "$STS_XML")
S3_SECRET_KEY=$(grep -oP '(?<=<SecretAccessKey>)[^<]+' <<< "$STS_XML")
S3_SESSION_TOKEN=$(grep -oP '(?<=<SessionToken>)[^<]+' <<< "$STS_XML")
[ -n "$S3_ACCESS_KEY" ] || { echo "ERROR: SeaweedFS STS AssumeRole failed: $STS_XML" >&2; exit 1; }

/opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode client \
  --conf spark.driver.host=devcontainer \
  --conf spark.driver.bindAddress=0.0.0.0 \
  --conf spark.sql.catalog.lakehouse.token="$UC_TOKEN" \
  --conf spark.hadoop.fs.s3a.access.key="$S3_ACCESS_KEY" \
  --conf spark.hadoop.fs.s3a.secret.key="$S3_SECRET_KEY" \
  --conf spark.hadoop.fs.s3a.session.token="$S3_SESSION_TOKEN" \
  "$FILE_TO_SUBMIT"
