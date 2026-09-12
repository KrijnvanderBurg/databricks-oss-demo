"""
Spark auto-initialization script for Jupyter notebooks.
This script runs automatically when a notebook kernel starts."""

import json
import logging
import os
import re
import sys
import urllib.parse
import urllib.request

from pyspark.sql import SparkSession

logging.basicConfig(level=logging.WARN)

print("Initializing Spark session...", file=sys.stderr)


def _post_form(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode()


# Authenticate as the human user (Keycloak password grant -> UC token exchange
# -> SeaweedFS STS), fetched fresh on every kernel start.
_auth_confs = {}
try:
    _username = os.environ.get("LAKEHOUSE_USER", "pietje")
    _password = os.environ.get("LAKEHOUSE_PASSWORD", "pietje123")
    _tokens = json.loads(_post_form(
        "http://keycloak:8080/realms/lakehouse/protocol/openid-connect/token",
        {
            "grant_type": "password",
            "client_id": "lakehouse-client",
            "client_secret": "lakehouse-client-secret",
            "username": _username,
            "password": _password,
            "scope": "openid profile email",
        },
    ))
    _uc_token = json.loads(_post_form(
        "http://unity-catalog:8080/api/1.0/unity-control/auth/tokens",
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
            "subject_token": _tokens["id_token"],
        },
    ))["access_token"]
    _sts_body = _post_form(
        "http://seaweedfs-s3:8333/",
        {
            "Action": "AssumeRoleWithWebIdentity",
            "Version": "2011-06-15",
            "RoleArn": "arn:aws:iam::role/LakehouseWriteRole",
            "RoleSessionName": _username,
            "WebIdentityToken": _tokens["access_token"],
            "DurationSeconds": "3600",
        },
    )
    _xml = lambda tag: re.search(rf"<{tag}>([^<]+)</{tag}>", _sts_body).group(1)
    _auth_confs = {
        "spark.sql.catalog.lakehouse.token": _uc_token,
        "spark.hadoop.fs.s3a.access.key": _xml("AccessKeyId"),
        "spark.hadoop.fs.s3a.secret.key": _xml("SecretAccessKey"),
        "spark.hadoop.fs.s3a.session.token": _xml("SessionToken"),
    }
    print("Lakehouse authentication succeeded.", file=sys.stderr)
except Exception as exc:  # noqa: BLE001 - keep the kernel usable without auth
    print(f"WARNING: lakehouse authentication failed ({exc}). "
          "Unity Catalog and S3 access will be denied.", file=sys.stderr)

# Build the SparkSession with sensible defaults for notebook usage
_builder = SparkSession.Builder() \
    .appName("Jupyter Notebook") \
    .master("spark://spark-master:7077") \
    .config("spark.driver.host", "devcontainer") \
    .config("spark.driver.bindAddress", "0.0.0.0") \
    .config("spark.ui.port", "4040") \
    .config("spark.dynamicAllocation.enabled", "false") \
    .config("spark.scheduler.mode", "FAIR") \
    .config("spark.python.worker.reuse", "true")

for _key, _value in _auth_confs.items():
    _builder = _builder.config(_key, _value)

spark = _builder.getOrCreate()

# Create a SparkContext variable for backward compatibility
sc = spark.sparkContext

# Set a higher log level to reduce verbosity
sc.setLogLevel("WARN")

# Print Spark session info
print(f"SparkSession successfully initialized!", file=sys.stderr)
print(f"Spark version: {spark.version}", file=sys.stderr)
print(f"Using {sc.defaultParallelism} cores by default", file=sys.stderr)
print("Spark Web UI available at http://localhost:4040", file=sys.stderr)

# Print connection information to help with debugging
print(f"Connected to Spark master: {sc.master}", file=sys.stderr)
print(f"Application ID: {sc.applicationId}", file=sys.stderr)
