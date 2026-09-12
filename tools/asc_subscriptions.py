#!/usr/bin/env python3
"""
Configure les abonnements de Mileage Pocket sur App Store Connect, 100% par l'API REST.

Idempotent : relancable sans rien dupliquer. Il relit l'existant et ne cree que ce qui manque.

Sequence :
  subscriptionGroups -> subscriptions -> localizations (groupe + abos)
  -> subscriptionAvailabilities -> subscriptionPrices -> subscriptionIntroductoryOffers

Usage:
  python3 tools/asc_subscriptions.py            # tout
  python3 tools/asc_subscriptions.py --verify   # verification seule
"""
import json, os, sys, time, threading, argparse
import urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

import hashlib

import jwt

# ---------------------------------------------------------------- config

KEY_ID = os.environ.get("ASC_KEY_ID", "88BAZ9XND3")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "***ASC-ISSUER-ID-RETIRE***")
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
APP_ID = "6811426601"
BASE = "https://api.appstoreconnect.apple.com"

GROUP_REFERENCE_NAME = "Mileage Pocket"
GROUP_DISPLAY_NAME = "Mileage Pocket"
LOCALES = ["en-US", "fr-FR", "es-ES", "de-DE", "it", "pt-PT"]

REF_TERRITORY = "USA"

NAME_LIMIT = 30
DESC_LIMIT = 45

PLANS = [
    {
        "key": "monthly",
        "productId": "company.lno.mileage.monthly",
        "referenceName": "Mileage Pocket Monthly",
        "period": "ONE_MONTH",
        "ref_price": "2.99",          # USD, territoire de reference
        "nominal": "2.99",            # palier nominal force en USD et EUR
        "loc": {
            "en-US": ("Monthly",   "Unlimited tracking, reports and exports."),
            "fr-FR": ("Mensuel",   "Suivi, rapports et exports illimites."),
            "es-ES": ("Mensual",   "Viajes, informes y exportaciones ilimitados."),
            "de-DE": ("Monatlich", "Unbegrenzt erfassen, berichten, exportieren."),
            "it":    ("Mensile",   "Tracciamento, report ed export illimitati."),
            "pt-PT": ("Mensal",    "Registos, relatorios e exportacoes sem fim."),
        },
    },
    {
        "key": "annual",
        "productId": "company.lno.mileage.annual",
        "referenceName": "Mileage Pocket Annual",
        "period": "ONE_YEAR",
        "ref_price": "29.99",
        "nominal": "29.99",
        "loc": {
            "en-US": ("Annual",   "Unlimited tracking, reports and exports."),
            "fr-FR": ("Annuel",   "Suivi, rapports et exports illimites."),
            "es-ES": ("Anual",    "Viajes, informes y exportaciones ilimitados."),
            "de-DE": ("Jahrlich", "Unbegrenzt erfassen, berichten, exportieren."),
            "it":    ("Annuale",  "Tracciamento, report ed export illimitati."),
            "pt-PT": ("Anual",    "Registos, relatorios e exportacoes sem fim."),
        },
    },
]

# accents reels (ecrits en echappement pour rester ASCII dans le fichier)
ACCENTED = {
    ("monthly", "fr-FR"): ("Mensuel", "Suivi, rapports et exports illimités."),
    ("annual",  "fr-FR"): ("Annuel",  "Suivi, rapports et exports illimités."),
    ("monthly", "de-DE"): ("Monatlich", "Unbegrenzt erfassen, berichten, exportieren."),
    ("annual",  "de-DE"): ("Jährlich", "Unbegrenzt erfassen, berichten, exportieren."),
    ("monthly", "pt-PT"): ("Mensal", "Registos, relatórios e exportações sem fim."),
    ("annual",  "pt-PT"): ("Anual",  "Registos, relatórios e exportações sem fim."),
}
for p in PLANS:
    for loc in list(p["loc"]):
        if (p["key"], loc) in ACCENTED:
            p["loc"][loc] = ACCENTED[(p["key"], loc)]

REVIEW_NOTE = (
    "Mileage Pocket Premium unlocks unlimited trip tracking, unlimited reports "
    "and CSV/PDF exports. Both plans unlock exactly the same features; only the "
    "billing period differs. Each plan starts with a 3-day free trial."
)

# Devises dont on force le palier nominal exact (les deux prix de reference
# donnes par la fiche produit : 2,99 $ / 2,99 EUR et 29,99 $ / 29,99 EUR).
# L'equalization Apple fait deriver 29.99 USD -> 34.99 EUR, ce qui n'est pas
# le prix voulu : on corrige explicitement ces territoires.
NOMINAL_CURRENCIES = {"USD", "EUR"}

INTRO_OFFER = {"offerMode": "FREE_TRIAL", "duration": "THREE_DAYS", "numberOfPeriods": 1}

# ---------------------------------------------------------------- http

_key_cache = None
_print_lock = threading.Lock()


def log(*a):
    with _print_lock:
        print(*a, flush=True)


def token():
    global _key_cache
    if _key_cache is None:
        _key_cache = open(KEY_PATH).read()
    return jwt.encode(
        {"iss": ISSUER_ID, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        _key_cache, algorithm="ES256", headers={"kid": KEY_ID},
    )


class ApiError(Exception):
    def __init__(self, status, body, path):
        self.status, self.body, self.path = status, body, path
        super().__init__(f"HTTP {status} on {path}: {body[:600]}")


def request(method, path, payload=None, retries=6):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(payload).encode() if payload is not None else None
    delay = 2.0
    last = None
    for attempt in range(retries):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + token())
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            if e.code == 429 or e.code >= 500:
                last = ApiError(e.code, body, path)
                time.sleep(delay)
                delay = min(delay * 2, 60)
                continue
            raise ApiError(e.code, body, path)
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last = ApiError(0, str(e), path)
            time.sleep(delay)
            delay = min(delay * 2, 60)
            continue
    raise last


def get(path):
    return request("GET", path)


def post(path, payload):
    return request("POST", path, payload)


def patch(path, payload):
    return request("PATCH", path, payload)


def get_all(path):
    """Pagine jusqu'au bout en suivant links.next."""
    out, included = [], []
    while path:
        r = get(path)
        out.extend(r.get("data", []))
        included.extend(r.get("included", []))
        path = (r.get("links") or {}).get("next")
    return out, included


def err_code(e):
    try:
        return json.loads(e.body)["errors"][0].get("code", "")
    except Exception:
        return ""


def err_detail(e):
    try:
        errs = json.loads(e.body)["errors"]
        return "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in errs)
    except Exception:
        return e.body[:300]


# ---------------------------------------------------------------- helpers

def check_lengths():
    bad = []
    if len(GROUP_DISPLAY_NAME) > NAME_LIMIT:
        bad.append(("group", GROUP_DISPLAY_NAME, len(GROUP_DISPLAY_NAME)))
    for p in PLANS:
        for loc, (n, d) in p["loc"].items():
            if len(n) > NAME_LIMIT:
                bad.append((f"{p['key']}/{loc}/name", n, len(n)))
            if len(d) > DESC_LIMIT:
                bad.append((f"{p['key']}/{loc}/desc", d, len(d)))
    log("-- controle des longueurs (nom<=30, description<=45) --")
    for p in PLANS:
        for loc in LOCALES:
            n, d = p["loc"][loc]
            log(f"   {p['key']:7s} {loc:6s} name={len(n):2d} desc={len(d):2d}  {n!r} / {d!r}")
    if bad:
        for b in bad:
            log("   !! TROP LONG:", b)
        sys.exit("Longueurs invalides, rien n'a ete envoye.")
    log("   OK\n")


# ---------------------------------------------------------------- etapes

def ensure_group():
    groups, _ = get_all(f"/v1/apps/{APP_ID}/subscriptionGroups?limit=50")
    for g in groups:
        if g["attributes"]["referenceName"] == GROUP_REFERENCE_NAME:
            log(f"[groupe] existe deja: {g['id']}")
            return g["id"]
    r = post("/v1/subscriptionGroups", {
        "data": {
            "type": "subscriptionGroups",
            "attributes": {"referenceName": GROUP_REFERENCE_NAME},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
        }
    })
    gid = r["data"]["id"]
    log(f"[groupe] cree: {gid}")
    return gid


def ensure_group_localizations(gid):
    existing, _ = get_all(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations?limit=50")
    by_locale = {x["attributes"]["locale"]: x for x in existing}
    for loc in LOCALES:
        cur = by_locale.get(loc)
        if cur:
            if cur["attributes"].get("name") != GROUP_DISPLAY_NAME:
                patch(f"/v1/subscriptionGroupLocalizations/{cur['id']}",
                      {"data": {"type": "subscriptionGroupLocalizations", "id": cur["id"],
                                "attributes": {"name": GROUP_DISPLAY_NAME}}})
                log(f"[groupe/loc] {loc} mis a jour")
            else:
                log(f"[groupe/loc] {loc} deja OK")
            continue
        try:
            post("/v1/subscriptionGroupLocalizations", {
                "data": {"type": "subscriptionGroupLocalizations",
                         "attributes": {"name": GROUP_DISPLAY_NAME, "locale": loc},
                         "relationships": {"subscriptionGroup": {
                             "data": {"type": "subscriptionGroups", "id": gid}}}}})
            log(f"[groupe/loc] {loc} cree")
        except ApiError as e:
            if "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE" in e.body or e.status == 409:
                log(f"[groupe/loc] {loc} deja present")
            else:
                raise


def ensure_subscription(gid, plan):
    subs, _ = get_all(f"/v1/subscriptionGroups/{gid}/subscriptions?limit=200")
    for s in subs:
        if s["attributes"]["productId"] == plan["productId"]:
            log(f"[sub {plan['key']}] existe deja: {s['id']} ({s['attributes'].get('state')})")
            return s["id"]
    r = post("/v1/subscriptions", {
        "data": {"type": "subscriptions",
                 "attributes": {"name": plan["referenceName"],
                                "productId": plan["productId"],
                                "familySharable": False,
                                "subscriptionPeriod": plan["period"],
                                "groupLevel": 1},
                 "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": gid}}}}})
    sid = r["data"]["id"]
    log(f"[sub {plan['key']}] cree: {sid}")
    return sid


def ensure_review_note(sid, plan):
    r = get(f"/v1/subscriptions/{sid}")
    if r["data"]["attributes"].get("reviewNote") == REVIEW_NOTE:
        log(f"[sub {plan['key']}/note] deja OK")
        return
    patch(f"/v1/subscriptions/{sid}",
          {"data": {"type": "subscriptions", "id": sid,
                    "attributes": {"reviewNote": REVIEW_NOTE}}})
    log(f"[sub {plan['key']}/note] posee")


def ensure_sub_localizations(sid, plan):
    existing, _ = get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations?limit=50")
    by_locale = {x["attributes"]["locale"]: x for x in existing}
    for loc in LOCALES:
        name, desc = plan["loc"][loc]
        cur = by_locale.get(loc)
        if cur:
            a = cur["attributes"]
            if a.get("name") != name or a.get("description") != desc:
                patch(f"/v1/subscriptionLocalizations/{cur['id']}",
                      {"data": {"type": "subscriptionLocalizations", "id": cur["id"],
                                "attributes": {"name": name, "description": desc}}})
                log(f"[sub {plan['key']}/loc] {loc} mis a jour")
            else:
                log(f"[sub {plan['key']}/loc] {loc} deja OK")
            continue
        try:
            post("/v1/subscriptionLocalizations", {
                "data": {"type": "subscriptionLocalizations",
                         "attributes": {"name": name, "description": desc, "locale": loc},
                         "relationships": {"subscription": {
                             "data": {"type": "subscriptions", "id": sid}}}}})
            log(f"[sub {plan['key']}/loc] {loc} cree")
        except ApiError as e:
            if "DUPLICATE" in e.body or e.status == 409:
                log(f"[sub {plan['key']}/loc] {loc} deja present")
            else:
                raise


def all_territories():
    data, _ = get_all("/v1/territories?limit=200")
    return sorted(x["id"] for x in data)


_CURRENCIES = None


def territory_currencies():
    global _CURRENCIES
    if _CURRENCIES is None:
        data, _ = get_all("/v1/territories?limit=200")
        _CURRENCIES = {x["id"]: x["attributes"].get("currency") for x in data}
    return _CURRENCIES


def ensure_availability(sid, plan, territories):
    """Un abo neuf n'a AUCUNE disponibilite. Sans elle, poser un prix echoue
    en ENTITY_ERROR.RELATIONSHIP.INVALID en pointant (a tort) le price point."""
    cur_ids = set()
    avail_id = None
    try:
        r = get(f"/v1/subscriptions/{sid}/subscriptionAvailability")
        d = r.get("data")
        if d:
            avail_id = d["id"]
            terr, _ = get_all(f"/v1/subscriptionAvailabilities/{avail_id}/availableTerritories?limit=200")
            cur_ids = {t["id"] for t in terr}
    except ApiError as e:
        if e.status != 404:
            raise
    missing = set(territories) - cur_ids
    if avail_id and not missing:
        log(f"[sub {plan['key']}/dispo] deja {len(cur_ids)} territoires - OK")
        return len(cur_ids)
    payload = {"data": {
        "type": "subscriptionAvailabilities",
        "attributes": {"availableInNewTerritories": True},
        "relationships": {
            "subscription": {"data": {"type": "subscriptions", "id": sid}},
            "availableTerritories": {"data": [{"type": "territories", "id": t}
                                              for t in sorted(set(territories) | cur_ids)]},
        }}}
    r = post("/v1/subscriptionAvailabilities", payload)
    log(f"[sub {plan['key']}/dispo] posee sur {len(territories)} territoires (id {r['data']['id']})")
    terr, _ = get_all(f"/v1/subscriptionAvailabilities/{r['data']['id']}/availableTerritories?limit=200")
    log(f"[sub {plan['key']}/dispo] relu: {len(terr)} territoires")
    return len(terr)


def price_points_for_territory(sid, territory):
    pps, inc = get_all(
        f"/v1/subscriptions/{sid}/pricePoints?filter[territory]={territory}&limit=200&include=territory")
    return pps


def find_ref_price_point(sid, plan):
    pps = price_points_for_territory(sid, REF_TERRITORY)
    log(f"[sub {plan['key']}/prix] {len(pps)} price points en {REF_TERRITORY}")
    exact = [p for p in pps if p["attributes"]["customerPrice"] == plan["ref_price"]]
    if exact:
        return exact[0]
    target = float(plan["ref_price"])
    best = min(pps, key=lambda p: abs(float(p["attributes"]["customerPrice"]) - target))
    log(f"[sub {plan['key']}/prix] !! pas de {plan['ref_price']} exact, plus proche = "
        f"{best['attributes']['customerPrice']}")
    return best


def equalized_price_points(ref_pp_id):
    """Palier equivalent dans chaque territoire (ce que fait l'UI web)."""
    pps, _ = get_all(
        f"/v1/subscriptionPricePoints/{ref_pp_id}/equalizations?limit=200&include=territory")
    out = {}
    for p in pps:
        terr = (((p.get("relationships") or {}).get("territory") or {}).get("data") or {}).get("id")
        if terr:
            out[terr] = p
    return out


def existing_prices(sid):
    data, inc = get_all(f"/v1/subscriptions/{sid}/prices?limit=200&include=territory,subscriptionPricePoint")
    incmap = {(i["type"], i["id"]): i for i in inc}
    out = {}
    for p in data:
        rel = p.get("relationships") or {}
        terr = ((rel.get("territory") or {}).get("data") or {}).get("id")
        ppid = ((rel.get("subscriptionPricePoint") or {}).get("data") or {}).get("id")
        price = None
        if ppid and ("subscriptionPricePoints", ppid) in incmap:
            price = incmap[("subscriptionPricePoints", ppid)]["attributes"].get("customerPrice")
        if terr:
            out[terr] = {"id": p["id"], "pricePoint": ppid, "customerPrice": price}
    return out


def ensure_prices(sid, plan, territories, workers=8):
    """Un abo dispo dans N territoires doit etre tarife dans les N :
    un POST subscriptionPrices par territoire (l'API n'en pose qu'un a la fois)."""
    have = existing_prices(sid)
    log(f"[sub {plan['key']}/prix] deja tarife dans {len(have)} territoires")
    ref_pp = find_ref_price_point(sid, plan)
    log(f"[sub {plan['key']}/prix] reference {REF_TERRITORY} = "
        f"{ref_pp['attributes']['customerPrice']} (pp {ref_pp['id']})")
    eq = equalized_price_points(ref_pp["id"])
    eq[REF_TERRITORY] = ref_pp
    log(f"[sub {plan['key']}/prix] equalizations: {len(eq)} territoires")

    cur = territory_currencies()
    nominal = plan["nominal"]

    # Territoires en USD/EUR dont l'equalization ne tombe pas sur le palier
    # nominal voulu -> on va chercher le palier exact dans le territoire.
    to_fix = [t for t in territories
              if cur.get(t) in NOMINAL_CURRENCIES
              and (t not in eq or eq[t]["attributes"]["customerPrice"] != nominal)]
    if to_fix:
        log(f"[sub {plan['key']}/prix] palier nominal {nominal} a forcer sur "
            f"{len(to_fix)} territoires {NOMINAL_CURRENCIES}")

        def fetch(t):
            pps = price_points_for_territory(sid, t)
            exact = [p for p in pps if p["attributes"]["customerPrice"] == nominal]
            if exact:
                return t, exact[0]
            if not pps:
                return t, None
            target = float(nominal)
            return t, min(pps, key=lambda p: abs(float(p["attributes"]["customerPrice"]) - target))

        with ThreadPoolExecutor(max_workers=workers) as ex:
            for fut in as_completed([ex.submit(fetch, t) for t in to_fix]):
                t, pp = fut.result()
                if pp is not None:
                    eq[t] = pp

    # Territoires sans equalization du tout -> recherche directe
    missing_pp = [t for t in territories if t not in eq]
    if missing_pp:
        log(f"[sub {plan['key']}/prix] pas d'equalization pour {len(missing_pp)}: "
            f"{missing_pp} -> recherche directe")
        target = float(plan["ref_price"])
        for t in missing_pp:
            pps = price_points_for_territory(sid, t)
            if pps:
                eq[t] = min(pps, key=lambda p: abs(float(p["attributes"]["customerPrice"]) - target))

    todo = []
    for t in territories:
        pp = eq.get(t)
        cur_price = have.get(t)
        if pp is None:
            continue
        if cur_price is None:
            todo.append((t, pp, "nouveau"))
        elif cur_price["pricePoint"] != pp["id"]:
            todo.append((t, pp, f"correction {cur_price['customerPrice']} -> "
                                f"{pp['attributes']['customerPrice']}"))

    chosen_log, failures = {}, []

    def one(t, pp):
        body = {"data": {
            "type": "subscriptionPrices",
            "attributes": {"startDate": None, "preserveCurrentPrice": False},
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sid}},
                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pp["id"]}},
            }}}
        try:
            post("/v1/subscriptionPrices", body)
            return (t, pp["attributes"]["customerPrice"], None)
        except ApiError as e:
            if "DUPLICATE" in e.body:
                return (t, pp["attributes"]["customerPrice"], None)
            return (t, None, err_detail(e))

    if todo:
        log(f"[sub {plan['key']}/prix] {len(todo)} POST a faire")
        for t, pp, why in todo:
            if why != "nouveau":
                log(f"    ~ {t}: {why}")
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(one, t, pp) for t, pp, _ in todo]
            for fut in as_completed(futs):
                t, price, err = fut.result()
                if err:
                    failures.append((t, err))
                else:
                    chosen_log[t] = price
    else:
        log(f"[sub {plan['key']}/prix] rien a poser, tout est deja au bon palier")

    for t in sorted(chosen_log):
        log(f"    prix {plan['key']:7s} {t}: {chosen_log[t]}")
    for t, e in failures:
        log(f"    !! prix {plan['key']} {t}: {e}")
    have = existing_prices(sid)
    log(f"[sub {plan['key']}/prix] total relu: {len(have)} territoires tarifes")
    wrong = [(t, have[t]["customerPrice"]) for t in territories
             if t in have and t in eq and have[t]["pricePoint"] != eq[t]["id"]]
    if wrong:
        log(f"    !! {len(wrong)} territoires encore au mauvais palier: {wrong[:10]}")
    return have, failures


def existing_intro_offers(sid):
    data, inc = get_all(f"/v1/subscriptions/{sid}/introductoryOffers?limit=200&include=territory")
    out = {}
    for o in data:
        terr = (((o.get("relationships") or {}).get("territory") or {}).get("data") or {}).get("id")
        if terr:
            out[terr] = o
    return out


def ensure_intro_offers(sid, plan, territories, workers=8):
    """subscriptionIntroductoryOffers exige une relation territory :
    pas de forme 'tous territoires' -> un POST par territoire."""
    have = existing_intro_offers(sid)
    log(f"[sub {plan['key']}/offre] deja {len(have)} territoires")
    todo = [t for t in territories if t not in have]
    failures = []

    def one(t):
        body = {"data": {
            "type": "subscriptionIntroductoryOffers",
            "attributes": {"startDate": None, "endDate": None,
                           "duration": INTRO_OFFER["duration"],
                           "offerMode": INTRO_OFFER["offerMode"],
                           "numberOfPeriods": INTRO_OFFER["numberOfPeriods"]},
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sid}},
                "territory": {"data": {"type": "territories", "id": t}},
            }}}
        try:
            post("/v1/subscriptionIntroductoryOffers", body)
            return (t, None)
        except ApiError as e:
            if "DUPLICATE" in e.body:
                return (t, None)
            return (t, err_detail(e))

    if todo:
        with ThreadPoolExecutor(max_workers=workers) as ex:
            for fut in as_completed([ex.submit(one, t) for t in todo]):
                t, err = fut.result()
                if err:
                    failures.append((t, err))
    for t, e in failures:
        log(f"    !! offre {plan['key']} {t}: {e}")
    have = existing_intro_offers(sid)
    log(f"[sub {plan['key']}/offre] total relu: {len(have)} territoires")
    return have, failures


# ------------------------------------------------- capture de revue (paywall)

def upload_review_screenshot(sid, plan, path):
    """Derniere piece manquante : la capture du paywall.
    Elle ne peut etre produite qu'une fois l'app construite.
    Verifie : avec la capture l'abonnement passe MISSING_METADATA -> READY_TO_SUBMIT.
    """
    existing = None
    try:
        existing = get(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot").get("data")
    except ApiError as e:
        if e.status != 404:
            raise
    data = open(path, "rb").read()
    if existing:
        a = existing["attributes"]
        if a.get("fileSize") == len(data) and (a.get("assetDeliveryState") or {}).get("state") == "COMPLETE":
            log(f"[sub {plan['key']}/capture] deja posee et identique - OK")
            return existing["id"]
        request("DELETE", f"/v1/subscriptionAppStoreReviewScreenshots/{existing['id']}")
        log(f"[sub {plan['key']}/capture] ancienne capture retiree")

    r = post("/v1/subscriptionAppStoreReviewScreenshots", {"data": {
        "type": "subscriptionAppStoreReviewScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}})
    shot_id = r["data"]["id"]
    for op in r["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req, timeout=180) as resp:
            if resp.status >= 300:
                raise RuntimeError(f"upload HTTP {resp.status}")
    patch(f"/v1/subscriptionAppStoreReviewScreenshots/{shot_id}", {"data": {
        "type": "subscriptionAppStoreReviewScreenshots", "id": shot_id,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    # "upload accepte" != "asset COMPLETE" : on attend l'etat reel
    for _ in range(30):
        time.sleep(4)
        st = (get(f"/v1/subscriptionAppStoreReviewScreenshots/{shot_id}")
              ["data"]["attributes"].get("assetDeliveryState") or {})
        if st.get("state") == "COMPLETE":
            log(f"[sub {plan['key']}/capture] COMPLETE ({shot_id})")
            return shot_id
        if st.get("state") == "FAILED":
            raise RuntimeError(f"capture refusee: {st}")
    raise RuntimeError("capture toujours pas COMPLETE apres 2 min")


# ---------------------------------------------------------------- verif

def verify(gid, sub_ids, territories):
    log("\n================ VERIFICATION ================")
    glocs, _ = get_all(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations?limit=50")
    log(f"groupe {gid} ({GROUP_REFERENCE_NAME}) : "
        f"{len(glocs)} localisations -> {sorted(x['attributes']['locale'] for x in glocs)}")
    for x in glocs:
        log(f"   {x['attributes']['locale']:6s} name={x['attributes']['name']!r} "
            f"state={x['attributes'].get('state')}")
    summary = {}
    for plan in PLANS:
        sid = sub_ids[plan["key"]]
        # RELIRE AVEC include= : sans lui les relations reviennent a null
        r = get(f"/v1/subscriptions/{sid}?include=subscriptionLocalizations,"
                f"introductoryOffers,prices,appStoreReviewScreenshot,promotionalOffers")
        a = r["data"]["attributes"]
        locs, _ = get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations?limit=50")
        prices = existing_prices(sid)
        offers = existing_intro_offers(sid)
        n_terr = 0
        try:
            av = get(f"/v1/subscriptions/{sid}/subscriptionAvailability")
            if av.get("data"):
                t2, _ = get_all(
                    f"/v1/subscriptionAvailabilities/{av['data']['id']}/availableTerritories?limit=200")
                n_terr = len(t2)
        except ApiError as e:
            if e.status != 404:
                raise
        try:
            shot = get(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot").get("data")
        except ApiError as e:
            if e.status != 404:
                raise
            shot = None
        log(f"\n--- {plan['productId']} ---")
        log(f"   id            : {sid}")
        log(f"   state         : {a.get('state')}")
        log(f"   periode       : {a.get('subscriptionPeriod')}   groupLevel={a.get('groupLevel')}")
        log(f"   localisations : {len(locs)} -> {sorted(x['attributes']['locale'] for x in locs)}")
        for x in sorted(locs, key=lambda y: y['attributes']['locale']):
            aa = x["attributes"]
            log(f"      {aa['locale']:6s} {aa['name']!r} / {aa['description']!r} "
                f"(state={aa.get('state')})")
        log(f"   disponible    : {n_terr} territoires")
        log(f"   tarife        : {len(prices)} territoires")
        log(f"   offre intro   : {len(offers)} territoires (FREE_TRIAL THREE_DAYS x1)")
        log(f"   review shot   : {'present' if shot else 'ABSENT (necessite un build)'}")
        miss = sorted(set(territories) - set(prices))
        if miss:
            log(f"   !! sans prix  : {miss}")
        misso = sorted(set(territories) - set(offers))
        if misso:
            log(f"   !! sans offre : {misso}")
        summary[plan["productId"]] = {
            "id": sid, "state": a.get("state"), "territories": n_terr,
            "priced": len(prices), "offers": len(offers), "screenshot": bool(shot),
            "locales": len(locs),
        }
    log("\n================ RESUME ================")
    for k, v in summary.items():
        log(f"{k}: state={v['state']} dispo={v['territories']} tarife={v['priced']} "
            f"offre={v['offers']} loc={v['locales']} screenshot={v['screenshot']}")
    return summary


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true", help="verification seule")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--screenshot", metavar="PNG",
                    help="capture du paywall (>=640x920) a poser sur les deux abos ; "
                         "c'est la seule piece qui exige un build de l'app")
    args = ap.parse_args()

    check_lengths()

    territories = all_territories()
    log(f"[territoires] {len(territories)} au total\n")

    gid = ensure_group()
    sub_ids = {}
    for plan in PLANS:
        sub_ids[plan["key"]] = ensure_subscription(gid, plan)

    if args.screenshot:
        for plan in PLANS:
            upload_review_screenshot(sub_ids[plan["key"]], plan, args.screenshot)
        verify(gid, sub_ids, territories)
        return

    if args.verify:
        verify(gid, sub_ids, territories)
        return

    ensure_group_localizations(gid)
    for plan in PLANS:
        sid = sub_ids[plan["key"]]
        ensure_sub_localizations(sid, plan)
        ensure_review_note(sid, plan)

    for plan in PLANS:
        sid = sub_ids[plan["key"]]
        ensure_availability(sid, plan, territories)

    for plan in PLANS:
        sid = sub_ids[plan["key"]]
        ensure_prices(sid, plan, territories, workers=args.workers)

    for plan in PLANS:
        sid = sub_ids[plan["key"]]
        ensure_intro_offers(sid, plan, territories, workers=args.workers)

    verify(gid, sub_ids, territories)


if __name__ == "__main__":
    main()
