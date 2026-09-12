#!/usr/bin/env python3
"""Validateur des fichiers de barème kilométrique (Resources/MileageRules/<ISO>/<version>.json).

Vérifie :
  - JSON valide, champs obligatoires présents
  - distanceUnit ∈ {kilometers, miles}
  - vehicleTypes ⊂ {car, motorcycle, moped, bicycle, van, electricCar}
  - fuelTypes ⊂ {petrol, diesel, hybrid, electric, other} ou null
  - bandMode ∈ {marginal, whole}
  - un `constant` non nul n'a de sens qu'avec bandMode == "whole"
  - bandes contiguës et croissantes, première fromDistance == 0, dernière toDistance == null
  - aucun rate <= 0 ; rate et constant sont des chaînes décodables en Decimal
  - sourceURL en https
  - lastVerified <= TODAY, dates au format YYYY-MM-DD
  - cohérence country / nom du dossier, version / nom du fichier
"""

import datetime
import decimal
import glob
import json
import os
import sys

TODAY = datetime.date(2026, 9, 12)
# Lives in tools/ rather than beside the packs: Resources/MileageRules is a blue folder
# reference copied wholesale into the app bundle, and a build script has no business
# shipping inside a signed iOS app.
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources", "MileageRules")

UNITS = {"kilometers", "miles"}
VEHICLES = {"car", "motorcycle", "moped", "bicycle", "van", "electricCar"}
FUELS = {"petrol", "diesel", "hybrid", "electric", "other"}
MODES = {"marginal", "whole"}

errors = []
warnings = []


def err(path, msg):
    errors.append(f"{os.path.relpath(path, ROOT)}: {msg}")


def warn(path, msg):
    warnings.append(f"{os.path.relpath(path, ROOT)}: {msg}")


def parse_date(path, field, value, required=True):
    if value is None:
        if required:
            err(path, f"{field} manquant")
        return None
    try:
        return datetime.date.fromisoformat(value)
    except (TypeError, ValueError):
        err(path, f"{field} n'est pas une date YYYY-MM-DD: {value!r}")
        return None


def check_bands(path, label, bands, mode):
    if not isinstance(bands, list) or not bands:
        err(path, f"{label}: bands vide ou absent")
        return
    if bands[0].get("fromDistance") != 0:
        err(path, f"{label}: première fromDistance = {bands[0].get('fromDistance')!r}, attendu 0")
    if bands[-1].get("toDistance") is not None:
        err(path, f"{label}: dernière toDistance = {bands[-1].get('toDistance')!r}, attendu null")

    for i, b in enumerate(bands):
        tag = f"{label}[{i}]"
        frm, to = b.get("fromDistance"), b.get("toDistance")

        if not isinstance(frm, (int, float)) or frm < 0:
            err(path, f"{tag}: fromDistance invalide ({frm!r})")
        if to is not None:
            if not isinstance(to, (int, float)):
                err(path, f"{tag}: toDistance invalide ({to!r})")
            elif isinstance(frm, (int, float)) and to <= frm:
                err(path, f"{tag}: toDistance ({to}) <= fromDistance ({frm})")

        rate = b.get("rate")
        if not isinstance(rate, str):
            err(path, f"{tag}: rate doit être une chaîne, trouvé {type(rate).__name__}")
        else:
            try:
                if decimal.Decimal(rate) <= 0:
                    err(path, f"{tag}: rate <= 0 ({rate})")
            except decimal.InvalidOperation:
                err(path, f"{tag}: rate non décimal ({rate!r})")

        const = b.get("constant", "__missing__")
        if const == "__missing__":
            err(path, f"{tag}: champ constant absent")
        elif const is not None:
            if not isinstance(const, str):
                err(path, f"{tag}: constant doit être une chaîne ou null, trouvé {type(const).__name__}")
            else:
                try:
                    decimal.Decimal(const)
                except decimal.InvalidOperation:
                    err(path, f"{tag}: constant non décimal ({const!r})")
            if mode != "whole":
                err(path, f"{tag}: constant non nul ({const!r}) avec bandMode={mode!r} — "
                          f"un terme additif n'a de sens qu'en bandMode 'whole'")

        # contiguïté
        if i > 0:
            prev_to = bands[i - 1].get("toDistance")
            if prev_to is None:
                err(path, f"{tag}: une bande suit une bande ouverte (toDistance null)")
            elif prev_to != frm:
                err(path, f"{tag}: rupture de contiguïté — bande précédente finit à {prev_to}, "
                          f"celle-ci commence à {frm}")


def check_file(path):
    try:
        with open(path) as f:
            doc = json.load(f)
    except json.JSONDecodeError as e:
        err(path, f"JSON invalide: {e}")
        return

    for field in ("country", "version", "validFrom", "validUntil", "currencyCode",
                  "distanceUnit", "source", "sourceURL", "lastVerified", "schemes"):
        if field not in doc:
            err(path, f"champ obligatoire manquant: {field}")

    iso_dir = os.path.basename(os.path.dirname(path))
    if doc.get("country") != iso_dir:
        err(path, f"country={doc.get('country')!r} ≠ dossier {iso_dir!r}")

    version_file = os.path.basename(path)[:-len(".json")]
    if doc.get("version") != version_file:
        err(path, f"version={doc.get('version')!r} ≠ nom de fichier {version_file!r}")

    if doc.get("distanceUnit") not in UNITS:
        err(path, f"distanceUnit={doc.get('distanceUnit')!r} hors {sorted(UNITS)}")

    cur = doc.get("currencyCode")
    if not isinstance(cur, str) or len(cur) != 3 or not cur.isupper():
        err(path, f"currencyCode invalide: {cur!r}")

    url = doc.get("sourceURL")
    if not isinstance(url, str) or not url.startswith("https://"):
        err(path, f"sourceURL non https: {url!r}")

    vf = parse_date(path, "validFrom", doc.get("validFrom"))
    vu = parse_date(path, "validUntil", doc.get("validUntil"), required=False)
    lv = parse_date(path, "lastVerified", doc.get("lastVerified"))

    if lv and lv > TODAY:
        err(path, f"lastVerified ({lv}) postérieur à {TODAY}")
    if vf and vu and vu <= vf:
        err(path, f"validUntil ({vu}) <= validFrom ({vf})")

    schemes = doc.get("schemes")
    if not isinstance(schemes, list) or not schemes:
        err(path, "schemes vide ou absent")
        return

    seen_ids = set()
    for s in schemes:
        sid = s.get("id")
        if not isinstance(sid, str) or not sid:
            err(path, f"scheme sans id valide: {sid!r}")
            sid = "?"
        if sid in seen_ids:
            err(path, f"id de scheme dupliqué: {sid!r}")
        seen_ids.add(sid)

        mode = s.get("bandMode")
        if mode not in MODES:
            err(path, f"scheme {sid}: bandMode={mode!r} hors {sorted(MODES)}")

        vt = s.get("vehicleTypes")
        if not isinstance(vt, list) or not vt:
            err(path, f"scheme {sid}: vehicleTypes vide ou absent")
        else:
            bad = set(vt) - VEHICLES
            if bad:
                err(path, f"scheme {sid}: vehicleTypes hors liste: {sorted(bad)}")

        ft = s.get("fuelTypes", "__missing__")
        if ft == "__missing__":
            err(path, f"scheme {sid}: champ fuelTypes absent")
        elif ft is not None:
            if not isinstance(ft, list):
                err(path, f"scheme {sid}: fuelTypes doit être une liste ou null")
            else:
                bad = set(ft) - FUELS
                if bad:
                    err(path, f"scheme {sid}: fuelTypes hors liste: {sorted(bad)}")

        check_bands(path, f"scheme {sid} / bands (repli)", s.get("bands"), mode)

        pb = s.get("powerBands", "__missing__")
        if pb == "__missing__":
            err(path, f"scheme {sid}: champ powerBands absent")
        elif pb is not None:
            if not isinstance(pb, list) or not pb:
                err(path, f"scheme {sid}: powerBands doit être une liste non vide ou null")
            else:
                prev_max = None
                for j, p in enumerate(pb):
                    lo, hi = p.get("minPower"), p.get("maxPower")
                    if j == 0 and lo is not None:
                        warn(path, f"scheme {sid}: premier powerBand a minPower={lo!r} (null attendu pour couvrir le bas)")
                    if j == len(pb) - 1 and hi is not None:
                        warn(path, f"scheme {sid}: dernier powerBand a maxPower={hi!r} (null attendu pour couvrir le haut)")
                    if lo is not None and hi is not None and hi < lo:
                        err(path, f"scheme {sid} powerBands[{j}]: maxPower ({hi}) < minPower ({lo})")
                    if prev_max is not None and lo is not None and lo <= prev_max:
                        err(path, f"scheme {sid} powerBands[{j}]: chevauchement — "
                                  f"minPower {lo} <= maxPower précédent {prev_max}")
                    prev_max = hi if hi is not None else prev_max
                    check_bands(path, f"scheme {sid} / powerBands[{j}]", p.get("bands"), mode)


def main():
    files = sorted(glob.glob(os.path.join(ROOT, "*", "*.json")))
    if not files:
        print("Aucun fichier trouvé.")
        return 1

    for path in files:
        check_file(path)

    print(f"Fichiers examinés : {len(files)}")
    for path in files:
        print(f"  - {os.path.relpath(path, ROOT)}")
    print()

    if warnings:
        print(f"AVERTISSEMENTS ({len(warnings)}) :")
        for w in warnings:
            print(f"  ! {w}")
        print()

    if errors:
        print(f"ERREURS ({len(errors)}) :")
        for e in errors:
            print(f"  x {e}")
        return 1

    print("OK — tous les fichiers passent les contrôles.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
