# Mileage Pocket — Design (V1)

**Date** : 2026-09-12
**Produit** : Crazy Bee Labs
**Promesse** : *Drive. We keep the record.* — Start. Drive. Stop. Export.

## 0. Faits vérifiés (App Store Connect, 2026-09-12)

| Élément | Valeur |
|---|---|
| App ID | `6811426601` |
| Nom | Mileage Pocket |
| Bundle ID | `Mileage.lno.company` (forme inversée, comme Dashcam Pocket) |
| SKU | `milegaeios` |
| Locale principale | `en-US` |
| Version | 1.0 — `PREPARE_FOR_SUBMISSION` |
| Builds | aucun |
| Groupes d'abonnement | **aucun** — à créer par l'API |
| Team | `2E6D4Q69QB` |

Toolchain : Xcode 26.6, runtimes iOS 18.6 → 26.5.

## 1. Périmètre V1

Tracking GPS manuel start/stop irréprochable, historique, Business/Personal, véhicules,
calcul kilométrique international, rapports PDF + CSV, abonnement StoreKit 2 avec essai
3 jours, 6 langues, iCloud, Live Activity, widget.

Hors périmètre V1 (architecture préparée, non implémentée) : détection automatique de
conduite, CarPlay, Bluetooth voiture, Siri/App Intents, Apple Watch, mode employeur.

**Non-objectif explicite** : ce n'est ni un logiciel comptable ni un gestionnaire
automobile. Toute fonction qui ne sert pas « départ → trajet → arrêt → export » est refusée.

## 2. Décisions structurantes

### 2.1 Le tracé GPS n'est pas stocké point par point de façon permanente

`LocationPoint` existe comme entité SwiftData **uniquement pour le trajet en cours** : c'est
le tampon de reprise après crash (§37 de la mission). Au STOP, le tracé est simplifié
(Ramer–Douglas–Peucker, tolérance ~5 m), encodé dans `Trip.encodedRoute: Data`, et les
`LocationPoint` du trajet sont supprimés.

**Pourquoi** : à 1 point / 5 s, un trajet d'une heure produit ~720 points. 1 000 trajets =
~700 000 lignes à synchroniser sur CloudKit. Ingérable en volume, en temps de sync et en
mémoire. Le format compacté conserve le tracé pour la carte du détail de trajet, qui est le
seul usage de lecture après coup.

### 2.2 Le moteur fiscal est déclaratif, pas une classe Swift par pays

Le protocole `MileageRule` de la mission est conservé, mais l'implémentation par défaut est
un **interpréteur unique** (`DeclarativeMileageRule`) qui lit un rule pack JSON versionné.
Un pack décrit : tranches de distance, taux par tranche, constante additive éventuelle,
discriminants véhicule (type, carburant, puissance fiscale, cylindrée), validité temporelle,
devise, unité, source réglementaire, URL, date de dernière vérification.

Ce schéma couvre les trois familles réelles de barèmes :

- **taux plat** (US, DE, BE…) : `montant = d × k`
- **paliers** (GB 10 000 mi, CA 5 000 km) : `d₁ × k₁ + (d − d₁) × k₂`
- **bandes avec constante** (FR, barème CV : `d × k + c`)

Un pays vraiment irréductible pourra recevoir une implémentation Swift dédiée conforme au
même protocole, sans toucher au reste.

**Pourquoi** : les barèmes changent chaque année. Une classe Swift par pays multiplie le
code à maintenir et les risques de régression, alors que la variation réelle entre pays est
une variation de *données*, pas de *logique*.

### 2.3 Aucun taux inventé

Un pays n'obtient un barème officiel que si une source gouvernementale ou fiscale officielle
est trouvée et citée dans le pack (URL + date de vérification). Sinon, le pays bascule
automatiquement en **Custom rate**, et l'app reste pleinement fonctionnelle (tracking,
historique, rapports). Aucune estimation n'est jamais présentée comme une règle officielle.

**Couverture officielle V1 (~12 pays)** : FR, US, GB, CA, DE, BE, CH, AU, IE, NL, ES, IT,
plus PT si une source officielle est trouvable. Tout pays non couvert est accessible en
Custom rate. Un pays dont la source ne peut pas être vérifiée est retiré de la liste plutôt
que rempli au jugé.

### 2.4 Historique figé

Chaque `Trip` conserve `mileageRuleVersion`, `mileageRate` et `calculatedAmount` au moment du
calcul. Aucun recalcul automatique quand un barème change, ni quand l'utilisateur change de
pays ou de véhicule. Recalcul uniquement sur action explicite « Recalculate using current
rules », avec confirmation.

### 2.5 Mise à jour distante des barèmes : client prêt, serveur plus tard

V1 embarque les packs signés (Ed25519, clé privée hors dépôt) et **inclut le client complet**
de mise à jour : fetch, vérification de signature, contrôle de version, mise en cache, rejet
d'un pack invalide, conservation du dernier pack valide. L'URL pointe un endpoint
`crazybeelabs.com` non encore déployé : l'échec réseau est un non-événement, l'app reste
utilisable hors ligne par construction. L'endpoint pourra être activé sans mise à jour d'app.

### 2.6 Modèle d'accès après l'essai

L'essai de 3 jours est un **Introductory Offer StoreKit** (`PAY_UP_FRONT`/free trial) déclaré
dans App Store Connect. Aucun trial local contournable — StoreKit est la seule source de
vérité, via `Transaction.currentEntitlements`.

Sans abonnement actif :

| Action | Accès |
|---|---|
| Ouvrir l'app, consulter tous les trajets | ✅ libre |
| Export CSV de ses données | ✅ libre |
| Supprimer ses données | ✅ libre |
| Démarrer un trajet / ajout manuel | 🔒 paywall |
| Rapport PDF | 🔒 paywall |
| Véhicules au-delà du premier | 🔒 paywall |

Le paywall d'onboarding est **fermable** : l'app s'ouvre alors en mode verrouillé. Un paywall
sans issue est un motif de rejet fréquent en revue Apple, et §32 de la mission interdit de
retenir les données de l'utilisateur derrière le paiement.

## 3. Architecture

```
mileage-pocket/
  App/                 MileagePocketApp, RootView, AppDependencies (injection)
  Core/
    DesignSystem/      couleurs, typographie, composants (BigButton, StatCard…)
    Localization/      AppLanguage, LanguageResolver, LocalizationService
    Persistence/       ModelContainer + configuration CloudKit
    Formatting/        distance, devise, durée, dates (FormatStyle)
  Models/              Trip, LocationPoint, Vehicle, Client, Project, UserSettings,
                       FrequentLocation, ActiveTripState
  Services/
    Location/          TripRecorder, LocationFilter, RouteCompactor, Geocoding
    MileageRules/      CountryRuleEngine, MileageRule, DeclarativeMileageRule,
                       RulePackStore, RulePackVerifier, RulePackUpdater
    Reports/           PDFReportRenderer, CSVExporter, ReportPeriod
    Subscription/      SubscriptionService, ProductIDs, Entitlement
    LiveActivity/      TripActivityController
    Notifications/     NotificationService
  Features/
    Onboarding/ Home/ ActiveTrip/ Trips/ TripDetail/ Vehicles/ Reports/ Settings/ Paywall/
  Resources/           Localizable.xcstrings, Assets.xcassets, MileageRules/<ISO>/*.json
  MileageWidgets/      widget Start Trip + Live Activity (un seul WidgetBundle)
  Tests/ UITests/
```

Injection de dépendances par un conteneur `AppDependencies` passé dans l'environnement
SwiftUI. Pas de singleton hors services système (CLLocationManager, StoreKit).

### 3.1 Cibles Xcode

`gen_pbxproj.py` (repris de `~/pillo-app`, UUID déterministes) génère :

1. `MileagePocket` — app iOS 18.0+
2. `MileageWidgetsExtension` — widget + Live Activity, `dstSubfolderSpec 13`
3. `MileagePocketTests`, `MileagePocketUITests`

`Shared/` compile dans l'app et l'extension (modèles + design system + formatage).

## 4. Tracking GPS

`TripRecorder` derrière `TripRecording` (protocole) pour que toute la logique de distance
soit testable en injectant une suite de `CLLocation` synthétiques.

Configuration : `desiredAccuracy = kCLLocationAccuracyBest`, `distanceFilter = 10 m`,
`activityType = .automotiveNavigation`, `allowsBackgroundLocationUpdates = true`,
`pausesLocationUpdatesAutomatically = false`, `showsBackgroundLocationIndicator = true`.

**Filtrage** (`LocationFilter`, fonction pure, testée) :

1. rejet si `horizontalAccuracy` ≤ 0 ou > 50 m
2. rejet si l'horodatage est antérieur au dernier point accepté ou vieux de > 30 s
3. rejet si la vitesse implicite entre deux points dépasse 60 m/s (216 km/h) — saut GPS
4. seuil de déplacement minimal fonction de la précision : un segment n'est compté que si
   sa longueur dépasse `max(10 m, horizontalAccuracy × 0.5)` — sinon c'est du bruit à l'arrêt
5. trou GPS (tunnel) : si l'écart temporel dépasse 20 s mais reste sous 5 min **et** que la
   distance en ligne droite est cohérente avec la dernière vitesse connue, le segment est
   ponté ; au-delà, le trou est marqué et non compté
6. détection d'arrêt : vitesse < 1 m/s pendant > 2 min → pause, distance non accumulée

Objectif énergie : `distanceFilter` relevé à 25 m au-delà de 90 km/h, abaissé à 10 m en
dessous de 30 km/h. La précision kilométrique n'est jamais sacrifiée.

**Persistance du trajet actif** : `ActiveTripState` (SwiftData, une seule ligne) est écrit à
chaque point accepté (distance cumulée, dernier point, horodatages). Au lancement, si un
état actif existe, l'app propose **Resume active trip** et le tracking reprend.

## 5. Modèle de données

`Trip` : id, startedAt, endedAt, start/end lat-lon, startAddress, endAddress,
rawDistanceMeters, correctedDistanceMeters, duration, tripType, purpose, clientId, projectId,
vehicleId, countryCode, mileageRuleVersion, mileageRate, calculatedAmount, currencyCode,
isManuallyEdited, encodedRoute, createdAt, updatedAt.

`Vehicle`, `Client`, `Project`, `UserSettings`, `FrequentLocation`, `LocationPoint`,
`ActiveTripState`.

Contraintes CloudKit : toute propriété est optionnelle ou a une valeur par défaut, aucune
contrainte `@Attribute(.unique)`, aucune relation obligatoire — sinon le conteneur CloudKit
refuse le schéma au démarrage.

## 6. Rapports

`PDFReportRenderer` (Core Graphics + PDFKit) : en-tête (nom, entreprise, période, véhicule,
pays, règle appliquée), tableau paginé (Date, From, To, Purpose, Distance, Rate, Amount),
totaux, pied de page avec date de génération, version du barème, source, et le disclaimer :

> Calculated using the applicable mileage rate configured in Mileage Pocket. Verify
> eligibility according to your local tax regulations.

Jamais de prétention à un document fiscal certifié.

`CSVExporter` : RFC 4180, virgule, UTF-8 avec BOM (Excel), une ligne par trajet.

Partage par `ShareLink` / Share Sheet iOS.

## 7. Internationalisation

6 langues : EN, FR, ES, DE, IT, PT. `AppLanguage` + `LanguageResolver` + `LocalizationService`
repris du patron Pillo (override explicite > langue système > EN), appliqué par
`\.locale` dans l'environnement — changement de langue sans relancer l'app.

Tous les textes dans `Localizable.xcstrings`. Aucun texte UI en dur. Pluriels gérés par
variations `.xcstrings`. Nombres, devises, dates et unités par `FormatStyle`.

## 8. Abonnement

Produits : `company.lno.mileage.monthly` (2,99 €/mois) et `company.lno.mileage.annual`
(29,99 €/an), un groupe, niveaux 1/1. Essai 3 jours en Introductory Offer sur chaque plan.

Prix **jamais en dur** : lus depuis `Product.displayPrice`. L'économie annuelle (« Save
44 % ») est calculée dynamiquement à partir des deux prix StoreKit.

Configuration ASC créée par l'API : `subscriptionGroups` → `subscriptions` →
localisations → **`subscriptionAvailabilities`** → `subscriptionPrices` (175 territoires) →
`subscriptionIntroductoryOffers` (175 POST par plan).

## 9. Tests

- **Distance** : trajet de distance connue reconstitué à partir de coordonnées réelles, bruit
  gaussien injecté, points aberrants injectés, perte GPS simulée, arrêt prolongé.
- **Règles** : chaque rule pack testé contre des cas calculés à la main depuis la source
  officielle (notamment les bornes de palier, testées *pile* sur la borne).
- **Rapports** : totaux, pagination, périodes à cheval sur un changement d'année.
- **Abonnement** : StoreKit Testing sur **iOS 18.6** (inerte sur les runtimes 26.x) —
  trial, mensuel, annuel, expiré, annulé, restauré, période de grâce.
- **UI** : parcours complet start → stop → business → save en moins de 5 secondes.

## 10. Cas limites traités

GPS désactivé, permission refusée/limitée, perte réseau, reverse geocoding indisponible,
tunnel, batterie faible, mode économie d'énergie, crash pendant un trajet, changement de
fuseau, trajet franchissant minuit ou une frontière ou deux exercices fiscaux, modification
d'un ancien trajet, changement de véhicule, changement de barème en cours d'année.

## 11. Confidentialité

Tout reste local (ou dans l'iCloud privé de l'utilisateur). Aucun tracker, aucun SDK tiers,
aucun backend requis. Le GPS ne sert qu'à la distance, au tracé et aux adresses de départ et
d'arrivée. Reverse geocoding sur ces deux points seulement, jamais sur la trace. Suppression
définitive de toutes les données possible depuis Settings. Privacy Manifest fourni.
