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

    if any("CARPLAY" in capability for capability in current):
        print("CarPlay entitlement GRANTED:", sorted(c for c in current if "CARPLAY" in c))
        return 0
    if new:
        print("capabilities changed since the request:", new)
        return 0
    print("no change — still waiting. This is not a refusal: a refusal arrives by email only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
