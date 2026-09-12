#!/usr/bin/env python3
"""Set the App Store name and subtitle of Mileage Pocket in every shipped language.

The App Store name is capped at 30 characters, so a tagline cannot live inside it — the
subtitle (also 30) is the line that shows directly under the name on the store, which is
where a baseline belongs. Lengths are checked here before anything is sent: the API's error
for an over-long value is laconic.

    python3 tools/asc_listing.py [--dry-run]
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
APP_ID = "6811426601"
BASE = "https://api.appstoreconnect.apple.com"

NAME = "Mileage Pocket"

# locale -> subtitle. Each is <= 30 characters; the script refuses to send otherwise.
SUBTITLES = {
    "en-US": "Business mileage, simplified",
    "fr-FR": "Frais kilométriques simplifiés",
    "es-ES": "Kilometraje laboral, simple",
    "de-DE": "Fahrtkosten, einfach erfasst",
    "it": "Rimborsi chilometrici facili",
    "pt-PT": "Quilometragem simplificada",
}

PRIVACY_URL = "https://www.crazybeelabs.com/legal/apps"


def token():
    key = open(KEY_PATH).read()
    return jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:600]
        raise SystemExit(f"{method} {path} -> {error.code}\n{detail}")


def main():
    dry_run = "--dry-run" in sys.argv

    for locale, subtitle in SUBTITLES.items():
        if len(NAME) > 30:
            raise SystemExit(f"name too long: {len(NAME)}")
        if len(subtitle) > 30:
            raise SystemExit(f"subtitle too long for {locale}: {len(subtitle)} chars — {subtitle!r}")
    print("lengths OK:", {locale: len(value) for locale, value in SUBTITLES.items()})
    if dry_run:
        return

    # Relations come back null without include=, so the localisations are read explicitly.
    infos = request("GET", f"/v1/apps/{APP_ID}/appInfos")
    app_info_id = infos["data"][0]["id"]

    existing = request("GET", f"/v1/appInfos/{app_info_id}/appInfoLocalizations")
    by_locale = {item["attributes"]["locale"]: item for item in existing.get("data", [])}
    print("existing locales:", sorted(by_locale))

    for locale, subtitle in SUBTITLES.items():
        attributes = {"name": NAME, "subtitle": subtitle, "privacyPolicyUrl": PRIVACY_URL}
        if locale in by_locale:
            request("PATCH", f"/v1/appInfoLocalizations/{by_locale[locale]['id']}", {
                "data": {"type": "appInfoLocalizations", "id": by_locale[locale]["id"], "attributes": attributes}
            })
            print(f"updated {locale}: {subtitle}")
        else:
            request("POST", "/v1/appInfoLocalizations", {
                "data": {
                    "type": "appInfoLocalizations",
                    "attributes": {**attributes, "locale": locale},
                    "relationships": {"appInfo": {"data": {"type": "appInfos", "id": app_info_id}}},
                }
            })
            print(f"created {locale}: {subtitle}")

    # Read back rather than trusting a silent success.
    after = request("GET", f"/v1/appInfos/{app_info_id}/appInfoLocalizations")
    for item in sorted(after.get("data", []), key=lambda entry: entry["attributes"]["locale"]):
        attributes = item["attributes"]
        print(f"  {attributes['locale']:>6}  {attributes['name']} — {attributes.get('subtitle')}")


if __name__ == "__main__":
    main()
