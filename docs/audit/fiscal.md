# Audit fiscal — Mileage Pocket

**Périmètre** : calcul des indemnités kilométriques et rapports.
**Méthode** : lecture du code + rejeu du moteur en Decimal (script Python autonome reproduisant
`DeclarativeMileageRule` ligne à ligne) sur les 12 packs JSON réellement livrés. Aucune
modification, aucun build, aucun test lancé.

**Verdict : NON, les montants ne sont pas justes.** L'arithmétique de l'interpréteur est
correcte — tranches marginales, tranche unique `whole`, constante additive, multiplicateur,
bandes de puissance : tout vérifié à la main et recalculé, tout tombe juste. Les montants faux
viennent de ce qui entoure le calcul : la sélection du barème, la sélection du schéma, le
cumul annuel, le recalcul après correction, et l'en-tête des rapports.

---

## 0. Ce qui est juste (vérifié, pas supposé)

Rejeu Decimal des 12 packs contre un calcul à la main :

| Cas | Attendu (calcul manuel) | Produit par le moteur |
|---|---|---|
| GB 12 000 mi, une seule fois | 10 000×0,55 + 2 000×0,25 = £6 000,00 | £6 000,00 |
| GB 100 mi avec 9 950 mi déjà parcourus | 50×0,55 + 50×0,25 = £40,00 | £40,00 |
| GB pile sur la borne : 10 000 mi | 10 000×0,55 = £5 500,00 | £5 500,00 |
| CA 200 km avec 4 900 km déjà parcourus | 100×0,73 + 100×0,67 = CAD 140,00 | CAD 140,00 |
| FR 5 CV, 10 000 km | 10 000×0,357 + 1 395 = 4 965,00 € | 4 965,00 € |
| FR continuité à 5 000 km (5 CV, +1 km) | 3 180,357 − 3 180 = 0,36 € | 0,36 € |
| FR électrique 5 CV 1 000 km | 1,20 × 636 = 763,20 € | 763,20 € |
| IE 2 000 km, 1201–1500 cm³ | 1 500×0,4340 + 500×0,7918 = 1 046,90 € | 1 046,90 € |

Audit structurel des 12 JSON (clés, valeurs d'énumération, couverture des bandes) : **aucun
champ mal nommé, aucun trou ni recouvrement de tranche, aucune bande de puissance discontinue,
aucun taux écrit en nombre JSON au lieu de chaîne.** Les taux correspondent aux tableaux de
`docs/mileage-rules-sources.md`. Le dossier `MileageRules` est bien embarqué en *folder
reference* (`gen_pbxproj.py:308`, `lastKnownFileType = folder`), donc les 12 fichiers arrivent
bien dans le bundle avec leur arborescence.

L'arrondi est correct : `MileageRounding.money` arrondit une seule fois à la fin
(`MileageRule.swift:84`), jamais par tranche. `Decimal(Double)` introduit des artefacts
(`24.317` → `24.31700000000000512`) qui disparaissent à 2 décimales — non significatif.

Le gel du barème (question 3) **tient** : aucun chemin automatique ne recalcule un trajet
existant. `applyCalculation` n'est appelé que depuis `stopTrip`, `finishTrip`, `createManualTrip`,
`duplicate`, `recalculate` (confirmé par action utilisateur) et l'amorce démo. Un changement de
pays, d'unité ou de taux ne réécrit rien. Voir toutefois **§8**.

Le rattachement des trajets aux périodes est correct et cohérent : un trajet appartient à la
période contenant son `startedAt`, que ce soit pour le filtre du rapport
(`ReportBuilder.swift:52`) ou pour le cumul annuel (`ReportBuilder.swift:100`). Un trajet à
cheval sur minuit, sur une fin de trimestre ou sur le Nouvel An est compté **une fois**, dans la
période où il a commencé. Testé, et le test est vrai (`ReportTests.swift:93`).

---

## 1. CRITIQUE — Hors fenêtre de validité, le montant devient 0,00 sans un mot

`Resources/MileageRules/*/2026.1.json` (champs `validFrom` / `validUntil`) +
`Services/MileageRules/CountryRuleEngine.swift:33-44`

Quand aucun pack n'est valide à la date du trajet, `CountryRuleEngine.rule` ne refuse pas : il
retombe sur `CustomRateRule(ratePerUnit: customRate ?? 0)`. Or `UserSettings.customRate` vaut
`nil` tant que l'utilisateur n'est pas passé en mode *custom*. Résultat :
`applyCalculation` écrit `trip.calculatedAmount = 0` (`AppDependencies.swift:282`).

Rejeu, trajet de 100 unités, `customRate = nil` :

| Pays | Date du trajet | Produit | Attendu |
|---|---|---|---|
| US | 2026-01-15 → 2026-06-30 | **0,00 $** | 100 mi × 0,725 = 72,50 $ |
| US | 2027-01-02 | **0,00 $** | taux 2027 |
| GB | 2026-01-01 → 2026-04-05 | **0,00 £** | taux 2025/26 |
| AU | avant 2026-07-01 | **0,00 A$** | taux 2025-26 |
| BE | **à partir du 2026-10-01** | **0,00 €** | circulaire du trimestre suivant |
| PT | 2026-01-01 → 2026-01-29 | **0,00 €** | taux antérieur |
| DE / CH / NL / CA | tout 2025 | **0,00 €/CHF/CAD** | taux 2025 |

`docs/mileage-rules-sources.md:108` l'annonce explicitement pour les US (« prévoir un second
fichier `2026.0.json` ») — **le fichier n'existe pas**. Un rapport annuel 2026 américain généré
aujourd'hui affiche donc six mois de lignes à 0,00 $.

Le cas belge est imminent : `validUntil: 2026-09-30`, soit dans 17 jours à la date de l'audit.
Après cette date, chaque trajet belge vaut 0,00 € — et l'endpoint de mise à jour
(`AppLinks.rulePackEndpoint`, `PaywallView.swift:288`) n'est pas déployé
(`AppDependencies.swift:122` : « the endpoint is not deployed yet, so failing is the expected
path in V1 »). Il n'y a donc aucun moyen de livrer le pack suivant sans passer par l'App Store.

**Le test ne l'attrape pas.** `RulePackTests.swift:82-85`
(`testUnitedStatesPackDoesNotApplyBeforeItsValidityWindow`) affirme en commentaire « the app
refuses rather than applying the wrong rate » et assertit `store.pack(...) == nil` et
`hasOfficialRule == false`. Les deux sont vrais. Mais l'app **ne refuse pas** : elle écrit
0,00 $ sur le trajet. Le test prouve le comportement du *store*, pas celui de l'app, et passe
intégralement avec le défaut présent. Idem `MileageCalculationTests.swift:268-280`, qui
n'assertit jamais le montant produit hors fenêtre.

---

## 2. CRITIQUE — Le schéma retenu est faux dès que le véhicule est inconnu ou non couvert

`Services/MileageRules/DeclarativeMileageRule.swift:65-67` +
`Services/MileageRules/RulePackModels.swift:112-117`

```swift
private func scheme(for vehicle: Vehicle?) -> RateScheme? {
    pack.schemes.first { $0.matches(vehicle: vehicle) } ?? pack.schemes.first
}

func matches(vehicle: Vehicle?) -> Bool {
    guard let vehicle else { return true }   // <- véhicule nil = TOUS les schémas matchent
    ...
}
```

Deux conséquences, toutes deux silencieuses.

### 2a. Véhicule nil → premier schéma du pack

Le véhicule est facultatif : l'onboarding offre « Passer » (`OnboardingFlow.swift:171`) et un
nom vide n'en crée aucun (`OnboardingFlow.swift:160`). `vehicle(for:)` renvoie alors `nil`
(`AppDependencies+Data.swift:11-23`). Dans le pack FR, le **premier** schéma est
`automobile-electrique`, `rateMultiplier: "1.20"`, `vehicleTypes: ["electricCar"]`.

> **Cas chiffré** — utilisateur français sans véhicule enregistré, trajet de 100 km, 0 km au
> compteur annuel.
> Attendu : barème 5 CV de repli, 100 × 0,636 = **63,60 €**.
> Produit : schéma `automobile-electrique`, 100 × 0,636 × 1,20 = **76,32 €**. **+20 % sur
> chaque trajet, toute l'année.**

### 2b. Type de véhicule non couvert → premier schéma du pack

`?? pack.schemes.first` masque l'absence de barème. Rejeu sur les 12 packs, trajet de 100 unités :

| Pays | Type déclaré | Schéma réellement appliqué | Montant produit | Ce que dit la source |
|---|---|---|---|---|
| FR | `bicycle` | `automobile-electrique` | **76,32 €** | pas de barème vélo en France |
| US | `motorcycle` / `moped` / `bicycle` | `business` | **76,00 $** | `docs:109` — motos exclues du *standard mileage rate* |
| DE | `motorcycle` | `kilometerpauschale` | **30,00 €** | `docs:199` — « les motos passeront en *Custom rate* » |
| CH | `motorcycle` | `auto` | **75,00 CHF** | `docs:241` — motos non reprises |
| PT | `motorcycle` | `viaturaPropria` | **40,00 €** | `docs:385` — « aucune valeur confirmée » |
| CA / AU / BE | `motorcycle` / `bicycle` | schéma voiture | 73,00 / 91,00 / 44,40 | aucun barème deux-roues dans le pack |

Le code contredit directement l'intention documentée : la doc dit « passeront en *Custom rate* »,
le code applique le tarif voiture. Un motard allemand voit 30,00 €/100 km au lieu des 20,00 €
de la pratique fiscale — **+50 %** — et sans jamais que `isOfficialRate` passe à `false`.

**Les tests ne l'attrapent pas.** `MileageCalculationTests.swift:234` assertit bien
`vehicle: nil`, mais sur un pack synthétique dont tous les schémas portent
`vehicleTypes: VehicleType.allCases` : le premier schéma est de toute façon le bon.
`testMotorcycleSchemeIsPickedOverTheCarScheme` (ligne 237) ne teste que des véhicules non nuls.
Dans `RulePackTests`, **aucun test n'assertit un montant français avec `vehicle: nil`** — tous
passent une `frenchCar(fiscalHorsepower:)`. Les deux défauts survivent à la suite entière.

### 2c. Puissance fiscale non saisie → barème médian appliqué en silence

`RulePackModels.swift:134-146` : sans `fiscalHorsepower`, le pack FR retombe sur ses `bands`,
qui sont la ligne **5 CV**. Le champ CV n'a ni valeur par défaut ni validation
(`OnboardingFlow.swift:144`). Propriétaire d'une 7 CV qui n'a rien saisi : 100 km →
**63,60 €** au lieu de 69,70 € (−8,8 %). Même mécanique en Irlande : une cylindrée à 0 (et non
à `nil`) tombe dans la bande « ≤ 1200 cm³ » et non dans le repli 1201–1500 → 2 000 km à
**990,20 €** au lieu de 1 046,90 €.

---

## 3. CRITIQUE — `recalculateWithFrozenRule` produit trois familles de montants faux

`App/AppDependencies.swift:291-302`

```swift
let unit = settingsStore.settings.distanceUnit
let distance = Decimal(unit.value(fromMeters: trip.distanceMeters))
trip.calculatedAmount = MileageRounding.money(distance * rate)
```

C'est le chemin de la correction manuelle de distance (`TripDetailView.swift:183-191`).

### 3a. L'unité est celle des réglages, le taux est celui du barème

`trip.mileageRate` est exprimé dans l'unité **du pack** (`MileageCalculation.unit`), jamais
relue ici. Le sélecteur d'unité (`SettingsView.swift:93-99`) est totalement indépendant du pays.

> **Cas chiffré** — utilisateur GB (pack en miles, 0,55 £/mile) qui a mis l'affichage en km.
> Trajet enregistré de 100 mi → 55,00 £, taux gelé 0,55 £/**mile**. Il corrige la distance en
> tapant « 150 » (interprété en km → 150 000 m).
> Attendu : 150 000 m = 93,2057 mi × 0,55 = **51,26 £**.
> Produit : `150 × 0,55` = **82,50 £**. **+61 %.**

### 3b. Le taux gelé est le taux *mixte*, pas le barème

Sur un barème à tranches, `MileageCalculation.rate` est le taux effectif mélangé du trajet
d'origine (`DeclarativeMileageRule.swift:48-50`). Le réappliquer à une autre distance n'est pas
le barème.

> **Cas chiffré GB** — 9 950 mi au compteur annuel, trajet de 100 mi → 40,00 £, taux mixte
> 0,40 £/mi. Correction 100 → 200 mi.
> Attendu : 50×0,55 + 150×0,25 = **65,00 £**. Produit : 200 × 0,40 = **80,00 £**. **+23 %.**

### 3c. Sur le barème `whole` français, la constante est mise à l'échelle

> **Cas chiffré FR 5 CV** — 4 900 km au compteur, trajet de 200 km → 99,30 €, taux mixte
> 0,49650 (qui contient une part de la constante de 1 395 €). Correction 200 → 100 km.
> Attendu : C(5 000) − C(4 900) = 3 180 − 3 116,40 = **63,60 €**.
> Produit : 100 × 0,49650 = **49,65 €**. **−22 %.**

Aucun test ne couvre `recalculateWithFrozenRule`.

---

## 4. CRITIQUE — Le cumul annuel n'est jamais rafraîchi : les autres trajets deviennent faux

`Services/Reports/ReportBuilder.swift:91-103` + `App/AppDependencies.swift:271-272`

`yearlyDistanceMeters(before:in:)` est correct en soi : il exclut le trajet lui-même, exclut les
trajets personnels, filtre sur la même année fiscale et ne retient que ce qui précède
`startedAt`. Le test `ReportTests.swift:127-138` le prouve honnêtement.

Le problème est qu'il n'est **évalué qu'une fois**, au moment où le trajet est calculé. Aucun
chemin — ni `createManualTrip` (`AppDependencies+Data.swift:164-179`), ni `delete`
(`:181-186`), ni `applyDistanceEdit` — ne recalcule les trajets postérieurs de la même année.

> **Cas chiffré — insertion antidatée (GB)**
> 1. 01/06/2026, 9 900 mi → 9 900 × 0,55 = **5 445,00 £**
> 2. 01/07/2026, 200 mi (cumul 9 900) → 100×0,55 + 100×0,25 = **80,00 £**
> 3. L'utilisateur saisit à la main un trajet oublié du **15/05/2026, 500 mi** → cumul 0 →
>    **275,00 £**
>
> Total affiché : **5 800,00 £**. Correct pour 10 600 mi : 10 000×0,55 + 600×0,25 =
> **5 650,00 £**. **150,00 £ de trop**, réclamés au fisc, sans aucun signal.

> **Cas chiffré — suppression (GB)**
> Trajets 9 900 mi + 200 mi (= 5 525,00 £). L'utilisateur supprime le trajet de 9 900 mi.
> Le trajet restant conserve **80,00 £** (taux mixte) alors qu'il vaut désormais
> 200 × 0,55 = **110,00 £**. **30,00 £ perdus.**

Dans les deux sens, rien ne le signale : ni badge, ni recalcul proposé, ni `isManuallyEdited`.
Et `Trip.swift:9-11` promet exactement l'inverse (« the applied rate is frozen here at save
time ») — le gel est réel mais il gèle un montant devenu faux.

Cas limite mineur : deux trajets au même `startedAt` à la microseconde près ne se comptent pas
mutuellement (`ReportBuilder.swift:101`, comparaison stricte). Les deux sont alors sous-comptés.

---

## 5. MAJEUR — L'année fiscale britannique est traitée comme une année civile

`Services/Reports/ReportPeriod.swift:51-56`

```swift
/// Calendar year: the countries whose tax year is offset (the UK's 6 April) are handled
/// by their pack's validity window, not by shifting every user's reports.
static func taxYear(of date: Date, calendar: Calendar = .current) -> Int {
    calendar.component(.year, from: date)
}
```

Le commentaire est faux. La fenêtre de validité d'un pack choisit un **taux** ; elle ne remet
pas à zéro le **compteur** des 10 000 miles de l'AMAP, qui court du 6 avril au 5 avril.

> **Cas chiffré** — année fiscale 2026/27, pack GB valide depuis le 06/04/2026.
> 7 000 mi du 06/04/2026 au 31/12/2026 → 3 850,00 £ (tout à 0,55).
> 5 000 mi du 01/01/2027 au 05/04/2027 → compteur remis à zéro le 1er janvier → 2 750,00 £.
> Total app : **6 600,00 £**. HMRC pour 12 000 mi sur une année fiscale :
> 10 000×0,55 + 2 000×0,25 = **6 000,00 £**. **600,00 £ de trop.**

Le sens s'inverse (sous-déclaration) si le seuil est franchi dans les deux segments civils.
Aucun test ne couvre le 6 avril. Le problème est limité à GB : IE, FR, CA, US, DE, NL, ES, PT,
CH sont en année civile ; AU (1er juillet) n'a qu'une tranche, donc le compteur n'a pas d'effet.

---

## 6. MAJEUR — L'en-tête du rapport décrit la règle d'aujourd'hui, pas celle des lignes

`App/AppDependencies+Data.swift:246-263` — `reportProfile()` appelle `currentRule()`,
c'est-à-dire `currentRule(on: .now)` avec le **pays et le mode actuels**.

Conséquences sur le PDF :
- `PDFReportRenderer.swift:140-142` imprime « Country / Rule / Rule version » de la règle du
  jour, au-dessus de lignes qui peuvent avoir été calculées sous une autre règle, dans un autre
  pays et une autre devise.
- `:174` choisit le libellé « Total deduction » ou « Total reimbursement » sur
  `profile.isOfficialRate` du jour.
- `:268-270` n'imprime l'avertissement « This report uses a rate you configured yourself » que
  si la règle **du jour** n'est pas officielle.
- `:260` et `:263` citent la source officielle du jour.

> **Cas concret, combiné avec §1** — rapport annuel US 2026 généré aujourd'hui. Les lignes de
> janvier à juin valent 0,00 $ (aucun pack valide → `CustomRateRule`, `isOfficialRate = false`
> sur ces trajets). Le PDF imprime malgré tout « Rule : IRS — Standard mileage rates… /
> Version : 2026.1 », « Total deduction », la source IRS, et **aucun** avertissement de taux
> personnalisé. Le document affirme une base légale que la moitié de ses lignes n'a pas.

> **Cas concret, changement de pays** — rapport français 2025 généré après passage en Allemagne :
> en-tête « Country: Germany · Rule: § 9 EStG… » au-dessus de lignes en euros calculées au
> barème français.

La note « more than one rule version applies » (`:265-266`) existe, mais elle ne se déclenche
que sur la pluralité de `mileageRuleVersion` et ne corrige pas l'en-tête.
`ReportTests.swift:233-244` vérifie cette note sur des trajets dont le `mileageRuleVersion` est
posé à la main — il prouve le pied de page, pas le calcul, et surtout pas l'en-tête.

---

## 7. MAJEUR — Devises mélangées : somme muette et symbole incohérent

`Services/Reports/ReportBuilder.swift:74` et `:84`

```swift
let total = rows.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
...
currencyCode: rows.compactMap(\.currencyCode).first ?? fallbackCurrency
```

Le total additionne des montants **sans regarder leur devise**, puis l'étiquette avec celle de
la **première ligne** (la plus ancienne, puisque `selected` est trié croissant). Un utilisateur
qui a roulé en France puis en Suisse sur la même période obtient un total « 1 234,56 € » qui est
une somme d'euros et de francs.

Réponse à la question 6 : **le montant par trajet est bon et le symbole par trajet est bon** —
`trip.currencyCode` est gelé depuis le pack (`AppDependencies.swift:283`) et les lignes
individuelles l'utilisent (`PDFReportRenderer.swift:220-221`, `TripsView.swift:104-106`,
`HomeView.swift:121-122`). Ce sont les **agrégats** qui sont faux, et deux écrans ne disent pas
la même chose du même chiffre :

| Écran | Chemin | Devise utilisée pour le total du mois |
|---|---|---|
| Accueil | `HomeView.swift:66` → `HomeModel.swift:30` | `settings.currencyCode` (pays **actuel**) |
| Rapports | `ReportsView.swift:108` → `ReportBuilder.swift:84` | devise du **premier trajet** |
| PDF | `PDFReportRenderer.swift:175`, `:248` | devise du **premier trajet** |
| Widget | `AppDependencies+Data.swift:294` | devise du **premier trajet** |

> Trajet de 100 km enregistré en France (63,60 €, EUR), puis pays basculé sur la Suisse.
> Accueil : « CHF 63.60 ». Rapports et PDF : « 63,60 € ». Même chiffre, deux symboles.

Le CSV, lui, n'imprime **aucune** devise : ni colonne, ni symbole, ni en-tête
(`CSVExporter.swift:12`). Un comptable qui ouvre le CSV n'a aucun moyen de savoir en quoi sont
libellés les montants.

---

## 8. MAJEUR — `recalculate` réécrit le pays du trajet

`App/AppDependencies.swift:259-261` et `:306-311`

```swift
func applyCalculation(to trip: Trip) {
    let settings = settingsStore.settings
    trip.countryCode = settings.countryCode
```

`recalculate(_:)` est présenté comme « the only path allowed to move an old trip onto a new
**scale** » (`:304-305`). En réalité il déplace aussi le trajet vers un autre **pays**, une autre
**devise** et un autre **mode de taux** (`:286`).

> **Cas chiffré** — trajet français du 01/06/2025, 100 km, 63,60 €. L'utilisateur déménage,
> passe les réglages sur l'Allemagne, ouvre l'ancien trajet et confirme « Recalculer ».
> `currentRule(on: 2025-06-01)` cherche un pack **DE** au 01/06/2025 → `validFrom` = 2026-01-01
> → aucun → `CustomRateRule(0)`.
> Produit : **0,00 €**, `countryCode = "DE"`, `isOfficialRate = false`. Le montant d'origine est
> perdu, en un tap, sans avertissement autre qu'une confirmation générique
> (`TripDetailView.swift:48-53`).

---

## 9. MAJEUR — Plafonds et suppléments officiels non modélisés, et `notes` n'est jamais lu

`RulePackModels.swift:23` déclare `let notes: [String: String]?` — « Optional localisation keys
for country-specific caveats shown in Settings ». Grep sur tout le projet : **`notes` n'est lu
nulle part**, et **aucun des 12 JSON ne le renseigne**. Les réserves que la documentation
demande d'afficher n'ont donc aucun canal vers l'écran.

| Pays | Élément officiel | Effet sur le montant |
|---|---|---|
| AU | plafond 5 000 km/an, méthode *cents per kilometre* (`docs:262`) | 20 000 km → l'app produit **18 200,00 A$**, le maximum ATO est 5 000 × 0,91 = **4 550,00 A$**. **×4.** |
| CH | plafond annuel 3 200 CHF pour l'IFD (`docs:240`) | au-delà de ~4 267 km, tout excédent est faux |
| CA | supplément territoires du Nord +4 ¢/km (`docs:172`) | un résident du Yukon est sous-payé de 4 ¢/km, soit −5,5 % |

Le cas australien est le plus grave : il produit un montant faux d'un facteur 4 sur un profil
parfaitement banal (un commercial), et `RulePackTests.swift:107-109` ne teste que 100 km.

---

## 10. MOYEN — Total de distance « business » qui inclut les trajets personnels

`ReportBuilder.swift:81-82` calcule `totalDistanceMeters` (toutes lignes) **et**
`businessDistanceMeters` (lignes business). Les deux exportateurs n'utilisent que le premier :

- `CSVExporter.swift:34-35` : la ligne TOTAL porte `"\(businessTripCount) business trips"` en
  colonne « Purpose » et `totalDistanceMeters` en colonne « Distance ».
- `PDFReportRenderer.swift:240-242` : « TOTAL — N business trips » avec `totalDistanceMeters`.
- `PDFReportRenderer.swift:173` : la tuile « Total distance » de l'en-tête, idem.

`businessDistanceMeters` est **mort** dans les deux exportateurs.

C'est sans effet tant que `includePersonal = false`, mais `exportAllData()`
(`AppDependencies+Data.swift:232-244`) passe `includePersonal: true`.

> Un trajet business de 10 km + un trajet personnel de 40 km → le CSV « toutes données » affiche
> `"TOTAL","","","1 business trips","50.0","","10.00"`. **50,0 km présentés comme la distance
> d'« 1 business trip »**, soit cinq fois la valeur réelle.

`ReportTests.swift:71-78` teste bien `includePersonal: true` mais n'assertit que
`businessDistanceMeters` — précisément le champ que personne n'imprime. Le défaut survit au test.

---

## 11. MOYEN — Le taux d'un trajet est affiché avec la mauvaise unité

`Features/TripDetail/TripDetailView.swift:17` et `:121`

```swift
private var unit: DistanceUnit { dependencies.settingsStore.settings.distanceUnit }
...
row("detail.rate", Fmt.rate(rate, currencyCode: currency, unit: unit, locale: locale))
```

Le taux est dans l'unité du pack ; l'étiquette vient des réglages. Un trajet britannique affiché
par un utilisateur en km lit « £0,55/km » pour un taux de 0,55 £/**mile**. Même mécanique dans
le CSV et le PDF : la colonne « Distance » est convertie avec `profile.unit`
(`CSVExporter.swift:24`, `PDFReportRenderer.swift:219`) tandis que « Rate » et « Amount » sont
dans l'unité du barème. La ligne ne se réconcilie plus — c'est exactement ce que le commentaire
de `CSVExporter.swift:81-83` promet d'éviter.

---

## 12. MOYEN — Le taux imprimé à 4 décimales ne réconcilie pas les trajets à tranches

`CSVExporter.swift:84-92` (`maximumFractionDigits = 4`) et `PDFReportRenderer.swift:220` via
`Fmt.rateAmount` (`.precision(.fractionLength(2...4))`), alors que `MileageRounding.rate`
conserve **5** décimales (`MileageRule.swift:93-97`).

> **Cas chiffré IE** — un trajet de 2 000 km, cylindrée inconnue (repli 1201–1500 cm³).
> Montant : 1 046,90 €. Taux mixte stocké : 0,52345. Taux imprimé : 0,5234.
> 2 000 × 0,5234 = **1 046,80 €** ≠ 1 046,90 € affiché à côté. **10 centimes d'écart sur la
> ligne**, sur le contrôle que le commentaire du code désigne comme « the first thing an
> accountant checks ».

`ReportTests.swift:260-273` prétend prouver cette réconciliation, mais sur un trajet de 24,3 km
à taux plat 0,7632 (écart réel : 0) et avec `accuracy: 0.01`. Le cas irlandais dépasserait cette
tolérance — le test passe parce qu'il ne l'exerce pas.

---

## 13. MOYEN — Le repli « taux écrit en nombre » est du code mort : le pays entier disparaît

`Services/MileageRules/RulePackModels.swift:205-225`

```swift
if let string = try container.decodeIfPresent(String.self, forKey: key) { ... }
// Tolerated so a hand-written pack with a bare number still loads rather than
// failing the whole country; the string form stays the one we produce.
if let number = try container.decodeIfPresent(Double.self, forKey: key) { ... }
```

Le commentaire est faux. Vérifié en exécutant le décodeur :

```
{"rate":"0.45"} -> Optional(0.45)
{"rate":0.45}   -> THROWS: DecodingError.typeMismatch: expected value of type String. Path: rate.
{"rate":null}   -> nil
{}              -> nil
```

`decodeIfPresent` ne renvoie `nil` que si la clé est absente ou nulle ; un type incompatible
**lève**. La ligne 218 est donc inatteignable. Conséquences :

- `RulePackStore.load` attrape et **saute le fichier** (`:84-87`, log `.error` uniquement) → le
  pays disparaît de `availableCountries()` → tous ses trajets tombent dans le cas **§1**, à 0,00.
- Pire côté réseau : `RulePackUpdater.refresh` décode `[RulePack]` en un seul appel
  (`:59`). **Un seul taux écrit en nombre dans le lot tue la mise à jour des 12 pays**, et
  l'échec est journalisé en `.debug` (`:68`) puis avalé.

Aucun test ne décode un pack malformé. Les 12 packs livrés utilisent bien des chaînes — le
défaut est donc latent, mais il est armé sur le canal de mise à jour.

---

## 14. MOYEN — Un pack historique ne peut jamais être installé par le réseau

`Services/MileageRules/RulePackUpdater.swift:74-77`

```swift
private func isNewer(_ pack: RulePack) -> Bool {
    guard let existing = store.pack(country: pack.country, on: .now) else { return true }
    return pack.version.compare(existing.version, options: .numeric) == .orderedDescending
}
```

La comparaison est faite contre le pack valide **aujourd'hui**, pas contre l'existence d'un pack
couvrant la fenêtre du nouveau. Le correctif que la documentation prescrit pour les États-Unis —
un `2026.0.json` couvrant janvier-juin à 72,5 ¢ (`docs:108`, `docs:420`) — porte une version
`2026.0` < `2026.1` : `isNewer` renvoie `false`, le pack est rejeté. **Le trou historique du
§1 ne peut pas être bouché par une mise à jour**, seulement par une nouvelle version de l'app.

Même racine dans `RulePackStore.insert` (`:53-59`), qui déduplique sur la seule `version` sans
tenir compte de la fenêtre de validité.

---

## 15. MOYEN — La discontinuité à 20 000 km facture 5,43 € pour un kilomètre

`DeclarativeMileageRule.swift:70-93`, mode `.whole`.

Le barème français n'est pas continu à 20 000 km : C(20 000) = 20 000×0,357 + 1 395 = 8 535 €
(5 CV) alors que C(20 001) = 20 001×0,370 = 8 540,43 €.

> Un trajet de **1 km** effectué alors que le compteur annuel est à 20 000 km est facturé
> **5,43 €**, taux effectif **5,42700 €/km**, imprimé tel quel dans la colonne « Rate » du PDF.

Le total annuel reste juste — c'est la répartition par trajet qui est indéfendable à l'œil.
Même phénomène, plus discret, à 5 000 km pour les 6 CV (+2 €, écart reconnu dans
`docs:80`) et à 3 000 km pour les motos 1–2 CV (+3 €).
`RulePackTests.swift:178-186` ne teste la continuité qu'à 5 000 km et qu'en 5 CV, c'est-à-dire
sur la seule borne exactement continue du barème.

---

## 16. MINEUR

- `applyCalculation` ne remet pas `mileageRuleVersion` ni `isOfficialRate` à zéro quand un trajet
  est reclassé en personnel (`AppDependencies.swift:263-268`) : la version d'un barème qui ne
  s'applique plus continue d'alimenter `ReportData.ruleVersions` et donc la note « plus d'une
  version de règle » du PDF.
- `ReportsView` filtre `$0.endedAt != nil` (`:50`) ; `HomeModel` (`:34`), `refreshWidgetSnapshot`
  (`AppDependencies+Data.swift:287`) et `exportAllData` (`:234`) ne le font pas. Un trajet en
  cours compte dans l'accueil et le widget mais pas dans les rapports.
- `ReportPeriod` et `yearlyDistanceMeters` utilisent `Calendar.current`, donc le fuseau de
  l'appareil. Un trajet du 1er janvier 00 h 30 à Paris change d'année fiscale si l'appareil passe
  en UTC. Les montants sont gelés, seul le regroupement bouge.
- `RateScheme.fuelTypes` est `null` dans les 12 packs ; le filtrage par carburant
  (`RulePackModels.swift:115`) n'est jamais exercé.
- `PDFReportRenderer.paginate` (`:102`) réserve 210 pt en dur pour un bloc d'en-tête dont la
  hauteur est dynamique (`drawLabelledValue` avec `wraps: true` sur « Rule »). Un nom de règle
  long — celui de l'Australie fait 96 caractères — peut pousser le bloc de clôture hors page.

---

## Verdict sur les tests

| Test | Ce qu'il prétend | Verdict |
|---|---|---|
| `RulePackTests:82` `testUnitedStatesPackDoesNotApplyBeforeItsValidityWindow` | « the app refuses rather than applying the wrong rate » | **Faux.** Assertit le store, pas l'app. L'app écrit 0,00 $. Passe avec le défaut §1. |
| `RulePackTests:215` `testIrelandBandsByEngineCapacity` | bande par cylindrée | **Ne prouve rien sur le montant** : `XCTAssertGreaterThan(withCapacity, 0)`. Passerait avec n'importe quel taux irlandais. |
| `MileageCalculationTests:223` `testUnknownPowerFallsBackToTheSchemesOwnBands` | `vehicle: nil` → bandes de repli | **Vrai mais aveugle** : pack synthétique dont tous les schémas couvrent tous les types. Passe avec le défaut §2a. |
| `MileageCalculationTests:308` `testMoneyIsRoundedOnceAtTheEnd` | arrondi unique en fin de calcul | Le corps l'avoue : il assertit un montant par trajet. Ne prouve pas l'absence d'arrondi par tranche. |
| `ReportTests:71` `testPersonalTripsAreIncludedOnRequest` | inclusion des trajets personnels | Assertit `businessDistanceMeters`, le seul champ que ni le CSV ni le PDF n'impriment. Passe avec le défaut §10. |
| `ReportTests:260` `testCSVRateKeepsEnoughPrecisionForTheRowToReconcile` | distance × taux = montant | Cas à taux plat, écart réel 0, `accuracy: 0.01`. Le cas irlandais (écart 0,10 €) n'est pas exercé. Passe avec le défaut §12. |
| `ReportTests:233` `testPDFFlagsWhenSeveralRuleVersionsApplyInsideOnePeriod` | période à cheval sur deux barèmes | Prouve le pied de page sur des `mileageRuleVersion` posés à la main. Ne touche jamais le moteur ni l'en-tête (§6). |
| `ReportTests:93` `testATripCrossingNewYearIsCountedOnceInItsStartingYear` | trajet à cheval sur le Nouvel An | **Vrai et utile.** |
| `ReportTests:127` `testYearlyDistanceBeforeATripCountsOnly…` | cumul annuel | **Vrai et utile** — mais ne teste que la fonction pure, jamais son rafraîchissement (§4). |
| `RulePackTests:113-149`, `:160-211` (GB, CA, FR) | montants officiels | **Vrais et utiles.** C'est ce qui garantit que l'arithmétique est juste. |

**Non couvert par un seul test** : `recalculateWithFrozenRule` (§3), la péremption du cumul
annuel après insertion/suppression/édition (§4), l'année fiscale britannique (§5),
`reportProfile` vs les lignes (§6), les devises mélangées (§7), l'écrasement du pays par
`recalculate` (§8), les plafonds AU/CH (§9), le décodage d'un pack malformé (§13),
`isNewer` sur un pack historique (§14), et le montant produit par un véhicule `nil` ou d'un type
non couvert en France (§2).

---

## Réponses aux six questions

1. **L'arithmétique est-elle juste ?** Oui. Tranches marginales, tranche unique `whole`,
   constante additive, multiplicateur électrique, bandes CV/cylindrée : les huit cas recalculés
   à la main tombent au centime. L'arrondi est fait une seule fois, à la fin. Le défaut n'est
   pas dans l'interpréteur, il est dans **le choix du barème et du schéma** (§1, §2).
2. **Le cumul annuel ?** La fonction est correcte ; elle n'est **jamais rejouée**. Une insertion
   antidatée, une suppression ou une correction de distance rend faux les montants des autres
   trajets de l'année, sans aucun signal (§4, cas chiffré : 150 £ de trop). L'année fiscale est
   en outre civile pour tout le monde, ce qui est faux pour le Royaume-Uni (§5, 600 £ de trop).
3. **L'historisation ?** Respectée. Aucun chemin automatique ne reprend un trajet existant.
   Réserve : `recalculate`, déclenché par l'utilisateur, réécrit aussi le **pays** et peut
   ramener le montant à 0,00 (§8).
4. **Les rapports ?** Les totaux monétaires du CSV et du PDF lisent le même champ et sont donc
   identiques. Ils divergent en revanche sur la devise (le CSV n'en imprime aucune, §7), ils
   présentent une distance qui inclut le personnel sous une étiquette « business » (§10), leurs
   lignes ne se réconcilient plus quand l'unité des réglages diffère de celle du barème (§11) ou
   sur un trajet long à tranches (§12), et l'en-tête décrit une règle qui n'est pas celle des
   lignes (§6). Minuit, fin de trimestre et fin d'année sont traités correctement.
5. **Les rule packs ?** Structurellement impeccables : aucun champ mal nommé, aucun trou de
   tranche, aucun taux en nombre JSON, valeurs conformes aux sources documentées. La validité
   temporelle est **appliquée** mais pas **couverte** : il manque les packs des périodes
   antérieures, et hors fenêtre le montant devient 0,00 au lieu de refuser (§1). `notes` est
   décodé mais lu nulle part, donc aucune réserve officielle n'atteint l'écran (§9).
6. **La devise ?** Correcte par trajet, fausse en agrégat : le total additionne des devises
   différentes et l'étiquette avec celle du premier trajet ; l'accueil utilise au contraire la
   devise des réglages. Deux écrans, un même chiffre, deux symboles (§7).

---

*Audit effectué en lecture seule le 2026-09-13. Aucun fichier du projet modifié, aucun build,
aucun test exécuté. Les montants « produits » proviennent d'un rejeu Decimal du moteur
reproduisant `DeclarativeMileageRule` instruction par instruction contre les JSON réellement
livrés ; les montants « attendus » sont calculés à la main depuis
`docs/mileage-rules-sources.md`.*
