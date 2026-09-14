#!/usr/bin/env bash
# Negative-path smoke test: proves nothing works without authentication.
# Checks Unity Catalog and SeaweedFS S3 directly, then submits the exact same
# Spark job as 04-run-spark-job-with-auth.sh but with zero credentials attached.
#
#   ./05-run-spark-job-without-auth.sh
set -uo pipefail
cd "$(dirname "$0")"

UC_URL="http://localhost:8080"
S3_URL="http://localhost:28333"

echo "Unity Catalog list catalogs without a token (expect 401/403):"
curl -s -o /dev/null -w '%{http_code}\n' "${UC_URL}/api/2.1/unity-catalog/catalogs"

echo "SeaweedFS S3 anonymous ListObjects (expect 401/403):"
curl -s -o /dev/null -w '%{http_code}\n' "${S3_URL}/lakehouse?list-type=2"

echo "SeaweedFS S3 anonymous PutObject (expect 401/403):"
curl -s -o /dev/null -w '%{http_code}\n' -X PUT -d "unauthorized" "${S3_URL}/lakehouse/hack.txt"

echo "Submitting the same Spark job WITHOUT any credentials (expect it to fail):"
docker compose exec -T spark-client /opt/spark/bin/spark-submit \
  --master "spark://spark-master:7077" /opt/spark-apps/spark-job.py
