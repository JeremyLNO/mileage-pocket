#!/usr/bin/env python3
"""Print a build number strictly greater than every build already in App Store Connect.

TestFlight decides which build is "latest" by CFBundleVersion, not by upload time. A build
numbered below one already uploaded is installed by nobody and reported as a success by
everything — which is exactly how a fixed build can sit behind a broken one.
"""
import json
import os
import time
import urllib.request

import jwt

KEY_ID = "88BAZ9XND3"
ISSUER = "***ASC-ISSUER-ID-RETIRE***"
KEY_PATH = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_88BAZ9XND3.p8")
APP_ID = "6811426601"


def existing_build_numbers():
    token = jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
        open(KEY_PATH).read(),
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )
    url = f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={APP_ID}&limit=200"
    request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(request) as response:
        payload = json.load(response)

    numbers = []
    for build in payload.get("data", []):
        version = build["attributes"].get("version")
        try:
            numbers.append(int(version))
        except (TypeError, ValueError):
            continue
    return numbers


def main():
    timestamp = int(time.strftime("%y%m%d%H%M"))
    try:
        floor = max(existing_build_numbers(), default=0)
    except Exception:
        # Offline or refused: the timestamp alone still beats reusing a number, and the
        # upload itself will reject a duplicate.
        floor = 0
    print(max(timestamp, floor + 1))


if __name__ == "__main__":
    main()
