#!/usr/bin/env python3
"""Reports whether the CarPlay entitlement has landed on the Mileage Pocket App ID.

⚠️ This can announce a yes, never a no. A granted entitlement shows up as a capability on
the App ID; a refusal leaves no trace in the API at all and arrives only by email. Reading
"no CarPlay capability" as a refusal would be reading silence as an answer.

    python3 tools/check-carplay-entitlement.py
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

KEY_ID = "88BAZ9XND3"
ISSUER = "***ASC-ISSUER-ID-RETIRE***"
KEY_PATH = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_88BAZ9XND3.p8")
BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "Mileage.lno.company"
# What the App ID carried when the request was made, on 2026-09-14. Read from the API, not
# assumed: the first attempt at this passed a `limit` the relationship refuses, the call
# failed, and an empty list read exactly like "no capabilities at all".
BASELINE = {"APP_GROUPS", "ICLOUD", "IN_APP_PURCHASE", "PUSH_NOTIFICATIONS"}
# Granted 2026-09-14 and enabled on the App ID the same evening. Kept as a guard: removing
# the capability (or a profile regenerated without it) fails code signing, not the build.
EXPECTED_CARPLAY = "CARPLAY_DRIVING_TASK"


def token():
    return jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        open(KEY_PATH).read(), algorithm="ES256", headers={"kid": KEY_ID})


def get(path):
    req = urllib.request.Request(BASE + path, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        raise SystemExit(f"GET {path} -> {error.code}\n{error.read().decode()[:400]}")


def main():
    ids = get("/v1/bundleIds?limit=200")
    match = next((b for b in ids["data"] if b["attributes"]["identifier"] == BUNDLE_ID), None)
    if match is None:
        raise SystemExit(f"{BUNDLE_ID} not found in this team")

    capabilities = get(f"/v1/bundleIds/{match['id']}/bundleIdCapabilities")
    current = {c["attributes"]["capabilityType"] for c in capabilities["data"]}
    new = sorted(current - BASELINE)

    if EXPECTED_CARPLAY in current:
        print(f"{EXPECTED_CARPLAY} is enabled on {BUNDLE_ID}.")
        return 0
    if new:
        print("capabilities changed, but not the CarPlay one:", new)
        return 1
    print(f"{EXPECTED_CARPLAY} is NOT on {BUNDLE_ID} — the entitlement in the app will fail to sign.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
