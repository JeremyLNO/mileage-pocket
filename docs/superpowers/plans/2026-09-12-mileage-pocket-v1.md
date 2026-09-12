# Mileage Pocket V1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer une app iOS native complète de suivi kilométrique professionnel — start/stop GPS en arrière-plan, historique, calcul international, rapports PDF/CSV, abonnement StoreKit avec essai 3 jours — compilable, testée et prête pour l'App Store.

**Architecture:** SwiftUI + SwiftData(+CloudKit), injection de dépendances par `AppDependencies` dans l'environnement, services derrière des protocoles pour la testabilité. Moteur fiscal déclaratif lisant des rule packs JSON signés. `project.pbxproj` généré par script Python (aucune ouverture de Xcode requise).

**Tech Stack:** Swift 6, SwiftUI, SwiftData, CoreLocation, MapKit, PDFKit/CoreGraphics, StoreKit 2, ActivityKit, WidgetKit, UserNotifications, XCTest.

## Global Constraints

- Bundle ID : `Mileage.lno.company` — App Store Connect app `6811426601`, team `2E6D4Q69QB`
- `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `SWIFT_VERSION = 6.0`, device family `1` (iPhone uniquement)
- 6 langues : `en`, `fr`, `es`, `de`, `it`, `pt` — **aucun texte UI en dur**, tout dans `Resources/Localizable.xcstrings`
- Tout `input`/label visible passe par `String(localized:)` ou une clé `LocalizedStringKey`
- Produits StoreKit : `company.lno.mileage.monthly`, `company.lno.mileage.annual` — **prix jamais en dur dans l'UI**, toujours `product.displayPrice`
- Aucune dépendance tierce. Frameworks Apple uniquement.
- CloudKit : toute propriété SwiftData optionnelle ou avec valeur par défaut, **aucun `@Attribute(.unique)`**, aucune relation non-optionnelle
- Aucun taux fiscal inventé : un rule pack sans `sourceURL` officielle vérifiée n'est pas livré
- Build : `./build-run.sh` (regénère le pbxproj, build simulateur, install, launch). **Jamais de flag `-sdk`.**
- Tests StoreKit : runtime **iOS 18.6** uniquement (StoreKit Testing est inerte sur iOS 26.x)
- Captures d'écran : en anglais

---

## Structure de fichiers

```
mileage-pocket/
  gen_pbxproj.py                      génération déterministe du projet Xcode
  build-run.sh                        build + install + launch simulateur
  Config/MileagePocket.xcconfig       bundle id, version, team
  App/
    MileagePocketApp.swift            @main, ModelContainer, AppDependencies
    RootView.swift                    aiguillage onboarding / tabs / trajet actif
    AppDependencies.swift             conteneur d'injection
    MainTabView.swift                 Home / Trips / Reports / Settings
  Core/
    DesignSystem/Theme.swift          couleurs, dégradés, rayons
    DesignSystem/Typography.swift     échelle typographique
    DesignSystem/Components.swift     PrimaryButton, StatCard, BigMetric, Pill
    Localization/AppLanguage.swift
    Localization/LanguageResolver.swift
    Localization/LocalizationService.swift
    Formatting/MeasurementFormatting.swift  distance, devise, durée, dates
    Persistence/PersistenceController.swift ModelContainer + CloudKit
  Models/
    Trip.swift  LocationPoint.swift  Vehicle.swift  Client.swift  Project.swift
    UserSettings.swift  FrequentLocation.swift  ActiveTripState.swift
    Enums.swift                       TripType, DistanceUnit, VehicleType, FuelType, RateMode
  Services/
    Location/LocationFilter.swift     filtrage pur, testable
    Location/RouteCompactor.swift     RDP + encodage/décodage polyline
    Location/TripRecorder.swift       CLLocationManager, background, persistance
    Location/GeocodingService.swift   CLGeocoder départ/arrivée seulement
    MileageRules/RulePackModels.swift schéma JSON décodable
    MileageRules/MileageRule.swift    protocole + MileageCalculation
    MileageRules/DeclarativeMileageRule.swift  interpréteur générique
    MileageRules/CountryRuleEngine.swift        résolution pays → règle
    MileageRules/RulePackStore.swift  chargement bundle + cache disque
    MileageRules/RulePackVerifier.swift  vérification Ed25519
    MileageRules/RulePackUpdater.swift   fetch distant, non bloquant
    Reports/ReportPeriod.swift        Month/Quarter/Year/Custom
    Reports/ReportBuilder.swift       agrégation, totaux
    Reports/PDFReportRenderer.swift   rendu PDF paginé
    Reports/CSVExporter.swift         RFC 4180
    Subscription/SubscriptionService.swift  StoreKit 2
    LiveActivity/TripActivityController.swift
    Notifications/NotificationService.swift
  Features/
    Onboarding/  Home/  ActiveTrip/  Trips/  TripDetail/  ManualTrip/
    Vehicles/  Reports/  Settings/  Paywall/
  Shared/                             compilé dans app + widget
    TripAttributes.swift              ActivityAttributes de la Live Activity
    WidgetSnapshot.swift              données du widget via App Group
  Resources/
    Localizable.xcstrings  Assets.xcassets  PrivacyInfo.xcprivacy
    MileageRules/<ISO>/<version>.json
  MileageWidgets/                     WidgetBundle : StartTripWidget + TripLiveActivity
  Tests/  UITests/
```

---

### Task 1 : Squelette du projet et build vert

**Files:**
- Create: `gen_pbxproj.py`, `build-run.sh`, `Config/MileagePocket.xcconfig`, `App/MileagePocketApp.swift`, `App/RootView.swift`, `Resources/Assets.xcassets/`, `Resources/Localizable.xcstrings`, `Tests/SmokeTests.swift`, `.gitignore`

**Interfaces:**
- Produces: cibles `MileagePocket`, `MileageWidgetsExtension`, `MileagePocketTests`, `MileagePocketUITests` ; script `./build-run.sh` ; `AppLanguage` pas encore requis ici.

- [ ] **Step 1** — Copier `~/pillo-app/gen_pbxproj.py` et l'adapter : `PROJ = "MileagePocket"`, `APP_ONLY_DIRS = ["App", "Core", "Models", "Services", "Features"]`, `SHARED_DIR = "Shared"`, une seule extension (`MileageWidgets`, `dst_subfolder_spec 13`, `device_family "1"`), pas de SPM, `IPHONEOS_DEPLOYMENT_TARGET 18.0`, capabilities : background modes `location`, App Group `group.company.lno.mileage`, iCloud container `iCloud.company.lno.mileage`.
- [ ] **Step 2** — `Config/MileagePocket.xcconfig` : `BUNDLE_IDENTIFIER = Mileage.lno.company`, `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`, `DEVELOPMENT_TEAM = 2E6D4Q69QB`. ⚠️ Pas de guillemets autour des valeurs, pas de `//` dans une valeur (voir mémoire `xcconfig_url_gotchas`).
- [ ] **Step 3** — `MileagePocketApp.swift` minimal affichant `Text("Mileage Pocket")`, `Info.plist` avec `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `UIBackgroundModes = [location]`, `NSSupportsLiveActivities = true`.
- [ ] **Step 4** — `Tests/SmokeTests.swift` : `XCTAssertEqual(Bundle.main.bundleIdentifier, "Mileage.lno.company")` côté app.
- [ ] **Step 5** — Lancer `./build-run.sh`. Attendu : BUILD SUCCEEDED, app lancée sur le simulateur. Capturer une capture d'écran pour preuve.
- [ ] **Step 6** — Commit `chore: scaffold MileagePocket Xcode project`.

---

### Task 2 : Modèles SwiftData + persistance CloudKit

**Files:**
- Create: `Models/*.swift`, `Core/Persistence/PersistenceController.swift`, `Tests/PersistenceTests.swift`

**Interfaces:**
- Produces:
  - `enum TripType: String, Codable { case business, personal }`
  - `enum DistanceUnit: String, Codable { case kilometers, miles }` avec `metersPerUnit: Double`
  - `enum VehicleType: String, Codable { case car, motorcycle, moped, bicycle, van, electricCar }`
  - `enum FuelType: String, Codable { case petrol, diesel, hybrid, electric, other }`
  - `enum RateMode: String, Codable { case official, employer, custom }`
  - `@Model final class Trip` — toutes propriétés optionnelles ou avec défaut, `id: UUID = UUID()`
  - `@Model final class Vehicle`, `Client`, `Project`, `UserSettings`, `FrequentLocation`, `LocationPoint`, `ActiveTripState`
  - `enum PersistenceController { static func makeContainer(cloudKitEnabled: Bool, inMemory: Bool) throws -> ModelContainer }`

- [ ] **Step 1** — Écrire `Tests/PersistenceTests.swift` : créer un conteneur en mémoire avec tous les modèles, insérer un `Trip`, sauvegarder, relire, vérifier l'égalité des champs. Un second test vérifie qu'un `Trip` créé sans aucun paramètre ne lève pas (toutes valeurs par défaut présentes).
- [ ] **Step 2** — Lancer les tests : échec (types inexistants).
- [ ] **Step 3** — Écrire `Models/Enums.swift` puis chaque `@Model`. Rappel CloudKit : `var vehicleID: UUID?` plutôt qu'une relation obligatoire ; les relations SwiftData utilisées (`Trip.vehicle`) doivent être optionnelles avec `deleteRule: .nullify`.
- [ ] **Step 4** — `PersistenceController.makeContainer` : `ModelConfiguration(cloudKitDatabase: cloudKitEnabled ? .private("iCloud.company.lno.mileage") : .none)`.
- [ ] **Step 5** — Lancer les tests : PASS. Puis `./build-run.sh` pour vérifier que l'app compile toujours.
- [ ] **Step 6** — Commit `feat: SwiftData models and CloudKit-ready persistence`.

---

### Task 3 : Design system, localisation, formatage

**Files:**
- Create: `Core/DesignSystem/*.swift`, `Core/Localization/*.swift`, `Core/Formatting/MeasurementFormatting.swift`, `Tests/LocalizationTests.swift`, `Tests/FormattingTests.swift`

**Interfaces:**
- Produces:
  - `enum AppLanguage: String, CaseIterable { case en, fr, es, de, it, pt }` + `nativeName`, `locale`
  - `enum LanguageResolver { static func resolve(hasExplicitOverride: Bool, selectedLanguage: String?, preferredLanguages: [String]) -> AppLanguage }`
  - `@Observable @MainActor final class LocalizationService` avec `currentLanguage`, `setLanguage(_:)`
  - `enum Fmt { static func distance(meters: Double, unit: DistanceUnit, locale: Locale) -> String ; static func money(_ amount: Decimal, currencyCode: String, locale: Locale) -> String ; static func duration(_ seconds: TimeInterval) -> String ; static func timer(_ seconds: TimeInterval) -> String }`
  - `enum Theme` : `accent`, `businessTint`, `personalTint`, `surface`, `cardRadius`, dégradé du bouton START

- [ ] **Step 1** — `Tests/LocalizationTests.swift` : override explicite gagne ; sinon première langue système supportée ; sinon `.en`. Cas testés : `(true, "de", ["fr"]) -> .de`, `(false, nil, ["it-IT","en"]) -> .it`, `(false, nil, ["ja-JP"]) -> .en`.
- [ ] **Step 2** — `Tests/FormattingTests.swift` : `Fmt.distance(meters: 24300, unit: .kilometers, locale: en_US) == "24.3 km"` ; `Fmt.distance(meters: 24300, unit: .miles, ...) == "15.1 mi"` ; `Fmt.timer(1662) == "00:27:42"` ; `Fmt.money(15.73, "EUR", fr_FR)` contient `15,73` et `€`.
- [ ] **Step 3** — Lancer : échec.
- [ ] **Step 4** — Implémenter. `distance` utilise `Measurement<UnitLength>` + `.formatted(.measurement(width: .abbreviated, usage: .road))` ; `money` utilise `Decimal.formatted(.currency(code:).locale(_:))`.
- [ ] **Step 5** — Écrire `Theme`/`Typography`/`Components` : `PrimaryButton`, `StatCard`, `BigMetric(value:unit:)`, `TripTypePill`. Palette franche (accent orange/ambre CBL, vert « business », gris-bleu « personal »), coins 20-24 pt, ombres douces, support Light/Dark par `Color` d'asset catalog.
- [ ] **Step 6** — Tests PASS + build vert. Commit `feat: design system, localization and formatting`.

---

### Task 4 : Filtrage GPS et compaction de tracé (cœur critique, 100 % testable hors device)

**Files:**
- Create: `Services/Location/LocationFilter.swift`, `Services/Location/RouteCompactor.swift`, `Tests/LocationFilterTests.swift`, `Tests/RouteCompactorTests.swift`, `Tests/Fixtures/RouteFixtures.swift`

**Interfaces:**
- Produces:
  - `struct FilterConfig { var maxAccuracy: Double = 50; var maxSpeed: Double = 60; var maxStaleness: TimeInterval = 30; var tunnelBridgeMaxGap: TimeInterval = 300; var stopSpeed: Double = 1; var stopDuration: TimeInterval = 120 }`
  - `enum FilterDecision: Equatable { case accepted(distanceMeters: Double); case bridged(distanceMeters: Double); case rejected(FilterRejection); case paused }`
  - `enum FilterRejection: Equatable { case poorAccuracy, stale, outOfOrder, implausibleSpeed, belowNoiseFloor, gapTooLong }`
  - `struct LocationFilter { private(set) var totalDistanceMeters: Double ; mutating func accept(_ sample: LocationSample) -> FilterDecision }`
  - `struct LocationSample { let latitude, longitude, horizontalAccuracy, altitude, speed: Double; let timestamp: Date }` — construit depuis `CLLocation`, pour tester sans CoreLocation
  - `enum RouteCompactor { static func simplify(_ points: [LocationSample], toleranceMeters: Double) -> [LocationSample] ; static func encode(_ points: [LocationSample]) -> Data ; static func decode(_ data: Data) -> [LocationSample] }`

- [ ] **Step 1** — `Tests/Fixtures/RouteFixtures.swift` : génère une ligne droite de 1 000 m (points tous les 10 m), un trajet Paris→Versailles synthétique de distance connue, un bruiteur gaussien déterministe (seed fixe), un injecteur de saut aberrant, un trou de 60 s.
- [ ] **Step 2** — `Tests/LocationFilterTests.swift`, cas :
  1. ligne droite propre 1 000 m → distance accumulée à ±2 %
  2. même ligne + bruit σ=8 m → distance toujours à ±5 % (sans filtre elle exploserait : le test assertera aussi que la somme brute dépasse 1 200 m, prouvant que le filtre mord)
  3. point à `horizontalAccuracy = 120` → `.rejected(.poorAccuracy)`, distance inchangée
  4. saut de 5 km en 2 s → `.rejected(.implausibleSpeed)`
  5. point antérieur au précédent → `.rejected(.outOfOrder)`
  6. trou de 60 s à 25 m/s puis reprise cohérente → `.bridged`, distance incluse
  7. trou de 10 min → `.rejected(.gapTooLong)`, distance non comptée
  8. 3 min de points immobiles (bruit 3 m) → `.paused`, distance inchangée
  9. **borne exacte** : `horizontalAccuracy == 50` accepté, `50.0001` rejeté ; vitesse implicite `== 60 m/s` acceptée, `60.0001` rejetée
- [ ] **Step 3** — `Tests/RouteCompactorTests.swift` : simplification d'une ligne droite de 100 points → ≤ 2 points ; un virage marqué survit ; `decode(encode(p)) ≈ p` à 1e-5 près ; 720 points encodés pèsent < 6 Ko.
- [ ] **Step 4** — Lancer : échec.
- [ ] **Step 5** — Implémenter `LocationFilter` (règles 1→6 du spec §4) et `RouteCompactor` (Ramer–Douglas–Peucker + encodage `Int32` de lat/lon × 1e5 et delta-timestamps).
- [ ] **Step 6** — Tests PASS. Commit `feat: GPS filtering and route compaction`.

---

### Task 5 : TripRecorder — enregistrement, arrière-plan, reprise après crash

**Files:**
- Create: `Services/Location/TripRecorder.swift`, `Services/Location/GeocodingService.swift`, `Tests/TripRecorderTests.swift`

**Interfaces:**
- Consumes: `LocationFilter`, `LocationSample`, `RouteCompactor`, modèles `Trip`/`LocationPoint`/`ActiveTripState`
- Produces:
  - `protocol TripRecording: AnyObject { var state: RecorderState { get } ; func start(vehicleID: UUID?) throws ; func stop() async throws -> Trip ; func resumeIfNeeded() throws }`
  - `enum RecorderState: Equatable { case idle; case recording(startedAt: Date, distanceMeters: Double, duration: TimeInterval); case paused }`
  - `protocol LocationProviding: AnyObject { var onSample: ((LocationSample) -> Void)? { get set } ; func startUpdates() ; func stopUpdates() ; var authorization: CLAuthorizationStatus { get } ; func requestAlways() }`
  - `final class CoreLocationProvider: LocationProviding` — la seule classe qui touche `CLLocationManager`
  - `protocol Geocoding { func address(latitude: Double, longitude: Double) async -> String? }`

- [ ] **Step 1** — `Tests/TripRecorderTests.swift` avec un `FakeLocationProvider` :
  1. start → injecter la fixture 1 000 m → `state.distanceMeters ≈ 1000`
  2. stop → un `Trip` persisté avec `rawDistanceMeters ≈ 1000`, `encodedRoute` non vide, **zéro `LocationPoint` restant en base**
  3. simuler un crash : écrire un `ActiveTripState`, instancier un nouveau recorder, `resumeIfNeeded()` → `state == .recording`, distance restaurée
  4. `ActiveTripState` est réécrit à chaque point accepté (compteur d'écritures > 0 après 5 points)
  5. un trajet qui franchit minuit garde `startedAt` et `endedAt` corrects (pas de troncature au jour)
- [ ] **Step 2** — Lancer : échec.
- [ ] **Step 3** — Implémenter `CoreLocationProvider` : `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`, `activityType = .automotiveNavigation`, `desiredAccuracy = kCLLocationAccuracyBest`, `distanceFilter` adaptatif (10 m < 30 km/h, 25 m > 90 km/h), `showsBackgroundLocationIndicator = true`.
- [ ] **Step 4** — Implémenter `TripRecorder` : accumule via `LocationFilter`, insère les `LocationPoint`, réécrit `ActiveTripState`, et au `stop()` compacte le tracé, supprime les points, géocode départ/arrivée (**deux appels `CLGeocoder` seulement**, jamais par point), crée le `Trip`.
- [ ] **Step 5** — Tests PASS + build vert. Commit `feat: trip recorder with background tracking and crash recovery`.

---

### Task 6 : Rule packs — recherche des sources officielles et schéma

**Files:**
- Create: `Services/MileageRules/RulePackModels.swift`, `Resources/MileageRules/<ISO>/2026.1.json` (≈12 pays), `docs/mileage-rules-sources.md`, `Tests/RulePackDecodingTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct RulePack: Codable, Sendable {
      let country: String          // ISO 3166-1 alpha-2
      let version: String          // "2026.1"
      let validFrom: Date
      let validUntil: Date?
      let currencyCode: String     // ISO 4217
      let distanceUnit: DistanceUnit
      let source: String
      let sourceURL: URL
      let lastVerified: Date
      let notes: [String: String]? // clés de localisation
      let schemes: [RateScheme]
  }
  struct RateScheme: Codable, Sendable {
      let id: String
      let vehicleTypes: [VehicleType]
      let fuelTypes: [FuelType]?
      let powerBands: [PowerBand]?   // CV fiscaux (FR) ou cylindrée
      let bands: [RateBand]          // paliers de distance annuelle
  }
  struct PowerBand: Codable, Sendable { let minPower: Int?; let maxPower: Int?; let bands: [RateBand] }
  struct RateBand: Codable, Sendable {
      let fromDistance: Double       // dans l'unité du pack, cumul annuel
      let toDistance: Double?        // nil = ∞
      let rate: Decimal              // par unité de distance
      let constant: Decimal?         // terme additif (barème FR)
  }
  ```

- [ ] **Step 1** — **Rechercher chaque taux sur la source officielle** et consigner dans `docs/mileage-rules-sources.md` : pays, URL exacte, date de consultation, extrait du texte, valeur retenue. Sources à interroger : `impots.gouv.fr` / `service-public.fr` (FR), `irs.gov` (US), `gov.uk` HMRC (GB), `canada.ca` CRA (CA), `bundesfinanzministerium.de` (DE), `finances.belgium.be` (BE), `admin.ch` (CH), `ato.gov.au` (AU), `revenue.ie` (IE), `belastingdienst.nl` (NL), `sede.agenciatributaria.gob.es` (ES), `aci.it`/`agenziaentrate.gov.it` (IT), `portaldasfinancas.gov.pt` (PT).
- [ ] **Step 2** — **Tout pays dont la source ne peut être vérifiée est retiré** de la livraison et laissé en Custom rate. Documenter le retrait dans le même fichier. Ne jamais compléter au jugé.
- [ ] **Step 3** — Écrire un pack JSON par pays retenu.
- [ ] **Step 4** — `Tests/RulePackDecodingTests.swift` : chaque JSON embarqué décode sans erreur ; `sourceURL` en `https` ; `lastVerified` ≤ aujourd'hui ; bandes contiguës et croissantes ; aucun taux ≤ 0.
- [ ] **Step 5** — Tests PASS. Commit `feat: official mileage rule packs with verified sources`.

---

### Task 7 : Moteur de calcul kilométrique

**Files:**
- Create: `Services/MileageRules/MileageRule.swift`, `DeclarativeMileageRule.swift`, `CountryRuleEngine.swift`, `RulePackStore.swift`, `Tests/MileageCalculationTests.swift`

**Interfaces:**
- Consumes: `RulePack`, `Vehicle`, `DistanceUnit`
- Produces:
  - `struct MileageCalculation: Equatable { let amount: Decimal; let rate: Decimal; let currencyCode: String; let ruleVersion: String; let unit: DistanceUnit; let isOfficial: Bool }`
  - `protocol MileageRule { var countryCode: String { get }; var currencyCode: String { get }; var distanceUnit: DistanceUnit { get }; func calculate(distanceMeters: Double, vehicle: Vehicle?, date: Date, yearlyDistanceMeters: Double) -> MileageCalculation }`
  - `struct DeclarativeMileageRule: MileageRule` (init depuis un `RulePack`)
  - `struct CustomRateRule: MileageRule` (taux libre + devise + unité)
  - `final class CountryRuleEngine { func rule(for countryCode: String, mode: RateMode, customRate: Decimal?, customCurrency: String?, date: Date) -> MileageRule }`
  - `final class RulePackStore { func pack(country: String, on date: Date) -> RulePack? ; func availableCountries() -> Set<String> }`

- [ ] **Step 1** — `Tests/MileageCalculationTests.swift`, **valeurs calculées à la main depuis les sources du Task 6** :
  1. taux plat : distance × taux, arrondi à 2 décimales
  2. paliers GB : une distance juste sous la borne, **pile sur la borne**, juste au-dessus — les trois vérifiées séparément
  3. barème FR avec constante : `d × k + c` pour une puissance fiscale donnée, et le passage d'une bande à l'autre testé pile sur la borne
  4. `yearlyDistanceMeters` déjà consommé décale correctement l'entrée dans les paliers (un trajet qui chevauche une borne est facturé en deux parties)
  5. unité : un pack en miles calcule juste quand la distance interne est en mètres
  6. pays sans pack → `CustomRateRule`, `isOfficial == false`
  7. date antérieure à `validFrom` → le pack n'est pas retenu
  8. véhicule `nil` → le schéma par défaut (`car`) s'applique sans crash
- [ ] **Step 2** — Lancer : échec.
- [ ] **Step 3** — Implémenter. Toute l'arithmétique en `Decimal` (jamais `Double`) pour les montants.
- [ ] **Step 4** — Tests PASS. Commit `feat: declarative international mileage calculation engine`.

---

### Task 8 : Signature et mise à jour distante des rule packs

**Files:**
- Create: `Services/MileageRules/RulePackVerifier.swift`, `RulePackUpdater.swift`, `tools/sign_rule_packs.py`, `Tests/RulePackVerifierTests.swift`

**Interfaces:**
- Produces:
  - `enum RulePackVerifier { static func verify(payload: Data, signature: Data, publicKey: Curve25519.Signing.PublicKey) -> Bool }`
  - `actor RulePackUpdater { func refresh() async }` — non bloquant, silencieux en cas d'échec
  - `struct SignedBundle: Codable { let payload: Data; let signature: Data; let version: String }`

- [ ] **Step 1** — `Tests/RulePackVerifierTests.swift` : une charge signée avec une clé de test est acceptée ; la même charge d'un octet modifié est refusée ; une signature d'une autre clé est refusée ; un bundle dont la version est ≤ la version en cache est ignoré ; un échec réseau laisse le cache intact et `availableCountries()` inchangé.
- [ ] **Step 2** — Lancer : échec.
- [ ] **Step 3** — Implémenter avec `CryptoKit.Curve25519.Signing`. Clé publique en dur dans le binaire ; clé privée **hors dépôt** (`~/crazybee-license-signing/`). `tools/sign_rule_packs.py` produit le bundle signé.
- [ ] **Step 4** — `RulePackUpdater` : `URLSession` avec `timeoutIntervalForRequest = 10`, appelé au lancement en tâche détachée, jamais sur un chemin bloquant l'UI. URL cible `https://crazybeelabs.com/api/mileage-rules/v1` (non déployée en V1 — l'échec est normal et silencieux).
- [ ] **Step 5** — Tests PASS. Commit `feat: signed rule pack verification and background updater`.

---

### Task 9 : Abonnement StoreKit 2

**Files:**
- Create: `Services/Subscription/SubscriptionService.swift`, `ProductIDs.swift`, `Config/MileagePocket.storekit`, `Tests/SubscriptionTests.swift`

**Interfaces:**
- Produces:
  - `enum ProductIDs { static let monthly = "company.lno.mileage.monthly"; static let annual = "company.lno.mileage.annual"; static let all: [String] }`
  - `enum Entitlement: Equatable { case none; case trial(expires: Date); case subscribed(productID: String, expires: Date?); case gracePeriod(expires: Date) }` + `var isActive: Bool`
  - `@Observable @MainActor final class SubscriptionService { private(set) var entitlement: Entitlement; private(set) var products: [Product]; func load() async; func purchase(_ product: Product) async throws; func restore() async throws; var annualSavingsPercent: Int? }`

- [ ] **Step 1** — `Config/MileagePocket.storekit` : groupe `Mileage Pocket`, deux abonnements, offre d'introduction 3 jours gratuits sur chacun. Le fichier doit être **référencé par le scheme** (`gen_pbxproj.py` écrit `StoreKitConfigurationFileReference` dans le `.xcscheme`) — sinon StoreKit Testing est inerte.
- [ ] **Step 2** — `Tests/SubscriptionTests.swift` avec `SKTestSession` (**runtime iOS 18.6**) : produits chargés (2) ; achat mensuel → `entitlement.isActive` ; expiration → `.none` ; annulation → `.none` ; restauration → actif ; `annualSavingsPercent` calculé depuis les prix StoreKit et non codé en dur. Garde-fou en tête de test : si `session.storefront` est vide, échouer avec un message explicite (session morte).
- [ ] **Step 3** — Lancer : échec.
- [ ] **Step 4** — Implémenter : `Product.products(for:)`, `Transaction.currentEntitlements`, écoute de `Transaction.updates` dans une tâche détachée au lancement, vérification `VerificationResult` (jamais `.unverified` accepté).
- [ ] **Step 5** — Tests PASS sur iOS 18.6. Commit `feat: StoreKit 2 subscription service`.

---

### Task 10 : Rapports PDF et CSV

**Files:**
- Create: `Services/Reports/ReportPeriod.swift`, `ReportBuilder.swift`, `PDFReportRenderer.swift`, `CSVExporter.swift`, `Tests/ReportTests.swift`

**Interfaces:**
- Consumes: `Trip`, `Vehicle`, `MileageCalculation`, `Fmt`
- Produces:
  - `enum ReportPeriod { case month(Int, Int), quarter(Int, Int), year(Int), custom(Date, Date) ; var range: ClosedRange<Date> ; func title(locale: Locale) -> String }`
  - `struct ReportData { let period: ReportPeriod; let trips: [Trip]; let businessCount: Int; let totalDistanceMeters: Double; let totalAmount: Decimal; let currencyCode: String; let ruleVersions: Set<String> }`
  - `enum ReportBuilder { static func build(trips: [Trip], period: ReportPeriod, includePersonal: Bool) -> ReportData }`
  - `struct PDFReportRenderer { func render(_ data: ReportData, profile: ReportProfile) throws -> URL }`
  - `struct ReportProfile { let userName: String; let company: String?; let vehicle: Vehicle?; let countryCode: String; let ruleDescription: String; let locale: Locale; let unit: DistanceUnit }`
  - `enum CSVExporter { static func csv(_ data: ReportData, profile: ReportProfile) -> String ; static func write(_ csv: String, to url: URL) throws }`

- [ ] **Step 1** — `Tests/ReportTests.swift` :
  1. totaux : 3 trajets business + 2 personal, `includePersonal = false` → compte et somme exacts, montant en `Decimal` sans dérive
  2. période : un trajet du 31/12 23:50 au 01/01 00:10 appartient à l'année de `startedAt` et n'est compté qu'une fois
  3. CSV : un motif contenant `,` `"` et un retour à la ligne est correctement échappé (RFC 4180) ; l'en-tête a exactement 7 colonnes ; BOM UTF-8 présent
  4. PDF : le fichier existe, `PDFDocument(url:)` s'ouvre, `pageCount ≥ 1`, et **pour 120 trajets `pageCount ≥ 3`** (preuve que la pagination mord) ; le texte extrait de la dernière page contient le disclaimer et l'URL de la source du barème
- [ ] **Step 2** — Lancer : échec.
- [ ] **Step 3** — Implémenter. `UIGraphicsPDFRenderer`, A4 595×842 pt, marges 40 pt, en-tête répété sur chaque page, lignes zébrées, totaux en pied de tableau, pied de page avec date de génération + pays + règle + version + disclaimer exact du spec.
- [ ] **Step 4** — Tests PASS. Générer un PDF de démo et l'ouvrir pour inspection visuelle. Commit `feat: PDF and CSV report generation`.

---

### Task 11 : Onboarding (6 écrans)

**Files:**
- Create: `Features/Onboarding/OnboardingFlow.swift`, `WelcomeStep.swift`, `CountryStep.swift`, `VehicleStep.swift`, `LocationPermissionStep.swift`, `NotificationsStep.swift`, `Tests/OnboardingTests.swift`

**Interfaces:**
- Consumes: `LocalizationService`, `CountryRuleEngine`, `SubscriptionService`, `NotificationService`
- Produces: `struct OnboardingFlow: View`, `@Observable final class OnboardingModel { var step: Int; var country: String; var vehicle: VehicleDraft; func complete() }`, `enum CountryCatalog { static let all: [CountryInfo] }` (tous les pays de `Locale.Region.isoRegions`, nom localisé, drapeau, devise via `Locale.Region.currency`)

- [ ] **Step 1** — `Tests/OnboardingTests.swift` : détection pays depuis `Locale` (FR → "FR", en-US → "US") ; `CountryCatalog.all.count > 200` et chaque entrée a un nom non vide dans les 6 langues ; un pays sans pack officiel force `RateMode.custom` ; `Skip for now` laisse `vehicle == nil` sans bloquer la suite.
- [ ] **Step 2** — Lancer : échec. Implémenter.
- [ ] **Step 3** — Écrans : Welcome (logo + « Track every business mile. » + sous-titre + Continue) ; Country (détection + sélecteur recherchable de tous les pays) ; Vehicle (nom, type, immatriculation optionnelle, + puissance fiscale **uniquement si le pack du pays l'exige**) ; GPS (explication puis `requestAlways` — l'autorisation n'est demandée **qu'à ce moment**) ; Notifications (optionnel, `Skip`) ; Paywall.
- [ ] **Step 4** — Vérifier au simulateur les 6 écrans, en anglais, capture à l'appui. Commit `feat: onboarding flow`.

---

### Task 12 : Paywall

**Files:**
- Create: `Features/Paywall/PaywallView.swift`, `PaywallModel.swift`, `Features/Paywall/PremiumGate.swift`

**Interfaces:**
- Consumes: `SubscriptionService`
- Produces: `struct PaywallView: View` (fermable), `struct PremiumGate<Content: View>: View` — enveloppe une action premium et présente le paywall si `entitlement.isActive == false`

- [ ] **Step 1** — Écran : headline « Your mileage. Automatically documented. », 6 bénéfices, deux plans côte à côte, badge « Save X% » **calculé** depuis StoreKit, CTA « Start 3-day free trial », pied « 3 days free, then [displayPrice]. Cancel anytime. », Restore / Terms / Privacy.
- [ ] **Step 2** — Aucun prix en dur : un test UI vérifie que le texte affiché contient la `displayPrice` du produit de la session de test.
- [ ] **Step 3** — `PremiumGate` appliqué à : START TRIP, ajout manuel, génération PDF, ajout d'un 2ᵉ véhicule. **Jamais** à : consultation des trajets, export CSV, suppression des données.
- [ ] **Step 4** — Commit `feat: paywall and premium gating`.

---

### Task 13 : Home + mode trajet actif + Live Activity

**Files:**
- Create: `Features/Home/HomeView.swift`, `HomeModel.swift`, `Features/ActiveTrip/ActiveTripView.swift`, `Shared/TripAttributes.swift`, `Services/LiveActivity/TripActivityController.swift`, `MileageWidgets/TripLiveActivity.swift`

**Interfaces:**
- Consumes: `TripRecording`, `CountryRuleEngine`, `Fmt`
- Produces: `struct TripAttributes: ActivityAttributes { struct ContentState: Codable, Hashable { let distanceMeters: Double; let startedAt: Date; let unitRaw: String } ; let vehicleName: String }`, `final class TripActivityController { func start(vehicleName:) ; func update(distanceMeters:) ; func end() }`

- [ ] **Step 1** — Home : mois en cours, **grand chiffre** de distance + montant estimé, nombre de trajets business, gros bouton circulaire START TRIP, véhicule actif changeable en un tap, carte « Last trip ».
- [ ] **Step 2** — ActiveTrip : timer `00:27:42`, distance, carte `Map` suivant le tracé, véhicule discret, gros bouton STOP. Mise à jour ≤ 1 Hz pour ne pas saturer le rendu.
- [ ] **Step 3** — Live Activity + Dynamic Island (compact : distance ; étendu : durée + distance + véhicule). Démarrée au START, mise à jour toutes les 30 s ou tous les 500 m, terminée au STOP.
- [ ] **Step 4** — Vérifier au simulateur : START → l'app en arrière-plan continue d'accumuler (injection de positions par `simctl` ou GPX), la Live Activity s'affiche. Capture à l'appui.
- [ ] **Step 5** — Commit `feat: home screen, active trip mode and Live Activity`.

---

### Task 14 : Fin de trajet en moins de 5 secondes

**Files:**
- Create: `Features/ActiveTrip/TripSummarySheet.swift`, `Services/Location/FrequentLocationMatcher.swift`, `Tests/FrequentLocationTests.swift`

**Interfaces:**
- Produces: `enum FrequentLocationMatcher { static func match(latitude: Double, longitude: Double, in known: [FrequentLocation], radiusMeters: Double = 150) -> FrequentLocation? ; static func learn(trip: Trip, into: [FrequentLocation]) -> [FrequentLocation] }`

- [ ] **Step 1** — `Tests/FrequentLocationTests.swift` : un point à 80 m d'un lieu connu correspond, à 200 m non ; **pile à 150 m** correspond ; un lieu vu 3 fois avec le même client propose ce client ; deux lieux proches ne se confondent pas.
- [ ] **Step 2** — Lancer : échec. Implémenter (distance de Haversine, aucune IA, aucun réseau).
- [ ] **Step 3** — `TripSummarySheet` : distance et montant affichés **immédiatement**, puis deux gros boutons BUSINESS / PERSONAL (défaut configurable), puis motif (5 suggestions + champ libre) et client/projet avec auto-complétion, bouton Save. Si le point d'arrivée correspond à un lieu connu : bandeau « Client ABC? » validable en un tap.
- [ ] **Step 4** — Test UI : du STOP au trajet enregistré en ≤ 3 taps. Commit `feat: fast trip qualification with smart destinations`.

---

### Task 15 : Trips, détail, édition, ajout manuel

**Files:**
- Create: `Features/Trips/TripsView.swift`, `TripsModel.swift`, `Features/TripDetail/TripDetailView.swift`, `Features/ManualTrip/ManualTripView.swift`, `Tests/TripGroupingTests.swift`

**Interfaces:**
- Produces: `enum TripSection: Hashable { case today, yesterday, thisWeek, earlier }`, `enum TripGrouping { static func group(_ trips: [Trip], now: Date, calendar: Calendar) -> [(TripSection, [Trip])] }`

- [ ] **Step 1** — `Tests/TripGroupingTests.swift` : un trajet à 00:05 aujourd'hui est dans `.today` ; hier 23:55 dans `.yesterday` ; il y a 3 jours dans `.thisWeek` ; il y a 20 jours dans `.earlier` ; les sections vides ne sont pas produites ; **changement de fuseau horaire** entre l'enregistrement et l'affichage : le regroupement suit le calendrier courant sans décaler d'un jour.
- [ ] **Step 2** — Lancer : échec. Implémenter.
- [ ] **Step 3** — `TripsView` : sections, cartes (date, départ → destination, distance, pastille Business/Personal, montant), recherche, filtre Business/Personal.
- [ ] **Step 4** — `TripDetailView` : carte avec tracé décodé, tous les champs du spec §10, actions Edit / Duplicate / Delete. Correction manuelle de la distance → `isManuallyEdited = true` et badge « Edited » visible ; le montant est recalculé avec **le barème historisé du trajet**, pas le courant.
- [ ] **Step 5** — `ManualTripView` : tous les champs, calcul automatique, `PremiumGate`.
- [ ] **Step 6** — Commit `feat: trips list, detail and manual entry`.

---

### Task 16 : Reports, véhicules, clients/projets

**Files:**
- Create: `Features/Reports/ReportsView.swift`, `Features/Vehicles/VehiclesView.swift`, `Features/Vehicles/VehicleEditor.swift`, `Features/Settings/ClientsProjectsView.swift`

- [ ] **Step 1** — `ReportsView` : période en cours (« September 2026 », N business trips, distance, montant), sélecteur Month/Quarter/Year/Custom, bouton GENERATE REPORT, choix PDF ou CSV, `ShareLink`.
- [ ] **Step 2** — `VehiclesView` : liste, défaut, ajout/édition. **N'afficher que les champs utiles au pays** (la puissance fiscale n'apparaît que si le pack l'exige) ; un 2ᵉ véhicule passe par `PremiumGate`.
- [ ] **Step 3** — `ClientsProjectsView` : création/suppression simples, comptage des trajets liés. Rien de plus — ce n'est pas un CRM.
- [ ] **Step 4** — Commit `feat: reports, vehicles and clients screens`.

---

### Task 17 : Settings complet

**Files:**
- Create: `Features/Settings/SettingsView.swift`, `Features/Settings/DataSettingsView.swift`, `Features/Settings/MileageRateSettingsView.swift`

- [ ] **Step 1** — Sections du spec §28 : Account (nom, entreprise, email) ; Driving (véhicule par défaut, type par défaut, unités) ; Region (pays, langue, devise) ; Mileage calculation (Official / Employer / Custom + affichage de la règle active, sa version et sa source cliquable) ; Data (iCloud Sync, Export all data, Delete all data) ; Subscription (plan courant, gérer, restaurer) ; About (Privacy, Terms, Support, version).
- [ ] **Step 2** — « Delete all data » : confirmation explicite, suppression de tous les modèles **et** du store CloudKit, retour à l'onboarding.
- [ ] **Step 3** — Changement de pays : n'altère **aucun** trajet existant ; un test le vérifie (montants et versions de barème inchangés après bascule FR → US).
- [ ] **Step 4** — Commit `feat: settings`.

---

### Task 18 : Widget, notifications, accessibilité, finitions

**Files:**
- Create: `MileageWidgets/StartTripWidget.swift`, `Shared/WidgetSnapshot.swift`, `Services/Notifications/NotificationService.swift`, `Resources/PrivacyInfo.xcprivacy`

- [ ] **Step 1** — Widget petit format : bouton Start Trip (deep link `mileagepocket://start`) + total du mois lu depuis l'App Group. Snapshot réécrit à chaque fin de trajet.
- [ ] **Step 2** — Notifications : rappel « trajet toujours en cours » (au bout de 3 h), confirmation de fin, rappel mensuel de rapport (le 1er du mois). Toutes optionnelles.
- [ ] **Step 3** — Accessibilité : Dynamic Type jusqu'à AX5 sans troncature sur Home/ActiveTrip/Trips, labels VoiceOver sur START/STOP/BUSINESS/PERSONAL, `Reduce Motion` respecté, cibles ≥ 44 pt. Vérifier au simulateur en AX5.
- [ ] **Step 4** — `PrivacyInfo.xcprivacy` : `NSPrivacyCollectedDataTypes` vide (rien n'est collecté), `NSPrivacyAccessedAPITypes` pour `UserDefaults` (`CA92.1`) et le système de fichiers si utilisé.
- [ ] **Step 5** — Données de démo : `#Preview` avec Paris → Versailles, Paris → Orly, Paris → Boulogne.
- [ ] **Step 6** — Commit `feat: widget, notifications, accessibility and privacy manifest`.

---

### Task 19 : Vérification de bout en bout

- [ ] **Step 1** — Suite complète : `xcodebuild test` sur iOS 18.6 **et** iOS 26.5 (hors tests StoreKit sur 26.x). Lire les **codes de sortie**, pas la sortie texte.
- [ ] **Step 2** — Parcours réel au simulateur avec injection GPX : START → conduite simulée → app en arrière-plan → STOP → BUSINESS → Save → le trajet apparaît dans Trips avec la bonne distance.
- [ ] **Step 3** — Générer un PDF sur un mois de données de démo et l'inspecter visuellement.
- [ ] **Step 4** — Captures d'écran anglaises des 6 écrans clés.
- [ ] **Step 5** — Commit + `git push`.

---

### Task 20 : App Store Connect

- [ ] **Step 1** — Créer par l'API le groupe d'abonnement, les deux abonnements, leurs localisations, **`subscriptionAvailabilities` avant les prix**, les prix sur les 175 territoires, puis les offres d'introduction 3 jours (175 POST par plan).
- [ ] **Step 2** — Vérifier que chaque abonnement quitte `MISSING_METADATA` — sinon il manque la capture de revue du paywall.
- [ ] **Step 3** — Remplir la fiche en 6 langues, catégorie Business/Finance, URL de confidentialité `crazybeelabs.com/legal/apps`.
- [ ] **Step 4** — Usage description GPS exacte : « Mileage Pocket uses your location while driving to calculate the distance of your trips, including when the app is in the background. »
- [ ] **Step 5** — Vérifier l'état final par l'API avec `include=` sur chaque relation lue.
