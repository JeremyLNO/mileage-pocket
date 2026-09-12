#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Verify Resources/Localizable.xcstrings against tools/strings_en.json.

Checks:
  1. the catalogue is valid JSON with the expected envelope
  2. its key set is exactly the key set of strings_en.json
  3. every key carries all expected languages
  4. for every key / language / plural variation, the ORDERED list of format
     specifiers is identical to the English source string's
  5. no empty value

Exit code 1 on any failure.

    python3 tools/check_xcstrings.py [path/to/Localizable.xcstrings]
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(HERE, "strings_en.json")
DEFAULT_CATALOGUE = os.path.join(ROOT, "Resources", "Localizable.xcstrings")

EXPECTED_LANGUAGES = ["en", "fr", "es", "de", "it", "pt"]

SPECIFIER = re.compile(
    r"%(?:%|(?:\d+\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(?:hh|h|ll|l|q|L|z|j|t)?[@a-zA-Z])"
)


def specifiers(value):
    return SPECIFIER.findall(value)


def values_of(localization):
    """Yield (label, value) for a localization node (plain or with variations)."""
    if "stringUnit" in localization:
        yield ("", localization["stringUnit"].get("value"))
    variations = localization.get("variations", {})
    for kind, cases in variations.items():
        for case, node in cases.items():
            if "stringUnit" in node:
                yield ("%s/%s" % (kind, case), node["stringUnit"].get("value"))
            else:
                for label, value in values_of(node):
                    yield ("%s/%s/%s" % (kind, case, label), value)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CATALOGUE
    errors = []

    with open(SOURCE, encoding="utf-8") as handle:
        english = json.load(handle)

    # 1. valid JSON
    try:
        with open(path, encoding="utf-8") as handle:
            catalogue = json.load(handle)
    except Exception as exc:  # noqa: BLE001
        print("FAIL  1. valid JSON: %s" % exc)
        return 1
    print("OK    1. valid JSON (%s)" % os.path.relpath(path, ROOT))

    if catalogue.get("version") != "1.0":
        errors.append("version is %r, expected \"1.0\"" % catalogue.get("version"))
    if catalogue.get("sourceLanguage") != "en":
        errors.append("sourceLanguage is %r, expected \"en\""
                      % catalogue.get("sourceLanguage"))
    strings = catalogue.get("strings")
    if not isinstance(strings, dict):
        print("FAIL  catalogue has no \"strings\" object")
        return 1

    # 2. same key set
    missing = sorted(set(english) - set(strings))
    surplus = sorted(set(strings) - set(english))
    for key in missing:
        errors.append("missing key: %s" % key)
    for key in surplus:
        errors.append("unknown key: %s" % key)
    if missing or surplus:
        print("FAIL  2. key set: %d missing, %d surplus" % (len(missing), len(surplus)))
    else:
        print("OK    2. key set: %d keys, identical to strings_en.json" % len(english))

    # 3. all languages present
    lang_errors = 0
    for key in sorted(set(english) & set(strings)):
        localizations = strings[key].get("localizations", {})
        absent = [lang for lang in EXPECTED_LANGUAGES if lang not in localizations]
        unexpected = [lang for lang in localizations if lang not in EXPECTED_LANGUAGES]
        for lang in absent:
            errors.append("%s: missing language %s" % (key, lang))
            lang_errors += 1
        for lang in unexpected:
            errors.append("%s: unexpected language %s" % (key, lang))
            lang_errors += 1
    if lang_errors:
        print("FAIL  3. languages: %d problems" % lang_errors)
    else:
        print("OK    3. languages: %d x %s = %d units"
              % (len(english), len(EXPECTED_LANGUAGES),
                 len(english) * len(EXPECTED_LANGUAGES)))

    # 4. format specifiers, 5. non-empty values
    spec_errors = 0
    empty_errors = 0
    checked = 0
    for key in sorted(set(english) & set(strings)):
        reference = specifiers(english[key])
        localizations = strings[key].get("localizations", {})
        for lang in EXPECTED_LANGUAGES:
            localization = localizations.get(lang)
            if localization is None:
                continue
            pairs = list(values_of(localization))
            if not pairs:
                errors.append("%s / %s: no string unit" % (key, lang))
                empty_errors += 1
                continue
            for label, value in pairs:
                where = "%s / %s%s" % (key, lang, (" [%s]" % label) if label else "")
                if not value or not value.strip():
                    errors.append("%s: empty value" % where)
                    empty_errors += 1
                    continue
                checked += 1
                found = specifiers(value)
                if found != reference:
                    errors.append("%s: specifiers %s, expected %s (value: %r)"
                                  % (where, found, reference, value))
                    spec_errors += 1

    if spec_errors:
        print("FAIL  4. format specifiers: %d mismatches" % spec_errors)
    else:
        print("OK    4. format specifiers: %d values checked, all match English"
              % checked)
    if empty_errors:
        print("FAIL  5. non-empty values: %d empty" % empty_errors)
    else:
        print("OK    5. non-empty values: none empty")

    if errors:
        print("")
        print("%d problem(s):" % len(errors))
        for problem in errors[:60]:
            print("  - %s" % problem)
        if len(errors) > 60:
            print("  ... and %d more" % (len(errors) - 60))
        return 1

    print("")
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
