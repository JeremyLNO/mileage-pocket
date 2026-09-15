#!/usr/bin/env python3
"""Set the objective submission metadata: category and age rating.

Deliberately does NOT touch the review contact: that needs a phone number, and inventing one
would send the reviewer to a number nobody answers.

    python3 tools/asc_review_metadata.py
"""
import os
import json, os, sys, time, urllib.error, urllib.request
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

PRIMARY = "FINANCE"
SECONDARY = "BUSINESS"

# A mileage log shows a map and a number. Nothing here is rated, and every one of these has
# to be answered explicitly — a null is "unanswered", which blocks submission just as surely
# as a wrong answer would.
AGE_RATING = {
    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
    "contests": "NONE",
    "gamblingSimulated": "NONE",
    "gunsOrOtherWeapons": "NONE",
    "horrorOrFearThemes": "NONE",
    "matureOrSuggestiveThemes": "NONE",
    "medicalOrTreatmentInformation": "NONE",
    "profanityOrCrudeHumor": "NONE",
    "sexualContentGraphicAndNudity": "NONE",
    "sexualContentOrNudity": "NONE",
    "violenceCartoonOrFantasy": "NONE",
    "violenceRealistic": "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    "advertising": False,
    "gambling": False,
    "healthOrWellnessTopics": False,
    "lootBox": False,
    "messagingAndChat": False,
    "parentalControls": False,
    "socialMedia": False,
    "unrestrictedWebAccess": False,
    "userGeneratedContent": False,
    # Required since 2026: the app does nothing to verify a user's age, because there is
    # nothing here that depends on it.
    "ageAssurance": False,
    "socialMediaAgeRestricted": False,
    "kidsAgeBand": None,
}


def token():
    return jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        open(KEY_PATH).read(), algorithm="ES256", headers={"kid": KEY_ID})


def request(method, path, body=None, tolerate=()):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as response:
            payload = response.read()
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:700]
        if error.code in tolerate:
            return {"error": detail, "code": error.code}
        raise SystemExit(f"{method} {path} -> {error.code}\n{detail}")


def main():
    info = request("GET", f"/v1/apps/{APP_ID}/appInfos")["data"][0]
    request("PATCH", f"/v1/appInfos/{info['id']}", {
        "data": {
            "type": "appInfos", "id": info["id"],
            "relationships": {
                "primaryCategory": {"data": {"type": "appCategories", "id": PRIMARY}},
                "secondaryCategory": {"data": {"type": "appCategories", "id": SECONDARY}},
            },
        }
    })
    print(f"categories: {PRIMARY} / {SECONDARY}")

    # The declaration hangs off appInfo, not off the version: it moved, and the old path
    # answers 404 rather than saying so.
    declaration = request("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    request("PATCH", f"/v1/ageRatingDeclarations/{declaration['id']}", {
        "data": {"type": "ageRatingDeclarations", "id": declaration["id"], "attributes": AGE_RATING}
    })
    answered = request("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]["attributes"]
    unanswered = [k for k, v in answered.items() if v is None and k not in {"kidsAgeBand", "developerAgeRatingInfoUrl", "ageAssurance", "socialMediaAgeRestricted"}]
    print("age rating:", "all answered" if not unanswered else f"still unanswered: {unanswered}")

    after = request("GET", f"/v1/appInfos/{info['id']}?include=primaryCategory,secondaryCategory")
    for item in after.get("included", []):
        print("  category:", item["id"])


if __name__ == "__main__":
    main()
