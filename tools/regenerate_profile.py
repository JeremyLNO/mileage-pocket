#!/usr/bin/env python3
"""Recreate an App Store provisioning profile and install it locally.

Changing a capability on an App ID **invalidates** every profile that carries it, and
`-allowProvisioningUpdates` does not rescue a profile named by
`PROVISIONING_PROFILE_SPECIFIER` under manual signing: xcodebuild reads the stale one and
fails with "doesn't include the … capability", which reads like the entitlement was never
granted. The API cannot update a profile — only delete and recreate — so that is what this
does, keeping the name so the specifier still matches.

    python3 tools/regenerate_profile.py "MileagePocket AppStore"
"""
import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

import jwt

def _asc_issuer():
    """Issuer ID App Store Connect — jamais en dur : ces dépôts sont publics.
    Ordre : $ASC_ISSUER_ID, puis ~/.appstoreconnect/issuer_id (chmod 600)."""
    value = os.environ.get("ASC_ISSUER_ID")
    if value:
        return value.strip()
    path = os.path.expanduser("~/.appstoreconnect/issuer_id")
    if os.path.exists(path):
        return open(path).read().strip()
    raise SystemExit(
        "ASC_ISSUER_ID absent : exporter la variable, ou écrire l'issuer ID dans "
        "~/.appstoreconnect/issuer_id (chmod 600). Il ne doit pas revenir dans le dépôt."
    )


KEY_ID = "88BAZ9XND3"
ISSUER = _asc_issuer()
KEY_PATH = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_88BAZ9XND3.p8")
BASE = "https://api.appstoreconnect.apple.com"

# Both locations: Xcode 16 reads the first, the toolchain still honours the second.
INSTALL_DIRS = [
    pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles",
]


def token():
    return jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        open(KEY_PATH).read(), algorithm="ES256", headers={"kid": KEY_ID})


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as response:
            payload = response.read()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {path} -> {error.code}\n{error.read().decode()[:700]}")


def install(profile):
    content = base64.b64decode(profile["attributes"]["profileContent"])
    uuid = profile["attributes"]["uuid"]
    for directory in INSTALL_DIRS:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{uuid}.mobileprovision").write_bytes(content)
    return uuid


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    name = sys.argv[1]

    profiles = request("GET", "/v1/profiles?limit=200&include=bundleId,certificates")
    existing = next((p for p in profiles["data"] if p["attributes"]["name"] == name), None)
    if existing is None:
        raise SystemExit(f"no profile named {name!r}")

    bundle_id = existing["relationships"]["bundleId"]["data"]["id"]
    certificates = [c["id"] for c in existing["relationships"]["certificates"]["data"]]
    profile_type = existing["attributes"]["profileType"]
    print(f"{name}: {existing['attributes']['profileState']} — bundle {bundle_id}, certs {certificates}")

    request("DELETE", f"/v1/profiles/{existing['id']}")
    created = request("POST", "/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": profile_type},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": c} for c in certificates]},
            },
        }
    })["data"]

    uuid = install(created)
    print(f"recreated: {created['attributes']['profileState']} uuid={uuid}")

    # Read back the entitlements the profile actually carries, rather than trusting the POST.
    content = base64.b64decode(created["attributes"]["profileContent"])
    text = content.decode("utf-8", errors="ignore")
    for needle in ["carplay-driving-task", "application-identifier", "aps-environment"]:
        print(f"  {'carries' if needle in text else 'MISSING'}: {needle}")


if __name__ == "__main__":
    main()
