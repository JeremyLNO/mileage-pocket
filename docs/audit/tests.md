# Audit — est-ce que les tests prouvent quoi que ce soit ?

Périmètre : `Tests/` (163 tests), `UITests/` (13 tests), `tools/run-tests.sh`.
Méthode : lecture seule. Aucun build, aucun `xcodebuild`, aucun fichier du projet modifié.
Chaque constat « confirmé » nomme la **mutation du code de production qui survivrait**.

Décompte vérifié : 163 + 13 = 176. Aucun `XCTSkip`, aucun test désactivé dans le scheme
(`MileagePocket.xcscheme` : les deux `TestableReference` sont `skipped = "NO"`), aucun
`.xctestplan`. Les deux incidents passés (horloge système dans `TripGrouping`, trajet laissé
en cours par un test UI) sont réellement corrigés et couverts.

---

## 1. Tautologies confirmées

### 1.1 CRITIQUE — `UITests/TripFlowUITests.swift:68` `testTheDailyLoopStaysWithinItsTapBudget`

```swift
var taps = 0
start.tap(); taps += 1
stop.tap();  taps += 1
business.tap(); taps += 1
save.tap();  taps += 1
XCTAssertLessThanOrEqual(taps, 4, "the everyday loop must not cost more than four taps")
```

`taps` vaut 4 par construction : c'est un compteur des lignes du test lui-même, pas du
produit. **Aucune mutation du code de production ne peut faire échouer cette assertion.**
Si l'app exigeait dix taps de plus, le test échouerait sur un `waitForExistence`, pas sur le
budget — et le budget est précisément ce que le test prétend mesurer. Le test ne peut mordre
que si un contrôle disparaît, ce que `testStartDriveStopClassifyAndSave` fait déjà.

### 1.2 CRITIQUE — `Tests/FrequentLocationTests.swift:51` `testVisitCountingAccumulatesOnRepeatVisits`

```swift
XCTAssertEqual(location.visitCount, 1)
location.visitCount += 1
location.visitCount += 1
XCTAssertEqual(location.visitCount, 3)
```

Le test teste l'opérateur `+=` de Swift. Le compteur de visites en production est
`App/AppDependencies+Data.swift:138` (`existing.visitCount += 1` dans `learnDestination`),
appelé depuis `AppDependencies.finishTrip`. **Aucun test n'atteint cette ligne.**

- Mutation survivante : supprimer `App/AppDependencies+Data.swift:138` → suite verte.
- Mutation survivante : supprimer `learnDestination(from:)` de `finishTrip` → suite verte.

### 1.3 MAJEUR — `Tests/LocalizationTests.swift:100` `testPluralRulesSelectDifferentFormsForOneAndMany`

```swift
let one  = L.plural("home.business.trips", 1)   // "1 business trip"
let many = L.plural("home.business.trips", 5)   // "5 business trips"
XCTAssertNotEqual(one, many, "a count of 1 must not read like a count of 5")
```

Les deux chaînes contiennent le compte interpolé (`%lld`). Elles diffèrent donc **toujours**,
que la règle de pluriel existe ou non.

- Mutation survivante : dans `Resources/Localizable.xcstrings`, remplacer les variations
  `one`/`other` de `home.business.trips` par un `stringUnit` unique `"%lld business trips"`
  → `"1 business trips"` ≠ `"5 business trips"` → test vert, et l'app affiche « 1 business
  trips ».

### 1.4 MINEUR — `Tests/RulePackTests.swift:209` (uplift électrique France)

```swift
XCTAssertEqual(electric, MileageRounding.money(petrol * Decimal(string: "1.20")!))
```

Assertion recalculée avec la formule de l'implémentation. Sans danger ici uniquement parce
que la ligne suivante fige la valeur en dur (`763.20`) — c'est elle qui mord. La première
ligne est décorative.

### 1.5 MINEUR — `Tests/PersistenceTests.swift:62`

`trip.isManuallyEdited = true` n'a aucun effet : `Models/Trip.swift:76` est
`correctedDistanceMeters ?? rawDistanceMeters`, le drapeau n'entre pas dans le calcul.
Supprimer cette ligne du test ne change rien — le test suggère un couplage qui n'existe pas.

---

## 2. Seuils testés « autour » plutôt que PILE — et seuils testés pile mais aveugles

### 2.1 CRITIQUE — `Services/MileageRules/RulePackModels.swift:230` `RateBand.contains`

Deux tests se présentent comme testant la borne sur la borne :

- `Tests/MileageCalculationTests.swift:155` `testWholeBandBoundaryIsInclusiveOfTheLowerBand`
- `Tests/RulePackTests.swift:178` `testFranceIsContinuousAtTheFiveThousandKilometreBound`

Ils utilisent tous deux des barèmes **continus à la borne**, ce qui rend l'inclusivité
invisible :

| Barème | Bande basse à 5 000 | Bande haute à 5 000 |
|---|---|---|
| `wholeScheme` synthétique | 5 000 × 0,500 = **2 500** | 5 000 × 0,300 + 1 000 = **2 500** |
| Pack FR 2026 (5 CV) | 5 000 × 0,636 = **3 180** | 5 000 × 0,357 + 1 395 = **3 180** |

**Mutation survivante confirmée** : `RulePackModels.swift:230`, `return distance <= toDistance`
→ `return distance < toDistance`. La bande basse ne contient plus 5 000, la bande haute est
sélectionnée, et les deux tests retrouvent exactement 2 500,00 et 3 180,00. La seconde partie
du test France (1 km au-delà de 5 000 → 0,36) passe également : elle ne sollicite que la
bande haute dans les deux cas.

Aucun autre test du dépôt n'exerce `RateBand.contains` en mode `whole` sur un barème
discontinu. L'inclusivité des bandes « whole » — la règle que le commentaire de
`DeclarativeMileageRule.swift:95` décrit comme « the boundary is tested on the bound itself » —
n'est **pas** testée.

### 2.2 CRITIQUE — `Services/Location/FrequentLocationMatcher.swift:24`

`Tests/FrequentLocationTests.swift:32` `testTheRadiusBoundaryIsInclusive` prétend tester
150 m exactement (« 150 m est dedans, un mètre de plus est dehors »).

La fixture décale la latitude avec `Geodesy.metersPerDegreeLatitude` = 111 319,49 (rayon
**équatorial** WGS84, 6 378 137 m), alors que `Geodesy.distance` mesure en haversine avec le
rayon **moyen** 6 371 008,8 m. Les deux ne sont pas le même mètre :

| Décalage demandé | Distance réellement mesurée |
|---|---|
| 150 m | **149,832 m** |
| 151 m | **150,831 m** |

Le test sonde donc 149,83 m et 150,83 m, pas la borne. Mutations survivantes :

- `filter { $0.distance <= radiusMeters }` → `< radiusMeters` (149,83 < 150 reste vrai).
- `defaultRadiusMeters = 150` → `150.5` (149,83 ≤ 150,5 ✓ ; 150,83 > 150,5 ✓).
- `defaultRadiusMeters = 150` → `149.9`.

Le rayon peut dériver de ±0,8 m et l'inclusivité peut basculer sans qu'un test bouge.

### 2.3 Ce qui est correctement testé sur la borne (à conserver)

- `Tests/LocationFilterTests.swift:240` — précision 50 / 50,0001 m, pile sur `maxAccuracy`.
- `Tests/LocationFilterTests.swift:269` — la vitesse implicite est balayée **ulp par ulp**
  jusqu'au premier franchissement, avec le segment mesuré par le code sous test. C'est le
  meilleur test du dépôt.
- `Tests/AccessPolicyTests.swift:62` — `isActive(now: end)` faux à l'instant exact.
- `Tests/SubscriptionTests.swift:148` — `grantsAccess` avec `revokedAt == now` et
  `expiresAt == now`, plus `now + 0.001`.
- `Tests/TripGroupingTests.swift:41` — J-7 au démarrage du jour, et une seconde avant.
- `Tests/RulePackTests.swift:125` — HMRC exactement 10 000 miles, puis 1 mile au-delà.

---

## 3. Assertions qui ne mordent pas

### 3.1 MAJEUR — `Tests/RulePackTests.swift:215` `testIrelandBandsByEngineCapacity`

```swift
let withCapacity = try amount("IE", ..., vehicle: vehicle /* engineCapacity 1400 */)
XCTAssertGreaterThan(withCapacity, 0)
...
XCTAssertEqual(fallback, noVehicle, "an unknown displacement must fall back, not guess")
```

Dans `Resources/MileageRules/IE/*.json`, les `bands` de repli du schéma `motorTravel` sont
**identiques au caractère près** à la bande de puissance 1201–1500 cm³
(0,4340 / 0,7918 / 0,3179 / 0,2385). Le véhicule de test déclare 1 400 cm³ : il tombe donc
sur cette bande-là. Résultat : `withCapacity == fallback == noVehicle`, et le test ne
l'assertit jamais autrement que par `> 0`.

Mutations survivantes confirmées :

- `RulePackModels.swift:135` `basePowerBands(for:)` → `return bands` en toutes circonstances
  (les `powerBands` ne sont plus jamais lues) → vert.
- `RulePackModels.swift:137-140` → lire `vehicle?.fiscalHorsepower` même quand
  `powerUnit == .engineCapacity` → le véhicule `wrongFigure` (fiscalHorsepower = 1 400) tombe
  sur la même bande 1201–1500 → `fallback == noVehicle` reste vrai → vert. C'est exactement
  le bug que le commentaire du test dit surveiller.

Les trois paliers irlandais réels (0,4180 ≤ 1 200 / 0,4340 / 0,5182 ≥ 1 501) ne sont vérifiés
par **aucune valeur**. Un pack IE dont les `powerBands` seraient toutes corrompues passerait.

`testIrelandPowerUnitIsEngineCapacity` et `testFrancePowerUnitIsFiscalHorsepower` ne lisent
que le champ JSON : ce sont des détecteurs de changement de données, pas des tests de
comportement.

### 3.2 MOYEN — `Tests/AccessPolicyTests.swift:83` `testAnEarlierClockDoesNotExtendThePeriod`

```swift
XCTAssertTrue(period.isActive(now: start.addingTimeInterval(-86_400)))
XCTAssertLessThanOrEqual(period.daysRemaining(now: start.addingTimeInterval(-86_400)), 4)
```

`Core/Access/AccessPolicy.swift` ne contient **aucun clamp d'horloge arrière**. La valeur
produite est exactement 4 (3 jours de période + 1 jour de recul). Le test assertit `≤ 4`,
c'est-à-dire précisément ce que le code non protégé rend : le test documente l'absence de la
règle qu'il prétend imposer. Toute valeur dans ]-∞, 4] passe.

Corollaire : `AccessPolicy.swift:18`, le `max(1, …)` est inatteignable — le `guard isActive`
garantit déjà `endsAt - now > 0`, donc `.rounded(.up) ≥ 1`. Mutation survivante : supprimer
`max(1, …)` → l'assertion ligne 78 (« dix minutes restantes se lisent 1 jour ») reste verte.

### 3.3 MOYEN — Tests UI dont l'assertion est déjà garantie

- `UITests/LaunchUITests.swift:4` `testAppLaunches` : `XCUIApplication.launch()` échoue déjà
  si l'app n'atteint pas le premier plan. L'assertion qui suit ne peut mordre que dans une
  fenêtre de course. Une `RootView` rendue entièrement vide laisse le test vert.
- `UITests/PaywallUITests.swift:65` `testCaptureForAppStoreReview` : générateur de capture
  d'écran. Ses deux assertions sont des copies de celles de
  `testPaywallShowsLivePricesAndTheTrialOffer`. Zéro mode d'échec nouveau.

### 3.4 MINEUR

- `Tests/PersistenceTests.swift:11` `testSchemaOpensWithEveryModel` : doublon de
  `makeContext()`, utilisé par quatre autres tests du même fichier qui échoueraient d'abord.
- `Tests/ReportTests.swift:210` `testPDFPaginatesLongReports` : `pageCount >= 3`. Mord bien
  dans le sens « lignes silencieusement perdues », mais une mutation « une ligne par page »
  (120 pages) reste verte.
- `Tests/RouteCompactorTests.swift:80` : seuil de 6 Ko pour un blob qui pèse ~2,9 Ko d'après
  le commentaire de `RouteCompactor.swift:88`. Le seuil est à 2× la réalité ; une mutation qui
  double la taille (par ex. `coordinateScale` 1e5 → 1e7) passe, d'autant que le round-trip
  n'assertit qu'une précision de 1e-5 degré.

---

## 4. Tests sautés en silence

### 4.1 MAJEUR — `UITests/RawKeyUITests.swift:52`

```swift
let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Car")).firstMatch
if picker.waitForExistence(timeout: 3) {
    picker.tap()
    XCTAssertTrue(app.buttons["Van"].waitForExistence(timeout: 5), "…")
    assertNoRawKeys(in: app, screen: "onboarding — vehicle type menu")
}
```

Le menu du picker est **le seul endroit** où le bug historique (`vehicle.type.%@` dessiné à
l'écran) apparaissait — le commentaire d'en-tête du fichier le dit explicitement. Cette
vérification est enfermée dans un `if` sans `else`, donc sautable sans que rien ne soit
signalé.

Mutation survivante : `Features/Onboarding/OnboardingFlow.swift:17`,
`@State private var vehicleType = VehicleType.car` → `.van`. Le bouton n'affiche plus « Car »,
le `if` est faux, le menu n'est jamais ouvert, et `testOnboardingShowsNoRawKeys` passe au vert
sans avoir rien asserté sur la raison d'être du fichier. Même effet si l'app démarre dans une
autre langue (`Voiture`, `Auto`, `Coche`) — et les tests UI sont censés tourner en anglais
par convention, ce qui n'est appliqué par aucune assertion.

Correctif : remplacer le `if` par un `XCTAssertTrue(picker.waitForExistence(timeout: 5))`.

### 4.2 Non-problèmes vérifiés

- `UITests/UITestSupport.swift:24` `guard stop.waitForExistence(timeout: 3) else { return }` :
  c'est du nettoyage conditionnel, pas une assertion sautée. Correct.
- `Tests/LocationFilterTests.swift:293`, `Tests/TripRecorderTests.swift:167`,
  `Tests/SubscriptionTests.swift:98` : tous les `guard … else` appellent `XCTFail`. Corrects.
- `Tests/SubscriptionTests.swift:29` : `XCTAssertFalse(session.storefront.isEmpty)` — le
  garde-fou qui empêche une session StoreKit inerte (runtimes iOS 26.x) de se présenter comme
  « aucun produit ». Exactement la bonne façon de faire.

---

## 5. Helpers de test qui masquent le code de production

### 5.1 CRITIQUE — `Tests/ReportTests.swift:33` : le montant est écrit par le test

```swift
trip.mileageRate = Decimal(string: "0.45")
trip.calculatedAmount = amount.flatMap { Decimal(string: $0) }   // "10.00" par défaut
trip.mileageRuleVersion = version
```

`ReportBuilder.build` ne fait que sommer `trip.calculatedAmount`
(`Services/Reports/ReportBuilder.swift:76`). Les 18 tests de `ReportTests` additionnent donc
des nombres que la fixture a elle-même posés.

En production, le seul endroit qui écrit ces champs est
`App/AppDependencies.swift:259` `applyCalculation(to:)` — qui choisit la règle du jour du
trajet, va chercher la distance annuelle déjà parcourue, applique le barème, et fige
`mileageRate` / `calculatedAmount` / `currencyCode` / `mileageRuleVersion` / `isOfficialRate`.
**Aucun test n'appelle `applyCalculation`.**

Mutation survivante : remplacer le corps de `applyCalculation` par
`trip.calculatedAmount = 0; trip.mileageRate = 0` → les 163 tests unitaires restent verts. Les
21 tests de `MileageCalculationTests` prouvent le moteur, les 25 de `RulePackTests` prouvent
les données, et **rien** ne prouve que le moteur est branché sur les trajets. Le chemin
« un trajet enregistré devient un montant » n'a aucune couverture.

Conséquences directes, toutes non testées :
- le passage de `trip.tripType == .personal` à montant 0 (`AppDependencies.swift:263`) ;
- l'appel `yearlyDistanceMeters(before:in:)` **sans calendrier injecté** (donc `.current`,
  alors que le test correspondant, `ReportTests.swift:127`, passe un calendrier Europe/Paris) ;
- le choix du véhicule (`vehicle(for: trip.vehicleID)`), donc toute la sélection par bande de
  puissance en situation réelle.

### 5.2 MAJEUR — `UITests/PaywallUITests.swift:20` : `--fake-store` court-circuite StoreKit

```swift
app.launchArguments = ["--screen=paywall", "--demo-data-only", "--fake-store"]
...
// « Prices come from StoreKit, never from a literal in the UI. Asserting the configured
//   amounts proves the products loaded *and* that nothing is hard-coded elsewhere. »
let monthly = app.staticTexts["$2.99"]
```

Le commentaire est faux dans cette configuration. `SubscriptionService.plans`
(`Services/Subscription/SubscriptionService.swift:27`) bascule sur
`PaywallPlan.fromBundledConfiguration()` dès que `products.isEmpty`, et le test lui-même
explique que la session StoreKit du scheme n'atteint pas l'app sous test. Les prix affichés
sont donc lus dans `Config/MileagePocket.storekit` par du code `#if DEBUG`
(`Features/Paywall/PaywallPlan.swift:33`), pas par le chemin de production
`PaywallPlan.init(product:)`.

Idem pour le « 16 % » : il vient de `SubscriptionService.fakeAnnualSavingsPercent`
(ligne 50), un duplicata DEBUG de la formule réelle (ligne 42).

Mutations survivantes :
- `PaywallPlan.swift:19` `self.displayPrice = product.displayPrice` → `= "—"` → les trois
  tests UI du paywall restent verts.
- `SubscriptionService.swift:46` `ratio * 100` → `ratio` → le UI test reste vert.

Seul `Tests/SubscriptionTests.swift` (SKTestSession réelle, produits non vides) couvre le
chemin de production. Le test UI ne prouve que la mise en page.

### 5.3 MOYEN — `Tests/TripRecorderTests.swift:142` : l'état interrompu est construit à la main

`testResumeIfNeededPicksUpAnInterruptedTrip` fabrique lui-même la ligne `ActiveTripState`
(tripID, distance 4 321 m, `startLatitude`/`startLongitude`, `lastUpdatedAt`). Ce n'est **pas**
une critique : `testActiveTripStateIsRewrittenForEveryAcceptedFix` (ligne 196) vérifie
séparément que la production écrit bien cette ligne à chaque fix accepté, y compris les
coordonnées et l'horodatage. Les deux tests se referment l'un sur l'autre. C'est le bon
motif, et il manque ailleurs.

Réserve mineure : aucun test ne couvre `resumeIfNeeded` quand la ligne existe mais que les
`LocationPoint` correspondants ont disparu (`routeSamples` vide) ni la reprise d'un trajet
laissé en `.paused`.

---

## 6. Dépendance à l'ordre, à l'horloge ou à l'état partagé

### 6.1 MOYEN — `Tests/RulePackTests.swift:15` lit le cache disque de l'app hôte

```swift
store = RulePackStore()
```

L'initialiseur par défaut charge le bundle **et** `RulePackStore.defaultCacheDirectory`
(`Application Support/MileageRules`), c'est-à-dire le répertoire dans lequel
`RulePackUpdater.cache(_:)` écrit. La cible de tests est hébergée par l'app (`SmokeTests`
lit `Bundle.main.bundleIdentifier` et attend celui de l'app), et `AppDependencies` lance
`rulePackUpdater.refresh()` à chaque démarrage (`AppDependencies.swift:123`).

Aujourd'hui l'endpoint n'est pas déployé, donc le cache reste vide et la suite est verte. Le
jour où il l'est, ou si un pack est déposé à la main, `testEveryExpectedCountryShips`
(égalité stricte sur l'ensemble des pays) casse, et les montants en dur peuvent devenir faux
sans que la cause soit visible. C'est un test qui dépend d'un état qu'un autre processus
laisse derrière lui.

Correctif : `RulePackStore(bundle: .main, cacheDirectory: nil)` dans `setUp`. Le seam existe
déjà (`RulePackStore.swift:15`).

### 6.2 Sain — le reste

- `Tests/AccessPolicyTests.swift:95-108` : `InstallDateStoreTests` sauvegarde l'item keychain
  dans `setUp` et le restaure dans `tearDown`. C'est exactement la précaution qui manquait
  ailleurs ; le keychain survit à la désinstallation, donc à la suite.
- `RulePackTests`, `ReportTests`, `TripGroupingTests`, `MileageCalculationTests` figent toutes
  leurs dates (2026-09-12, 2026-06-01, `timeIntervalSince1970` explicites) et injectent un
  `Calendar` avec fuseau explicite. Aucune ne lira `Date.now`.
- `RouteFixtures.epoch = Date(timeIntervalSinceReferenceDate: 0)` avec la justification ulp
  (`RouteFixtures.swift:16`) : c'est ce qui rend le test de borne de vitesse exact.
- `RouteFixtures.DeterministicGaussian` : LCG graine fixe, pas de `Double.random`. Un échec
  est reproductible.
- `testGroupingIgnoresTheSystemClockEntirely` et `testAFutureTimestampIsGroupedAsToday`
  ferment bien l'incident d'horloge passé.
- `discardTripInProgress` dans `launchApp` ferme bien l'incident d'ordre passé.

### 6.3 `tools/run-tests.sh`

- Lignes 20-22 : `simctl bootstatus` et `simctl privacy grant location-always` sont suivis de
  `|| true`. Si l'octroi de permission échoue (réinstallation, UDID changé), le script
  continue et l'échec ressort comme une distance nulle dans `TripFlowUITests`, c'est-à-dire
  comme un bug applicatif. Le commentaire d'en-tête décrit précisément ce piège — et le script
  l'avale quand même. Un `|| { echo …; exit 1; }` coûterait deux lignes.
- Ligne 24 : la simulation de trajet est lancée en arrière-plan, `LOCATION_PID` n'est jamais
  vérifié vivant après le `sleep 2`. Même conséquence.
- `DEVICE_ID` par défaut est un UDID en dur ; sur une autre machine, `xcodebuild` échoue
  franchement (bon comportement).
- Aucun `-only-testing` / `-skip-testing` : la suite entière tourne. Bon point.

---

## 7. Ce qui n'est pas testé du tout

Fichiers de production sans **aucune** référence depuis `Tests/` ni `UITests/` :

**Chemin critique métier (argent, sécurité, données)**
- `App/AppDependencies.swift` + `App/AppDependencies+Data.swift` (~330 lignes) : `applyCalculation`
  (§5.1), `learnDestination`/`suggestedDestination`, `createManualTrip`, `duplicate`,
  `client(named:)` (déduplication insensible à la casse), `saveVehicle` (invariant « exactement
  un véhicule par défaut »), `export`, `exportAllData`, `deleteAllData` (et son invariant
  documenté « ne pas re-offrir la période gratuite »), `reportProfile`, `refreshWidgetSnapshot`,
  `subscriptionDescription`.
- `Services/MileageRules/RulePackVerifier.swift` : **vérification de signature Ed25519 d'un
  barème fiscal arrivant du réseau. Zéro test.** Mutation survivante : `verify(...)` →
  `return true`. Rien ne casse. C'est la seule barrière entre l'endpoint et les montants
  déclarés au fisc.
- `Services/MileageRules/RulePackUpdater.swift` : HTTP + code 200, décodage, garde de
  signature, `isNewer` (anti-rejeu d'un pack plus ancien), écriture du cache. Zéro test, alors
  que le seam d'injection `session:` existe déjà dans l'initialiseur.
- `Core/Persistence/SettingsStore.swift`, `Core/Persistence/CloudKitAvailability.swift`.

**Périphérie**
- `Features/Home/HomeModel.swift` (le total du mois affiché en page d'accueil).
- `Core/Country/CountryCatalog.swift`, `Core/Localization/LocalizationService.swift`
  (`L.string`/`L.format`/`L.plural` ne sont exercés que comme sonde de catalogue).
- `Services/Notifications/NotificationService.swift`,
  `Services/LiveActivity/TripActivityController.swift`, `MileageWidgets/*`,
  `Shared/WidgetSnapshot.swift`, `Shared/TripAttributes.swift`.
- `Services/Location/CoreLocationProvider.swift` et `LocationSample+CoreLocation.swift` : seul
  le double `FakeLocationProvider` est exercé ; la conversion `CLLocation → LocationSample` et
  la gestion d'autorisation réelles ne sont couvertes que par le trajet simulé des tests UI.
- Toutes les vues SwiftUI (`Features/**/*View.swift`, `OnboardingFlow`, `TripSummarySheet`) —
  couvertes uniquement par les 13 tests UI, eux-mêmes concentrés sur 4 écrans.
- `Core/DesignSystem/*`, `Core/Debug/DemoMode.swift`.

**Branches jamais assertées dans du code par ailleurs testé**
- `FilterRejection.belowNoiseFloor` : produite par `LocationFilter.swift:206`, jamais assertée
  (elle est exercée indirectement par les fixtures stationnaires).
- `RateScheme.matches(vehicle:)`, branche `fuelTypes` (`RulePackModels.swift:115`) : aucun des
  12 packs livrés ne renseigne `fuelTypes`, et aucun test synthétique ne la construit.
- `RulePack.isValid(on:)`, borne `validUntil` **exactement** à la date d'expiration : testée
  seulement avec une date largement dépassée (`MileageCalculationTests.swift:276`).
- `RouteCompactor.decode`, troncature en milieu de varint (les deux cas testés sont vide et
  version invalide).
- `SubscriptionService.gracePeriodEntitlement()` : la fonction asynchrone réelle. Seule la
  fonction pure `entitlement(for:)` est testée — choix assumé et documenté, mais le câblage
  entre les deux ne l'est pas.

---

## 8. Verdict

| Catégorie | Nb |
|---|---|
| Tests qui contraignent réellement le code de production | ~150 |
| Tests qui ne peuvent échouer sur aucune mutation de production | **8** |
| Tests qui prouvent nettement moins que leur nom | **~14** |

Les 8 incapables d'échouer : `testTheDailyLoopStaysWithinItsTapBudget`,
`testVisitCountingAccumulatesOnRepeatVisits`, `testPluralRulesSelectDifferentFormsForOneAndMany`,
`testIrelandBandsByEngineCapacity`, `testAppLaunches`, `testCaptureForAppStoreReview`,
`testTheRadiusBoundaryIsInclusive` (sur l'inclusivité), `testWholeBandBoundaryIsInclusiveOfTheLowerBand`.

La suite est forte là où le code est pur et faible là où il est branché. `LocationFilter`,
`DeclarativeMileageRule`, `RouteCompactor`, `AccessPolicy`, `SubscriptionService.grantsAccess`,
`TripGrouping` et les 12 packs de barèmes sont sérieusement contraints — le test de borne de
vitesse implicite balayé ulp par ulp est un modèle du genre.

Mais le **glue code** — les ~330 lignes d'`AppDependencies` qui transforment un trajet
enregistré en un montant, apprennent les lieux fréquents, écrivent le snapshot du widget et
suppriment les données — a **0 %** de couverture, et la vérification de signature des barèmes
fiscaux téléchargés (`RulePackVerifier`) n'a **aucun** test. Un moteur prouvé qu'on ne prouve
jamais branché, et une serrure qu'on ne prouve jamais fermée.

### Les cinq corrections par ordre de rendement

1. Tester `AppDependencies.applyCalculation` sur un trajet réel (business/personal, distance
   annuelle, véhicule) — ferme §5.1, la plus grosse lacune du dépôt.
2. Un test de `RulePackVerifier.verify` : payload valide accepté, payload muté rejeté, et un
   `RulePackUpdater` avec `URLSession` injectée pour couvrir 200 / signature invalide / pack
   plus ancien.
3. Rendre visible la borne « whole » : ajouter au `wholeScheme` synthétique une bande
   **discontinue** à 5 000, puis asserter la valeur pile sur la borne (§2.1).
4. `RulePackTests` : `RulePackStore(bundle: .main, cacheDirectory: nil)` (§6.1) ; et pour
   l'Irlande, asserter les trois paliers par leur valeur, avec un véhicule à 1 100 cm³ et un
   à 1 600 cm³, qui diffèrent du repli (§3.1).
5. `RawKeyUITests` : `XCTAssertTrue(picker.waitForExistence(...))` à la place du `if` (§4.1) ;
   et supprimer `testTheDailyLoopStaysWithinItsTapBudget`, qui ne mesure que lui-même (§1.1).
