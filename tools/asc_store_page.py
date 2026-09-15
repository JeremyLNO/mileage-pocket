#!/usr/bin/env python3
"""Fill the App Store page: description, keywords, promotional text, screenshots.

The listing was entirely empty in all six languages — no description, no keywords, no
images — which is the one state an app cannot be submitted from. Texts live in
`tools/store/copy.json`; screenshots come from `tools/screenshots.sh`.

    python3 tools/asc_store_page.py [--dry-run] [--skip-screenshots]

Every write is read back afterwards: App Store Connect accepts an upload and then fails the
asset asynchronously, so "no error" is not "it is there".
"""
import hashlib
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
APP_ID = "6811426601"
BASE = "https://api.appstoreconnect.apple.com"

ROOT = pathlib.Path(__file__).resolve().parent.parent
COPY = json.loads((ROOT / "tools" / "store" / "copy.json").read_text())
SHOTS = ROOT / "docs" / "screenshots"
# 1290 × 2796. Apple accepts this one size for every modern iPhone.
DISPLAY_TYPE = "APP_IPHONE_67"

LIMITS = {"description": 4000, "keywords": 100, "promotionalText": 170}


def token():
    return jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        open(KEY_PATH).read(),
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )


def request(method, path, body=None, raw=None, headers=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    url = path if path.startswith("http") else BASE + path
    sent = {"Authorization": "Bearer " + token()}
    sent.update(headers or {"Content-Type": "application/json"})
    if raw is not None:
        sent.pop("Authorization", None)   # upload operations are pre-signed
        sent.update(headers or {})
    req = urllib.request.Request(url, data=data, method=method, headers=sent)
    try:
        with urllib.request.urlopen(req) as response:
            payload = response.read()
            return json.loads(payload) if payload and response.headers.get_content_type() == "application/json" else {}
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {url} -> {error.code}\n{error.read().decode()[:800]}")


def editable_version():
    versions = request("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=10")
    for item in versions["data"]:
        if item["attributes"]["appStoreState"] in {
            "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
            "WAITING_FOR_REVIEW", "INVALID_BINARY",
        }:
            return item
    raise SystemExit("no editable App Store version")


def upload_screenshots(localization_id, locale):
    sets = request("GET", f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")
    existing = next(
        (s for s in sets["data"] if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None
    )
    if existing:
        shots = request("GET", f"/v1/appScreenshotSets/{existing['id']}/appScreenshots")
        for shot in shots["data"]:
            request("DELETE", f"/v1/appScreenshots/{shot['id']}")
        set_id = existing["id"]
    else:
        created = request("POST", "/v1/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
                    }
                },
            }
        })
        set_id = created["data"]["id"]

    for index, path in enumerate(sorted(SHOTS.glob("*.png"))):
        blob = path.read_bytes()
        reserved = request("POST", "/v1/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileSize": len(blob), "fileName": path.name},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
            }
        })
        shot_id = reserved["data"]["id"]
        for operation in reserved["data"]["attributes"]["uploadOperations"]:
            chunk = blob[operation["offset"]: operation["offset"] + operation["length"]]
            headers = {h["name"]: h["value"] for h in operation["requestHeaders"]}
            request(operation["method"], operation["url"], raw=chunk, headers=headers)
        request("PATCH", f"/v1/appScreenshots/{shot_id}", {
            "data": {
                "type": "appScreenshots",
                "id": shot_id,
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()},
            }
        })
        print(f"    {locale}: {path.name}")

    # Accepted is not delivered: the asset is processed after the upload returns.
    for _ in range(30):
        shots = request("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots")
        states = [s["attributes"]["assetDeliveryState"]["state"] for s in shots["data"]]
        if all(state == "COMPLETE" for state in states):
            return len(states)
        if any(state == "FAILED" for state in states):
            raise SystemExit(f"{locale}: an asset failed processing — {states}")
        time.sleep(4)
    raise SystemExit(f"{locale}: assets still processing after two minutes — {states}")


def main():
    dry_run = "--dry-run" in sys.argv
    skip_shots = "--skip-screenshots" in sys.argv

    for locale, copy in COPY.items():
        for field, limit in LIMITS.items():
            if len(copy[field]) > limit:
                raise SystemExit(f"{locale}.{field}: {len(copy[field])} > {limit}")
    shots = sorted(SHOTS.glob("*.png"))
    print("copy within limits;", len(shots), "screenshots:", ", ".join(p.name for p in shots))
    if not shots and not skip_shots:
        raise SystemExit("no screenshots — run tools/screenshots.sh first")
    if dry_run:
        return

    version = editable_version()
    print("version", version["attributes"]["versionString"], version["attributes"]["appStoreState"])

    localizations = request("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    by_locale = {item["attributes"]["locale"]: item for item in localizations["data"]}

    for locale, copy in COPY.items():
        attributes = {
            "description": copy["description"],
            "keywords": copy["keywords"],
            "promotionalText": copy["promotionalText"],
        }
        if locale in by_locale:
            localization_id = by_locale[locale]["id"]
            request("PATCH", f"/v1/appStoreVersionLocalizations/{localization_id}", {
                "data": {"type": "appStoreVersionLocalizations", "id": localization_id, "attributes": attributes}
            })
        else:
            created = request("POST", "/v1/appStoreVersionLocalizations", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {**attributes, "locale": locale},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}},
                }
            })
            localization_id = created["data"]["id"]
        print(f"  {locale}: text set")
        if not skip_shots:
            count = upload_screenshots(localization_id, locale)
            print(f"  {locale}: {count} screenshots COMPLETE")

    # Read back, because a silent success here is the expensive kind.
    after = request("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    print("\nRead back:")
    for item in sorted(after["data"], key=lambda entry: entry["attributes"]["locale"]):
        a = item["attributes"]
        sets = request("GET", f"/v1/appStoreVersionLocalizations/{item['id']}/appScreenshotSets?include=appScreenshots")
        total = sum(len(s["relationships"]["appScreenshots"]["data"]) for s in sets["data"])
        print(f"  {a['locale']:>6}  description {len(a.get('description') or ''):4d}  "
              f"keywords {len(a.get('keywords') or ''):3d}  screenshots {total}")


if __name__ == "__main__":
    main()
