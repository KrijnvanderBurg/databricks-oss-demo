"""Smoke test: authentication/authorization must be enforced end to end.

Run inside the devcontainer (or any container on the spark-network):
    python3 scripts/verify_lakehouse_auth.py
"""
import sys, json, urllib.parse, urllib.request, urllib.error

failures = []


def expect(desc, ok):
    print(("[PASS] " if ok else "[FAIL] ") + desc)
    if not ok:
        failures.append(desc)


def post_form(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


# 1. UC without token -> 401/403
try:
    urllib.request.urlopen("http://unity-catalog:8080/api/2.1/unity-catalog/catalogs", timeout=10)
    expect("UC list catalogs WITHOUT token is denied", False)
except urllib.error.HTTPError as e:
    expect(f"UC list catalogs WITHOUT token is denied (HTTP {e.code})", e.code in (401, 403))

# 2. UC with pietje's token -> catalogs visible
tokens = post_form("http://keycloak:8080/realms/lakehouse/protocol/openid-connect/token", {
    "grant_type": "password",
    "client_id": "lakehouse-client",
    "client_secret": "lakehouse-client-secret",
    "username": "pietje",
    "password": "pietje123",
    "scope": "openid profile email",
})
access_token = tokens["access_token"]
uc_token = post_form("http://unity-catalog:8080/api/1.0/unity-control/auth/tokens", {
    "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
    "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
    "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
    "subject_token": tokens["id_token"],
})["access_token"]
req = urllib.request.Request("http://unity-catalog:8080/api/2.1/unity-catalog/catalogs")
req.add_header("Authorization", f"Bearer {uc_token}")
with urllib.request.urlopen(req, timeout=10) as resp:
    names = [c["name"] for c in json.loads(resp.read()).get("catalogs", [])]
expect(f"UC list catalogs WITH pietje token works (visible: {names})", "lakehouse" in names)

# 3. S3 anonymous list bucket -> denied
try:
    urllib.request.urlopen("http://seaweedfs-s3:8333/lakehouse?list-type=2", timeout=10)
    expect("S3 anonymous ListObjects is denied", False)
except urllib.error.HTTPError as e:
    expect(f"S3 anonymous ListObjects is denied (HTTP {e.code})", e.code in (401, 403))

# 4. S3 anonymous PUT -> denied
try:
    req = urllib.request.Request("http://seaweedfs-s3:8333/lakehouse/hack.txt", data=b"x", method="PUT")
    urllib.request.urlopen(req, timeout=10)
    expect("S3 anonymous PutObject is denied", False)
except urllib.error.HTTPError as e:
    expect(f"S3 anonymous PutObject is denied (HTTP {e.code})", e.code in (401, 403))

# 5. S3 with pietje's OIDC bearer token -> allowed (SeaweedFS supports direct bearer auth)
try:
    req = urllib.request.Request("http://seaweedfs-s3:8333/lakehouse?list-type=2")
    req.add_header("Authorization", f"Bearer {access_token}")
    with urllib.request.urlopen(req, timeout=10) as resp:
        expect(f"S3 ListObjects WITH pietje bearer token works (HTTP {resp.status})", resp.status == 200)
except urllib.error.HTTPError as e:
    expect(f"S3 ListObjects WITH pietje bearer token works (HTTP {e.code})", False)

# 6. S3 bearer PUT outside lakehouse bucket -> denied by policy
try:
    req = urllib.request.Request("http://seaweedfs-s3:8333/otherbucket/hack.txt", data=b"x", method="PUT")
    req.add_header("Authorization", f"Bearer {access_token}")
    urllib.request.urlopen(req, timeout=10)
    expect("S3 PutObject outside lakehouse bucket is denied", False)
except urllib.error.HTTPError as e:
    expect(f"S3 PutObject outside lakehouse bucket is denied (HTTP {e.code})", e.code in (401, 403))

print("\nRESULT:", "ALL PASS" if not failures else f"{len(failures)} FAILURES")
sys.exit(1 if failures else 0)
