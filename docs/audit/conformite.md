# Mileage Pocket — Audit de conformité au cahier des charges V1

Date : 2026-09-13 · Lecture seule · Sources : `docs/superpowers/specs/2026-09-12-mileage-pocket-design.md`, `docs/superpowers/plans/2026-09-12-mileage-pocket-v1.md`

Méthode : lecture du code uniquement. Chaque constat porte un `chemin:ligne` et un statut
**confirmé** (lu dans le fichier) ou **soupçonné** (non vérifiable sans exécuter).

> Réserve méthodologique : `build/Debug-iphonesimulator/MileagePocket.app/Info.plist` date du
> 12/09 22:35, soit **avant** `App/Info.plist` et `Config/Base.xcconfig` (23:07). Le binaire
> compilé est périmé ; aucun constat ci-dessous ne s'appuie dessus. Tout est tiré des sources.

---

## 1. Tableau de bord des 16 priorités V1

| Priorité V1 | État | Preuve |
|---|---|---|
| Onboarding | **livré** | `Features/Onboarding/OnboardingFlow.swift:28-35` — 6 étapes, toutes atteignables |
| GPS (filtrage, précision) | **livré** | `Services/Location/LocationFilter.swift` — règles 1→6 du spec §4, écarts documentés |
| Start / Stop | **livré** | `Features/Home/HomeView.swift:84`, `Features/ActiveTrip/ActiveTripView.swift:104-118` |
| **Suivi en arrière-plan** | **ABSENT** | §2.1 — l'autorisation `Always` n'est jamais demandée |
| Historique | **livré** | `Features/Trips/TripsView.swift` — sections, recherche, filtre |
| Business / Personal | **partiel** | classement possible à la création seulement, jamais après (§2.7) |
| Véhicules | **livré** | `Features/Vehicles/VehiclesView.swift` + gate 2ᵉ véhicule ligne 42 |
| Calcul local | **livré** | `Services/MileageRules/DeclarativeMileageRule.swift` |
| Moteur international | **partiel** | 12 packs livrés, mais 2 défauts de calcul silencieux (§2.3, §2.4) |
| Rapports PDF | **partiel** | rendu correct mais **100 % en anglais en dur** (§2.8) |
| CSV | **partiel** | livré mais payant, contre le spec §2.6 (§3.1) |
| Abonnement | **livré** | `Services/Subscription/SubscriptionService.swift` — StoreKit 2, prix jamais en dur |
| Essai 3 jours | **partiel** | offre StoreKit OK, mais doublé d'un essai local interdit par le spec (§3.2) |
| Langues (6) | **partiel** | catalogue complet 202×6, mais 33 appels ignorent la langue choisie (§2.9) |
| **iCloud** | **ABSENT** | `Config/Base.xcconfig:26` `CLOUDKIT_AVAILABLE = NO` (§2.5) |
| Live Activity | **livré** | `Services/LiveActivity/TripActivityController.swift`, `MileageWidgets/TripLiveActivity.swift` |
| *(Widget, hors liste mais au spec §1)* | **partiel** | bouton OK, chiffres jamais affichés (§2.6) |

---

## 2. Défauts critiques et majeurs

### 2.1 CRITIQUE — Le suivi en arrière-plan n'est atteignable par aucun chemin d'interface — **confirmé**

`CoreLocationProvider.requestAlways()` (`Services/Location/CoreLocationProvider.swift:52-63`)
n'appelle `requestAlwaysAuthorization()` que dans la branche `case .authorizedWhenInUse`.
Il faut donc **deux** appels successifs : un pour obtenir *When In Use*, un second pour
demander *Always*.

Or `requestPermission()` n'a que deux appelants :

- `App/AppDependencies.swift:329` (`requestLocationPermission()`), appelé une seule fois
  depuis `Features/Onboarding/OnboardingFlow.swift:192` ;
- `App/AppDependencies.swift:170-171`, gardé par `if recorder.authorizationStatus == .notDetermined`.

Après l'onboarding le statut vaut `.authorizedWhenInUse` : le premier appelant a disparu de
l'écran, le second est désactivé par sa garde. **La seconde demande n'a lieu jamais.**

Conséquence directe, `Services/Location/CoreLocationProvider.swift:71-72` :

```swift
if manager.authorizationStatus == .authorizedAlways {
    manager.allowsBackgroundLocationUpdates = true
}
```

`allowsBackgroundLocationUpdates` reste `false` sur toute la durée de vie de l'app. Un trajet
cesse d'accumuler dès que l'écran se verrouille. C'est la promesse centrale du produit
(« Drive. We keep the record. ») et la description d'usage GPS livrée à Apple
(`App/Info.plist:35-38`, « including when the app is in the background ») annonce le contraire
de ce que le code fait.

### 2.2 CRITIQUE — Permission refusée : l'app fait semblant d'enregistrer — **confirmé**

`Features/Home/HomeView.swift:156-162` ne consulte que `canAccess(.startTrip)` ; l'état
d'autorisation n'est jamais lu. `TripRecorder.start` (`Services/Location/TripRecorder.swift:106-131`)
ne lève que `alreadyRecording` et place `state = .recording` sans condition. `RootView`
bascule alors sur `ActiveTripView` (`App/RootView.swift:15-16`).

Résultat avec le GPS refusé ou coupé : plein écran « RECORDING », chronomètre qui tourne,
distance figée à 0,0 km, aucun message. Au STOP, un trajet de 0 m est enregistré.

Le commentaire de `App/AppDependencies.swift:184-186` affirme « the view already shows the
permission state ». **Aucune vue ne l'affiche** : `grep authorizationStatus` sur `Features/`
ne renvoie rien. Cas limite explicitement exigé par le spec §10.

### 2.3 CRITIQUE — France : tout montant est majoré de 20 % quand le véhicule est inconnu — **confirmé**

`Services/MileageRules/DeclarativeMileageRule.swift:65-67` :

```swift
private func scheme(for vehicle: Vehicle?) -> RateScheme? {
    pack.schemes.first { $0.matches(vehicle: vehicle) } ?? pack.schemes.first
}
```

et `Services/MileageRules/RulePackModels.swift:112-113` :

```swift
func matches(vehicle: Vehicle?) -> Bool {
    guard let vehicle else { return true }
```

Un véhicule `nil` fait donc matcher **le premier schéma du pack**. Or dans
`Resources/MileageRules/FR/2026.1.json` le premier schéma est `automobile-electrique`,
`vehicleTypes: ["electricCar"]`, `rateMultiplier: 1.20`.

Deux chemins y mènent, tous deux ordinaires :

1. **Aucun véhicule** — l'onboarding propose explicitement « Skip »
   (`Features/Onboarding/OnboardingFlow.swift:171`) ; `AppDependencies.vehicle(for:)` renvoie
   alors `nil` (`App/AppDependencies+Data.swift:11-15`).
2. **Un vélo** — `VehicleType.bicycle` est offert dans les deux sélecteurs
   (`OnboardingFlow.swift:127`, `VehiclesView.swift:102`) et aucun schéma FR ne le couvre ;
   le `?? pack.schemes.first` renvoie encore l'électrique.

Le montant est alors présenté avec `isOfficial: true`
(`DeclarativeMileageRule.swift:58`) et imprimé dans le PDF comme barème officiel.
Le plan exigeait nommément l'inverse — Task 7, Step 1, cas 8 : « véhicule `nil` → le schéma
par défaut (`car`) s'applique ». Les tests couvrent ce cas contre un pack **synthétique**
(`Tests/MileageCalculationTests.swift:234`), jamais contre le pack FR livré : la garantie
n'est donc pas tenue sur les données réelles.

Vérifié sur les 12 packs : **seule la France** est touchée (les 11 autres ont un premier
schéma `car/van/electricCar` sans multiplicateur).

### 2.4 CRITIQUE — Pays sans barème officiel : tous les montants valent 0,00 et le taux est insaisissable — **confirmé**

Le spec §2.3 dit : « le pays bascule **automatiquement** en Custom rate ». Ce basculement
n'existe pas dans l'état de l'app :

- `Core/Persistence/SettingsStore.swift:41-46` (`applyCountry`) écrit `countryCode`,
  `currencyCode`, `distanceUnit` — **pas** `rateMode`, qui reste `.official`.
- `App/AppDependencies.swift:313-324` (`currentRule`) passe alors
  `customRate: settings.customRate`, qui vaut `nil` par défaut
  (`Models/UserSettings.swift:23`).
- `Services/MileageRules/CountryRuleEngine.swift:38-44` retombe sur
  `CustomRateRule(ratePerUnit: customRate ?? 0)` → **taux 0**.
- `Features/Settings/SettingsView.swift:138` : le champ de saisie du taux n'est affiché que
  `if settings.rateMode != .official`. Il est donc **invisible** dans cette situation.

Un utilisateur en Italie, en Pologne, au Japon — soit ~190 pays sur les ~250 du sélecteur —
voit « Official » coché, le champ de taux absent, et chaque trajet à 0,00. Pendant ce temps
les textes affichés lui promettent le contraire :

- `onboarding.country.custom` : « You will set your own rate, and everything else works the same. »
- `settings.no.official.rule` : « …so your own rate is used. »

La fonction prévue pour cela, `CountryRuleEngine.effectiveMode(requested:countryCode:on:)`
(`Services/MileageRules/CountryRuleEngine.swift:49-54`), avec le commentaire « which is what
Settings should display », **n'est appelée nulle part** (0 occurrence hors déclaration).

### 2.5 MAJEUR — iCloud : priorité V1 absente, et l'interrupteur est doublement mort — **confirmé**

Deux constats distincts.

**a) La synchronisation n'existe pas dans ce build.**
`Config/Base.xcconfig:26` : `CLOUDKIT_AVAILABLE = NO`. `App/MileagePocket.entitlements` ne
contient aucune clé iCloud (le fichier n'a qu'un commentaire expliquant pourquoi).
`Core/Persistence/CloudKitAvailability.swift:17-22` renvoie donc `false`, et
`PersistenceController.makeContainerWithFallback` (`Core/Persistence/PersistenceController.swift:38`)
ouvre toujours un magasin local. La priorité V1 « iCloud » est **absente**.

À décharge : l'app est honnête à l'écran (interrupteur `.disabled` et note explicative,
`Features/Settings/SettingsView.swift:186,194-196`) et le paywall retire la ligne iCloud de
sa liste d'arguments (`Features/Paywall/PaywallView.swift:110-113`). Rien n'est promis à
tort — la fonction manque, elle n'est pas mentie.

**b) L'interrupteur ne serait pas câblé même si (a) était corrigé.**
`Features/Settings/SettingsView.swift:182` écrit `settings.iCloudSyncEnabled` (SwiftData),
tandis que `App/MileagePocketApp.swift:11` lit au lancement :

```swift
let cloudEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
```

`grep -r iCloudSyncEnabled` ne trouve **aucune écriture** de cette clé `UserDefaults`. Le
réglage est un réglage sans effet, indépendamment de l'entitlement.

### 2.6 MAJEUR — Widget : les chiffres du mois ne s'affichent jamais — **confirmé**

`Shared/WidgetSnapshot.swift:30-34` passe par
`containerURL(forSecurityApplicationGroupIdentifier: "group.company.lno.mileage")`.
L'App Group n'est déclaré dans aucun des deux fichiers d'entitlements
(`App/MileagePocket.entitlements`, `MileageWidgets/MileageWidgets.entitlements`, tous deux vides
par décision assumée). `containerURL` renvoie `nil`, donc `write` sort au premier `guard`
(ligne 37) et `read` renvoie `nil` (ligne 45).

Le widget affiche donc en permanence la branche `else` de
`MileageWidgets/StartTripWidget.swift:80-84` : un titre et « home.empty.title ». Le bouton
(deep link `mileagepocket://start`, ligne 87 → `App/MileagePocketApp.swift:22-28`) fonctionne ;
le reste du widget, non. Livré à moitié.

### 2.7 MAJEUR — Un trajet enregistré n'est plus modifiable que sur sa distance — **confirmé**

`Features/TripDetail/TripDetailView.swift:131-151` offre exactement quatre actions :
corriger la distance, recalculer, dupliquer, supprimer.

`grep` sur `Features/` et `App/` montre que `trip.tripType`, `trip.purpose`, `trip.clientID`
et `trip.vehicleID` ne sont écrits que dans trois contextes : la feuille de résumé
(`Features/ActiveTrip/TripSummarySheet.swift:199-203`), la saisie manuelle
(`App/AppDependencies+Data.swift:169-173`) et la duplication (lignes 199-203).

Conséquence : **reclasser un trajet Personnel → Professionnel est impossible**. C'est l'usage
le plus courant d'un carnet kilométrique (on classe vite au volant, on corrige le soir).
Corriger un motif, changer de véhicule ou rattacher un client après coup l'est aussi.
Le plan demandait « actions Edit / Duplicate / Delete » (Task 15, Step 4) ; « Edit » se réduit
ici à la distance.

Contournement existant mais coûteux : dupliquer, puis reclasser… non, la duplication recopie
`tripType` sans l'exposer. Il n'y a pas de contournement.

### 2.8 MAJEUR — Le rapport PDF est intégralement en anglais en dur — **confirmé**

`Services/Reports/PDFReportRenderer.swift` : `"MILEAGE REPORT"` (129), `"Rule version"` (142),
`"Business trips"` / `"Total distance"` / `"Total deduction"` (172-174), l'en-tête de tableau
(188), `"TOTAL — N business trips"` (240), `"Generated on … by Mileage Pocket."` (259),
l'avertissement (269-271), le pied de page (287, 293). Aucun `String(localized:)` dans le
fichier. `profile.locale` n'est utilisé que pour formater nombres et dates.

Un utilisateur français qui choisit le français obtient un PDF anglais — or ce PDF est
précisément le livrable du produit, celui qu'on envoie à son comptable ou à son employeur.
Spec §7 : « Aucun texte UI en dur. »

Même remarque, moindre, pour le CSV (`Services/Reports/CSVExporter.swift:12,34`), où
l'anglais est défendable puisque le fichier est machine-readable.

### 2.9 MAJEUR — Changer de langue ne traduit qu'une partie de l'écran — **confirmé**

Le mécanisme retenu est `\.locale` poussé dans l'environnement SwiftUI
(`App/RootView.swift:23`), qui n'agit que sur `Text(LocalizedStringKey)`.

Mais 33 sites d'appel court-circuitent l'environnement et résolvent contre la langue
**système** :

- `Core/Localization/LocalizationService.swift:54-66` — `L.string` / `L.format` / `L.plural`
  sont bâtis sur `NSLocalizedString(key, comment:)`, qui ignore `\.locale`. 10 sites, dont
  `Features/Home/HomeView.swift:66,72` (le montant estimé et le compteur de trajets, en
  plein sur l'écran d'accueil), `Features/ActiveTrip/TripSummarySheet.swift:117,136,138`
  (les motifs pré-remplis), `Features/Paywall/PaywallView.swift:157` (le badge « Save X% »),
  `Features/Vehicles/VehiclesView.swift:69,103` et `Features/Onboarding/OnboardingFlow.swift:128`
  (les types de véhicule).
- 23 sites `String(localized:)`, même problème, notamment
  `App/AppDependencies+Data.swift:251,256,309` (le profil du rapport et la description du plan).

Un utilisateur d'un iPhone en anglais qui choisit le français obtient donc un écran d'accueil
mi-français mi-anglais. Le catalogue lui-même est irréprochable : 202 clés × 6 langues,
aucun trou (vérifié en parcourant `Resources/Localizable.xcstrings`).

### 2.10 MAJEUR — L'écran Clients / Projets n'existe pas — **confirmé**

Plan, Task 16, Step 3 : « `Features/Settings/ClientsProjectsView.swift` : création/suppression
simples, comptage des trajets liés ». Le fichier n'existe pas et aucune vue n'en tient lieu.

Le modèle `Models/Project.swift` est déclaré et enregistré au schéma
(`Core/Persistence/PersistenceController.swift:16`) mais **`Trip.projectID` n'est jamais écrit
nulle part** hors duplication (`App/AppDependencies+Data.swift:202`). La notion de projet est
entièrement inatteignable : code présent, fonction absente.

Les clients s'en tirent mieux (création implicite par le nom tapé dans la feuille de résumé,
`App/AppDependencies+Data.swift:44-55`) mais sont eux aussi non listables, non renommables et
non supprimables.

---

## 3. Écarts au spec assumés ou non documentés

### 3.1 L'export CSV est payant, le spec le dit gratuit — **confirmé**

Spec §2.6, tableau d'accès : « Export CSV de ses données · ✅ libre ».
`Core/Access/AccessPolicy.swift:32` : `if feature == .exportReport { return false }`, et
`Features/Reports/ReportsView.swift:120,130-134` route le bouton CSV par ce même
`exportReport`. Le commentaire de `Services/Subscription/Entitlement.swift:44` assume :
« Report exports — PDF and CSV alike — are premium ».

Le ledger SDD enregistre la décision (« Décision produit (Jeremy, mi-parcours) »), et un
chemin gratuit subsiste — `Réglages > Export all data`, non gardé
(`App/AppDependencies+Data.swift:232`, `Features/Settings/SettingsView.swift:187-189`). Le
spec n'a simplement pas été mis à jour : il dit encore l'inverse du code.

### 3.2 Un essai local de 3 jours a été ajouté, que le spec interdit — **confirmé**

Spec §2.6 : « Aucun trial local contournable — StoreKit est la seule source de vérité, via
`Transaction.currentEntitlements` ». `Services/Subscription/Entitlement.swift:5-7` répète le
principe mot pour mot.

Pourtant `Core/Access/AccessPolicy.swift:4-20` définit `FreeAccessPeriod` (3 jours) et
`Core/Access/InstallDateStore.swift` en stocke l'origine dans le trousseau ;
`App/AppDependencies.swift:38-45` accorde l'accès dès que `freePeriod.isActive()`.

C'est un ajout délibéré (commit `250607e`), plutôt bien fait — trousseau plutôt que
`UserDefaults` pour survivre à une réinstallation, export exclu de la gratuité, période non
réarmée par « Delete all data » (`App/AppDependencies+Data.swift:276-277`). Mais il contredit
frontalement une décision structurante du spec, et le spec n'a pas été amendé.

### 3.3 Aucun rapport sur une période passée — **confirmé**

`Features/Reports/ReportsView.swift:32-46` construit toujours la période **courante** :
`calendar.component(.year, from: now)`, `.month, from: now`, trimestre calculé depuis `now`.
Il n'y a ni sélecteur d'année ni sélecteur de mois.

`ReportPeriod` sait pourtant faire (`.month(year:month:)`,
`Services/Reports/ReportPeriod.swift`) : la capacité est là, l'interface ne l'expose pas.
Or le geste le plus fréquent — éditer le rapport du mois écoulé, les premiers jours du mois
suivant — n'est possible qu'en passant par « Custom » et en saisissant deux dates à la main.

### 3.4 Notifications : deux tiers des exigences manquent — **confirmé**

Plan, Task 18, Step 2 : trois notifications, « toutes optionnelles ».

- Rappel « trajet toujours en cours » : **livré**
  (`Services/Notifications/NotificationService.swift:28-40`, appelé depuis
  `App/AppDependencies.swift:181`).
- Rappel mensuel : **livré mais non débrayable** (`NotificationService.swift:55-70`, planifié
  une seule fois depuis `App/AppDependencies.swift:335`).
- **Confirmation de fin de trajet : absente.** `notifyTripSaved(distanceText:)` existe
  (`NotificationService.swift:46-52`) et n'a **aucun appelant**. Code mort.
- **« Optionnelles » n'est pas tenu** : il n'y a aucune section Notifications dans
  `Features/Settings/SettingsView.swift`. `UserSettings.notificationsEnabled`
  (`Models/UserSettings.swift:29`) est écrit une fois à l'onboarding
  (`App/AppDependencies.swift:334`) et **relu nulle part** — réglage sans effet. Qui refuse
  à l'onboarding ne peut plus jamais accepter depuis l'app ; qui accepte ne peut plus couper
  le rappel mensuel.

### 3.5 « Delete all data » ne ramène pas à l'onboarding — **confirmé**

Plan, Task 17, Step 2 : « suppression de tous les modèles **et** du store CloudKit, retour à
l'onboarding ».

`App/AppDependencies+Data.swift:267-280` supprime les sept entités, mais ne touche pas
`settings.hasCompletedOnboarding`. `App/RootView.swift:13` continue donc d'afficher les
onglets : l'utilisateur se retrouve sur un accueil vide, sans pays, sans véhicule, sans avoir
été réorienté. (Le volet CloudKit est sans objet, voir §2.5.)

### 3.6 Pas de proposition « Resume active trip » — **confirmé**

Spec §4 : « Au lancement, si un état actif existe, l'app **propose** *Resume active trip* et le
tracking reprend. »

`App/AppDependencies.swift:118` appelle `try? recorder.resumeIfNeeded()` sans condition, et
`Services/Location/TripRecorder.swift:139-165` reprend tout `ActiveTripState` trouvé, **sans
contrôle d'ancienneté**. Il n'y a aucune alerte, aucune confirmation.

Un plantage survenu il y a trois semaines renvoie donc l'utilisateur directement dans
`ActiveTripView`, chronomètre à 500 heures, sans autre issue que STOP — lequel crée un trajet
aberrant. La reprise après crash elle-même fonctionne (c'est le point fort de §37) ; c'est la
main tendue à l'utilisateur qui manque.

### 3.7 Une langue choisie ne peut plus être rendue au système — **confirmé**

`Core/Localization/LocalizationService.swift:31-39` expose `useSystemLanguage()`.
**Zéro appelant.** Le sélecteur de `Features/Settings/SettingsView.swift:114-121` ne liste que
`AppLanguage.allCases` — pas d'entrée « Système ». Une fois `hasExplicitLanguageOverride`
passé à `true` (ligne 26 du service), il ne redescend jamais.

### 3.8 Le formulaire véhicule n'a pas de bouton Annuler — **confirmé**

`App/AppDependencies+Data.swift:59-64` (`makeVehicle`) insère le `Vehicle` dans le contexte
**avant** que l'éditeur ne s'ouvre (`Features/Vehicles/VehiclesView.swift:43`). L'éditeur
n'a qu'une action, `Done` (`VehiclesView.swift:132-137`). Un balayage vers le bas pour fermer
la feuille laisse donc un véhicule au nom vide dans le magasin — que `mainContext` de SwiftData
persiste de lui-même.

### 3.9 Test d'onboarding manquant — **confirmé**

Plan, Task 11, Step 1, énumère six assertions (détection du pays, `CountryCatalog.all.count > 200`,
bascule en `RateMode.custom`, « Skip » non bloquant…). `Tests/` contient 15 fichiers ;
`OnboardingTests.swift` n'en fait pas partie. La bascule `RateMode.custom`, non testée, est
précisément celle qui manque au code (§2.4).

---

## 4. Constats mineurs

| # | Constat | Preuve | Statut |
|---|---|---|---|
| 4.1 | `Vehicle.brand`, `.model`, `.powerKW`, `.fuelType` : aucun champ d'interface, jamais écrits | `Models/Vehicle.swift:10-19` ; 0 occurrence dans `Features/` | confirmé |
| 4.2 | `UserSettings.customRateCurrencyCode` : jamais lu ni écrit | `Models/UserSettings.swift:24` ; 0 occurrence ailleurs | confirmé |
| 4.3 | La devise est en lecture seule dans Réglages alors que le plan liste « Region (pays, langue, **devise**) » | `Features/Settings/SettingsView.swift:123` (`LabeledContent`) | confirmé |
| 4.4 | Widget et Live Activity codent « km »/« mi » en dur au lieu de `Fmt.unitAbbreviation` | `MileageWidgets/StartTripWidget.swift:69`, `MileageWidgets/TripLiveActivity.swift:70` | confirmé |
| 4.5 | `CountryRuleEngine.availableCountries()` jamais appelé : le sélecteur de pays n'indique pas lesquels ont un barème officiel (seul l'onboarding le dit, une fois) | `Services/MileageRules/CountryRuleEngine.swift:19` ; `Features/Settings/SettingsView.swift:222-255` | confirmé |
| 4.6 | `CustomRateRule.summary` renvoie de l'anglais en dur — sans conséquence, les appelants le court-circuitent | `Services/MileageRules/MileageRule.swift:57-59` ; `App/AppDependencies+Data.swift:112,256` | confirmé |
| 4.7 | 7 seuls `accessibilityLabel`/`Identifier` dans tout `Features/` + `App/` ; l'exigence Dynamic Type AX5 sans troncature n'est pas vérifiable par lecture | plan Task 18 Step 3 | soupçonné |
| 4.8 | Depuis Home, le sélecteur de véhicule affiche un état vide sans moyen d'en ajouter un | `Features/Vehicles/VehiclesView.swift:176-180` | confirmé |

---

## 5. Ce que le spec exige et qui est bien là

Pour ne pas peindre un tableau faux, la liste de ce qui est tenu, vérifié ligne à ligne :

- **Les 12 packs de barèmes** sont livrés, sourcés et documentés
  (`Resources/MileageRules/{AU,BE,CA,CH,DE,ES,FR,GB,IE,NL,PT,US}/2026.1.json`,
  `docs/mileage-rules-sources.md`), l'Italie écartée faute de source vérifiable — exactement
  la règle §2.3 (« un pays dont la source ne peut pas être vérifiée est retiré plutôt que
  rempli au jugé »). Ils sont bien embarqués (dossier bleu, `gen_pbxproj.py:306-308`).
- **Historique figé** : `Trip` porte `mileageRuleVersion`, `mileageRate`, `calculatedAmount`
  (`Models/Trip.swift:39-41`) ; `applyCountry` ne touche aucun trajet
  (`Core/Persistence/SettingsStore.swift:39-46`) ; le recalcul est explicite et confirmé
  (`Features/TripDetail/TripDetailView.swift:48-53`), et une correction de distance repasse par
  le barème **gelé sur le trajet** et non par le courant
  (`App/AppDependencies.swift:291-302`).
- **Le tracé n'est pas stocké point par point** : `stop()` compacte puis supprime les
  `LocationPoint` (`Services/Location/TripRecorder.swift:187-199`), conformément à §2.1.
- **Deux géocodages par trajet, jamais un par point** (`TripRecorder.swift:205-210`), §11.
- **Prix jamais en dur** : `PaywallPlan` lit `product.displayPrice`
  (`Features/Paywall/PaywallPlan.swift:19`) et l'économie annuelle est calculée depuis les deux
  prix StoreKit (`Services/Subscription/SubscriptionService.swift:42-48`).
- **Paywall fermable** dans ses deux présentations, y compris la dernière étape d'onboarding
  où `dismiss()` ne fait rien — d'où le `onClose` explicite
  (`Features/Paywall/PaywallView.swift:16,250-257` ; `OnboardingFlow.swift:224`).
- **Une transaction non vérifiée n'accorde jamais rien**
  (`SubscriptionService.swift:112-115,206`).
- **Client de mise à jour des barèmes complet et non bloquant**, endpoint non déployé, échec
  silencieux (`App/AppDependencies.swift:123-125`, `Services/MileageRules/RulePackUpdater.swift`).
- **Avertissement légal du PDF présent au mot près** (`PDFReportRenderer.swift:271`), et le
  rapport signale explicitement un taux non officiel (ligne 269).
- **CSV RFC 4180** : tous les champs guillemetés, guillemets doublés, CRLF, BOM UTF-8
  (`Services/Reports/CSVExporter.swift:41,47-49,64-66`).
- **Manifeste de confidentialité** présent et cohérent avec « rien n'est collecté »
  (`Resources/PrivacyInfo.xcprivacy`).
- **Filtre GPS** : les six règles du spec §4 sont implémentées, avec deux écarts assumés et
  argumentés dans le code — seuil de bruit à `accuracy × 2` plutôt que `× 0,5`, et ajout d'un
  lisseur α-β (`Services/Location/LocationFilter.swift:47-79`). L'écart est motivé par une
  mesure (1 749 m sur une fixture de 1 000 m sans lisseur), pas par une préférence.
- **Abonnements créés dans App Store Connect** : groupe 22380282, deux produits, 175
  territoires tarifés, offres 3 jours posées ; seule manque la capture de revue du paywall
  (`.superpowers/sdd/2026-09-12-mileage-pocket-v1/task-20-report.md`).

---

## 6. Verdict

**Tenues** : onboarding, filtrage GPS, start/stop, historique, véhicules, moteur de calcul
déclaratif, packs officiels sourcés, historique figé, abonnement StoreKit 2, Live Activity,
catalogue de traduction, manifeste de confidentialité.

**Non tenues** : suivi en arrière-plan (inatteignable), iCloud (désactivé à la compilation).

**Livrées à moitié** : Business/Personal (jamais modifiable après coup), moteur international
(faux à 0 ou à +20 % dans deux cas courants), rapports PDF (anglais seul), CSV (payant contre
le spec), essai (doublé d'un essai local interdit), langues (un tiers de l'interface ignore le
choix), widget (chiffres jamais affichés), clients/projets (écran absent, projets
inatteignables).

Le socle technique — filtrage, compaction, moteur de barèmes, StoreKit, persistance — est
solide et sérieusement testé. Ce qui manque se concentre sur **le dernier centimètre entre le
code et l'utilisateur** : des permissions jamais redemandées, des réglages jamais relus, des
écrans jamais écrits, des fonctions correctes que rien n'appelle.
