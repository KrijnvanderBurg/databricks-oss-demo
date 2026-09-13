"""Demo job: authenticated lakehouse access as the data-eng-pipeline service account.

04-submit-spark-job.sh fetches all credentials before submitting this
job (Keycloak client-credentials grant -> Unity Catalog token + temporary S3
credentials from SeaweedFS STS), so this job contains no auth code. Without
those credentials the same operations fail: Unity Catalog returns 401 and
SeaweedFS returns 403 - see 05-verify-auth-required.sh.

Demonstrated here:
  1. Governance: authenticated Unity Catalog access; the pipeline creates and
     owns schema lakehouse.demo, in the catalog admin user alice created and
     granted it access to (any UC call without a token fails with 401).
  2. Storage auth: a Delta table written to the SeaweedFS `lakehouse` bucket
     with the pipeline's temporary STS credentials (group data-engineers ->
     write role); anonymous S3 access is denied.

Note: with authorization enabled, UC OSS only lets the metastore admin register
tables at explicit LOCATIONs (path-credential vending is admin-only), so this
demo keeps table data governance at the storage layer.

Submit with:
    ./04-run-spark-job.sh
"""

from pyspark.sql import SparkSession

spark = SparkSession.Builder().appName("Lakehouse Demo (data-eng-pipeline)").getOrCreate()

# --- 1. Unity Catalog, authenticated as the pipeline service account.
spark.sql("CREATE SCHEMA IF NOT EXISTS lakehouse.demo")
print("Schemas in lakehouse (as data-eng-pipeline):")
spark.sql("SHOW SCHEMAS IN lakehouse").show()

# --- 2. Delta on SeaweedFS S3 with the pipeline's temporary STS credentials.
s3_path = "s3a://lakehouse/demo/people"
df = spark.createDataFrame([(1, "Pietje"), (2, "Puk")], ["id", "name"])
df.write.format("delta").mode("overwrite").save(s3_path)
print(f"{s3_path} (SeaweedFS, authenticated via Keycloak/STS):")
spark.read.format("delta").load(s3_path).orderBy("id").show()

spark.stop()
