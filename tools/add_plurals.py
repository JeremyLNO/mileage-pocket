#!/usr/bin/env python3
"""Merge plural entries into Resources/Localizable.xcstrings.

Reads {key: {lang: {"one": …, "other": …}}} on stdin. A counted string written as a flat
format renders "1 trips" — in six languages, including the PDF handed to an accountant — so
anything interpolating a count belongs here rather than in `add_strings.py`.

French CLDR puts 0 in `one`, which is what "0 trajet" wants; the other five use it for 1.
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
            lang: {
                "variations": {
                    "plural": {
                        form: {"stringUnit": {"state": "translated", "value": values[lang][form]}}
                        for form in ("one", "other")
                    }
                }
            }
            for lang in LANGS
        },
    }

doc["strings"] = dict(sorted(doc["strings"].items()))
path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
print(f"{len(incoming)} plural keys merged")
