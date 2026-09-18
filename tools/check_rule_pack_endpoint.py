#!/usr/bin/env python3
"""Vérifie que l'endpoint des barèmes sert quelque chose que l'app accepterait.

Un 200 ne prouve rien : l'app rejette en silence un bundle dont la signature ne passe pas,
et ce refus n'est visible nulle part — ni pour elle, ni pour l'utilisateur, ni dans les logs
du serveur. Ce script refait exactement ce que fait `RulePackUpdater.refresh()` : décoder
l'enveloppe, vérifier la signature Ed25519 détachée sur les octets du payload décodé, puis
décoder les barèmes.

La clé publique est LUE DANS LE SOURCE SWIFT, jamais recopiée ici : une clé recopiée finit
par diverger de celle qui est compilée dans l'app, et le script dirait alors « valide » d'un
bundle que l'app refuse.

    python3 tools/check_rule_pack_endpoint.py [url]
"""
import base64
import json
import pathlib
import re
import sys
import urllib.request

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_URL = "https://www.crazybeelabs.com/api/mileage-rules/v1"


def compiled_public_key() -> bytes:
    source = (ROOT / "Services/MileageRules/RulePackVerifier.swift").read_text()
    match = re.search(r'publicKeyBase64\s*=\s*"([^"]+)"', source)
    if not match:
        sys.exit("clé publique introuvable dans RulePackVerifier.swift")
    return base64.b64decode(match.group(1))


def main() -> None:
    url = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_URL
    with urllib.request.urlopen(url, timeout=20) as response:
        if response.status != 200:
            sys.exit(f"HTTP {response.status} — l'app abandonnerait ici")
        body = response.read()

    bundle = json.loads(body)
    for field in ("version", "payload", "signature"):
        if field not in bundle:
            sys.exit(f"champ « {field} » absent — l'app ne saurait pas décoder l'enveloppe")

    payload = base64.b64decode(bundle["payload"])
    signature = base64.b64decode(bundle["signature"])

    try:
        Ed25519PublicKey.from_public_bytes(compiled_public_key()).verify(signature, payload)
    except InvalidSignature:
        sys.exit("SIGNATURE REFUSÉE — l'app ignorerait ce bundle, en silence")

    # Et l'autre moitié de la preuve : `PublishedRulePackTests` fait passer une COPIE de ce
    # bundle par le décodeur Swift et la clé embarquée — ce que la crypto de Python ne peut
    # pas faire. Ce test ne vaut que si la copie est encore ce qui est servi ; sinon chacun
    # des deux est vert sur un objet différent.
    fixture = ROOT / "Tests/Fixtures/PublishedRulePacks/mileage-rules-v1.json"
    drift = None
    if fixture.exists():
        if json.loads(fixture.read_text()) != bundle:
            drift = "⚠️  DÉRIVE : la fixture des tests n'est plus ce qui est servi — regénérer avec\n      curl -s <url> -o Tests/Fixtures/PublishedRulePacks/mileage-rules-v1.json"
    else:
        drift = "⚠️  fixture absente : PublishedRulePackTests ne protège rien"

    packs = json.loads(payload)
    countries = sorted({pack["country"] for pack in packs})
    versions = sorted({pack["version"] for pack in packs})

    print(f"✅ {url}")
    print(f"   enveloppe    : version {bundle['version']}, {len(body)} octets")
    print(f"   signature    : valide pour la clé compilée dans l'app")
    print(f"   barèmes      : {len(packs)} paquets, {len(countries)} pays — {', '.join(countries)}")
    print(f"   versions     : {', '.join(versions)}")
    # L'app n'applique un paquet que s'il est PLUS RÉCENT que celui qu'elle a déjà : servir
    # la même version que celle embarquée est donc normal, et volontairement sans effet.
    print("   à savoir     : un paquet n'est appliqué que s'il est plus récent que l'embarqué")
    if drift:
        print(drift)
        sys.exit(1)
    print("   fixture      : identique à ce qui est servi (PublishedRulePackTests est à jour)")


if __name__ == "__main__":
    main()
