#!/usr/bin/env python3
"""Produce the signed rule-pack bundle the app's updater fetches.

Reads every Resources/MileageRules/<ISO>/<version>.json, concatenates them into one JSON
array, signs those exact bytes with the Ed25519 private key, and writes a bundle the app
verifies against the public key compiled into RulePackVerifier.swift.

The private key lives OUTSIDE this repository, at
~/crazybee-license-signing/mileage_rules_ed25519_private.key, and must never be committed.

    python3 tools/sign_rule_packs.py [output.json]
"""
import base64
import glob
import json
import os
import sys

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKS = os.path.join(ROOT, "Resources", "MileageRules")
KEY_PATH = os.path.expanduser("~/crazybee-license-signing/mileage_rules_ed25519_private.key")


def load_key():
    if not os.path.exists(KEY_PATH):
        sys.exit(f"private key not found at {KEY_PATH}")
    raw = base64.b64decode(open(KEY_PATH).read().strip())
    return Ed25519PrivateKey.from_private_bytes(raw)


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "mileage-rules-v1.json")
    files = sorted(glob.glob(os.path.join(PACKS, "*", "*.json")))
    if not files:
        sys.exit("no rule packs found")

    packs = [json.load(open(path)) for path in files]
    # separators matter: the signature covers these exact bytes, so the payload must be
    # serialised identically here and nowhere re-encoded before it is verified.
    payload = json.dumps(packs, separators=(",", ":"), ensure_ascii=False, sort_keys=True).encode("utf-8")

    key = load_key()
    signature = key.sign(payload)

    version = max(pack["version"] for pack in packs)
    bundle = {
        "version": version,
        "payload": base64.b64encode(payload).decode(),
        "signature": base64.b64encode(signature).decode(),
    }

    os.makedirs(os.path.dirname(output), exist_ok=True)
    with open(output, "w") as handle:
        json.dump(bundle, handle)

    print(f"Signed {len(packs)} rule packs -> {output} (version {version}, {len(payload)} bytes)")
    print("public key:", base64.b64encode(key.public_key().public_bytes_raw()).decode())


if __name__ == "__main__":
    main()
