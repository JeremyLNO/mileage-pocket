#!/usr/bin/env python3
"""Merge keys into Resources/Localizable.xcstrings.

Reads a JSON object {key: {lang: value}} on stdin. Existing keys are updated, so the same
file can be replayed. Every key must carry all six languages: a key that ships with only
English is a key that renders as a raw identifier for five sixths of the store fronts.
"""
import json, sys, pathlib

LANGS = ["de", "en", "es", "fr", "it", "pt"]
path = pathlib.Path(__file__).resolve().parent.parent / "Resources" / "Localizable.xcstrings"
doc = json.loads(path.read_text())
incoming = json.load(sys.stdin)

for key, values in incoming.items():
    missing = [l for l in LANGS if l not in values]
    if missing:
        sys.exit(f"{key}: missing {missing}")
    doc["strings"][key] = {
        "extractionState": "manual",
        "localizations": {
            lang: {"stringUnit": {"state": "translated", "value": values[lang]}}
            for lang in LANGS
        },
    }

doc["strings"] = dict(sorted(doc["strings"].items()))
path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
print(f"{len(incoming)} keys merged, {len(doc['strings'])} total")
