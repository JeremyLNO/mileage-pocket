# Audit « Données, cycle de vie et cas limites » — Mileage Pocket

Date : 2026-09-13 · Périmètre : `Models/`, `Core/Persistence/`, `Shared/`, `App/AppDependencies*.swift`,
`MileageWidgets/`, `Services/Notifications/`, `Services/LiveActivity/` (+ `Services/Location/`,
`Services/MileageRules/`, `Services/Reports/` en appui).
Méthode : lecture seule. Aucune compilation, aucun test lancé. Chaque constat porte `chemin:ligne`.

Légende : **CONFIRMÉ** = lu dans le code, chemin d'exécution complet vérifié. **SOUPÇONNÉ** = raisonnement
solide mais dépendant d'un comportement système que je n'ai pas exercé ici.

---

## 0. Résumé exécutif

Le socle de persistance est sain : aucun `@Attribute(.unique)`, aucune `@Relationship`, toute propriété
optionnelle ou avec défaut — le schéma est réellement compatible CloudKit. Le repli de
`makeContainerWithFallback` est bien pensé. Le filtre GPS est le meilleur morceau du projet.

Ce qui casse est ailleurs, et c'est presque toujours **silencieux** :

1. **On peut enregistrer un trajet sans aucune autorisation de localisation.** Rien ne vérifie
   `.denied`/`.restricted`, rien ne vérifie `locationServicesEnabled()`. L'écran tourne, le chrono
   tourne, le trajet est sauvé à 0 m.
2. **`allowsBackgroundLocationUpdates` n'est jamais vrai dans le parcours nominal.** L'app ne demande
   jamais `Always` après l'onboarding ; écran verrouillé = distance figée.
3. **L'unité n'est pas stockée sur le trajet.** Le taux gelé est dans l'unité du barème, l'affichage et
   le recalcul utilisent l'unité *courante*. Écart ×1,609 sans le moindre signe.
4. **Le seuil des 10 000 miles britanniques est remis à zéro le 1er janvier** au lieu du 6 avril.
5. **Un trajet manuel antidaté avant `validFrom` du barème vaut 0,00 €**, sans avertissement.
6. **Le total d'un rapport additionne des devises différentes** et étiquette la somme avec la première.
7. **La Live Activity ne se termine pas toujours** : elle n'est jamais réadoptée après un kill.
8. **Le toggle iCloud n'est pas câblé** (SwiftData d'un côté, `UserDefaults` de l'autre).

---

## 1. Perte de données

### D1 — CONFIRMÉ · CRITIQUE — Un trajet peut être enregistré à 0 m sans permission, et ça ressemble à un succès

`App/AppDependencies.swift:166-188` · `Services/Location/TripRecorder.swift:106-131`

```
// AppDependencies.swift:170
if recorder.authorizationStatus == .notDetermined {
    recorder.requestPermission()
}
```

`authorizationStatus` n'est lu **qu'ici**, dans tout le projet (vérifié par grep : les seules autres
occurrences sont la définition du protocole, l'implémentation, et un faux de test). `.denied` et
`.restricted` ne sont testés nulle part. `CLLocationManager.locationServicesEnabled()` n'est appelé
nulle part.

`TripRecorder.start(vehicleID:)` ne lève que `RecorderError.alreadyRecording` (`TripRecorder.swift:107`) :
il n'y a **aucune garde de permission**. Le commentaire de `AppDependencies.swift:183-186` —
« Starting can only fail for want of location permission; the view already shows the permission state »
— est faux sur les deux points : `start` ne peut pas échouer pour cette raison, et aucune vue n'affiche
l'état de la permission (`Features/Home/HomeView.swift:156-162` ne teste que le paywall).

**Scénario.** L'utilisateur refuse la localisation à l'onboarding (ou l'a coupée dans Réglages iOS).
Il appuie sur START. `ActiveTripState` est créé et sauvé (`TripRecorder.swift:115-117`),
`state = .recording`, `RootView` bascule sur `ActiveTripView`, le chrono démarre
(`ActiveTripView.swift:76`), la Live Activity démarre, la notification 3 h est armée. Il roule 40 km.
Il appuie sur STOP. `stop()` écrit un `Trip` avec `rawDistanceMeters = 0`, `startLatitude = nil`,
`endLatitude = nil`, pas de route. `applyCalculation` calcule 0,00 €. La feuille de résumé affiche
« 0,0 km ». Le trajet est enregistré, définitivement à zéro.

**Ce qui devrait se produire.** START refusé, avec un message et un lien vers Réglages ; ou au minimum
une bannière permanente sur l'écran de trajet et un refus d'enregistrer un trajet à 0 m.

### D2 — CONFIRMÉ · CRITIQUE — Enregistrement en arrière-plan jamais actif dans le parcours nominal

`Services/Location/CoreLocationProvider.swift:52-76` · `App/AppDependencies.swift:170` ·
`Features/Onboarding/OnboardingFlow.swift:191-192`

```
// CoreLocationProvider.swift:71-73
if manager.authorizationStatus == .authorizedAlways {
    manager.allowsBackgroundLocationUpdates = true
}
```

Trois faits qui se combinent :

- `requestAlways()` (`:52-63`) n'escalade vers `requestAlwaysAuthorization()` que si le statut est
  **déjà** `.authorizedWhenInUse`. Au premier appel (`.notDetermined`) il ne demande que
  `WhenInUse` — ce qui est correct et documenté.
- L'onboarding appelle `dependencies.requestLocationPermission()` **une seule fois**
  (`OnboardingFlow.swift:192`). Il n'y a pas de second écran, pas de second appel.
- `startTrip()` ne rappelle `requestPermission()` que si le statut est `.notDetermined`
  (`AppDependencies.swift:170`). Après l'onboarding il vaut `.authorizedWhenInUse`. **`Always` n'est
  donc jamais demandé de toute la vie de l'app.**

Conséquence : `allowsBackgroundLocationUpdates` reste `false`, et `CLLocationManagerDelegate` n'implémente
pas `locationManagerDidChangeAuthorization` (`CoreLocationProvider.swift:108-122` : seulement
`didUpdateLocations` et `didFailWithError`), donc rien ne réévalue jamais ce réglage même si
l'utilisateur accorde `Always` plus tard depuis Réglages iOS.

**Scénario.** Parcours nominal : onboarding → « Autoriser » → « Lorsque l'app est active ». START.
Le téléphone se verrouille au bout de 30 secondes de conduite. iOS suspend l'app. Plus aucun fix.
Le chrono, lui, est calculé depuis `startedAt` (`AppDependencies.swift:157-160`) et continue d'avancer.
À l'arrivée, l'utilisateur déverrouille : « 1 h 12 min · 0,4 km ». **Le produit ne fonctionne pas, sans
jamais le dire.**

**Ce qui devrait se produire.** Demander `Always` explicitement (2e prompt après le 1er accord),
implémenter `locationManagerDidChangeAuthorization` pour réarmer `allowsBackgroundLocationUpdates`, et
bloquer/avertir tant que le statut n'est pas `.authorizedAlways`.

### D3 — CONFIRMÉ · MAJEUR — L'échec d'écriture d'un trajet est avalé sans trace

`App/AppDependencies.swift:190-206` · `Services/Location/TripRecorder.swift:199`

```
// AppDependencies.swift:195-205
Task {
    defer {
        liveActivity.end(...)
        notifications.cancelTripReminders()
        syncRecorderState()
    }
    guard let trip = try? await recorder.stop() else { return }
    ...
}
```

`try?` efface toute erreur. Si `try context.save()` (`TripRecorder.swift:199`) lève — disque plein,
store verrouillé, migration ratée, objet invalide — alors :

- le `Trip` n'est pas écrit ;
- `reset()` (`TripRecorder.swift:201`) n'est jamais atteint : `tripID`, `startedAt`, `activeState`
  restent posés et `state` reste `.recording` ;
- mais le `defer` termine quand même la Live Activity et **annule le rappel « trajet en cours »** ;
- `syncRecorderState()` laisse `isRecording = true` → l'app reste bloquée sur l'écran de trajet ;
- `provider.stopUpdates()` et `provider.onSample = nil` ont déjà été exécutés (`:172-173`) : **plus
  aucun fix n'est ingéré**, la distance est gelée pour toujours.

**Scénario.** Le trajet disparaît, l'app reste coincée sur un écran de conduite mort, aucune erreur
n'est affichée. Le seul recours est de réappuyer sur STOP (qui relancera `stop()` et peut réussir) ou de
tuer l'app (auquel cas `resumeIfNeeded` reprendra le trajet à la relance — ce qui est le comportement
le moins pire, et il est accidentel).

**Ce qui devrait se produire.** Propager l'erreur, la montrer, ne pas désarmer la Live Activity ni le
rappel tant que le trajet n'est pas écrit.

### D4 — CONFIRMÉ · MAJEUR — « Supprimer toutes mes données » pendant un trajet en cours

`App/AppDependencies+Data.swift:267-280`

`deleteAllData()` supprime les `ActiveTripState` (`:274`) et les `LocationPoint` (`:269`) **sans
arrêter l'enregistreur**. Or `TripRecorder` détient une référence forte à l'objet supprimé
(`TripRecorder.swift:83 : private var activeState: ActiveTripState?`) et le prochain fix accepté écrit
dedans puis sauve (`TripRecorder.swift:251-257`).

Rien non plus n'arrête le provider, ne termine la Live Activity, ni n'annule la notification 3 h.

**Scénario.** L'utilisateur démarre un trajet, va dans Réglages, appuie sur « Tout supprimer », confirme.
Le trajet continue de tourner, écrit dans un objet supprimé (comportement SwiftData indéfini : résurrection
silencieuse de la ligne, ou crash), la Live Activity reste sur l'écran verrouillé, et une notification
« trajet toujours en cours » arrivera 3 h plus tard pour un trajet qui n'existe plus.

**Ce qui devrait se produire.** `deleteAllData()` arrête l'enregistreur, termine la Live Activity,
annule les notifications, puis purge.

### D5 — CONFIRMÉ · MAJEUR — `LocationPoint` sans aucun plafond : la base gonfle sans limite

`Services/Location/TripRecorder.swift:240-257`

Une ligne insérée **et un `context.save()`** par fix accepté. Aucun plafond de nombre, aucun plafond
d'âge, aucun élagage périodique. Le seul nettoyage est au `stop()` (`:197`) ou au prochain `start()`
(`:293-299`).

Le mode de défaillance que la spec elle-même désigne comme le pire — « oublier d'appuyer sur STOP »
(`Services/Notifications/NotificationService.swift:6-7`) — est exactement celui qui rend cette croissance
non bornée. Avec le `distanceFilter` à 10 m en ville, un trajet oublié pendant trois jours de conduite
produit des centaines de milliers de lignes.

Au `stop()` suivant, `storedPoints(for:)` (`:279-285`) charge **tout** en mémoire d'un coup, puis
`RouteCompactor.simplify` (`RouteCompactor.swift:14-57`) est un RDP dont la boucle interne est O(n) par
découpe — pire cas O(n²).

**SOUPÇONNÉ** (non exercé) : sur un très grand nombre de points, `stop()` peut faire dépasser la mémoire
ou bloquer le thread principal plusieurs secondes, exactement au moment où la spec exige « fin de trajet
en moins de 5 secondes » (plan, Task 14).

### D6 — CONFIRMÉ · MOYEN — Orphelins `LocationPoint` irrécupérables si une lecture échoue

`Services/Location/TripRecorder.swift:176`

```
let points = (try? storedPoints(for: tripID)) ?? []
```

Si ce `fetch` lève, `points` vaut `[]` : **la route n'est pas encodée** (`:187-191` sautés) **et les
points ne sont pas supprimés** (`:197` itère sur un tableau vide). L'`ActiveTripState`, lui, est bien
supprimé (`:198`). Les points deviennent alors définitivement orphelins : `discardActiveState()`
(`:293-299`) ne sait nettoyer que les points rattachés à un `ActiveTripState` encore présent.

Même famille : `App/AppDependencies+Data.swift:11-13, 33, 46, 129, 135, 268-274` — partout des
`(try? context.fetch(...)) ?? []`. Un échec de lecture ne se distingue jamais d'un magasin vide.

### D7 — CONFIRMÉ · MOYEN — Aucune cascade : supprimer un véhicule re-tarife silencieusement l'historique

`App/AppDependencies+Data.swift:11-15`

```
func vehicle(for id: UUID?) -> Vehicle? {
    guard let id else { return defaultVehicle() }
    let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
    return vehicles.first { $0.id == id } ?? defaultVehicle()   // <- substitution silencieuse
}
```

Les liens sont des `UUID` nus (`Trip.clientID`, `projectID`, `vehicleID` — `Models/Trip.swift:34-36`),
sans relation ni cascade. Supprimer un `Vehicle`/`Client`/`Project` laisse des identifiants pendants.

**Scénario.** L'utilisateur roulait en Renault Clio (5 CV), la revend et la supprime, crée une Tesla
(par défaut). Il ouvre un trajet de l'an dernier et appuie sur « Recalculer avec les règles actuelles »
(`TripDetailView.swift:49`) : `applyCalculation` → `vehicle(for: trip.vehicleID)` ne trouve plus la Clio
et renvoie **la Tesla**. Le trajet est re-tarifé au barème véhicule électrique. Aucune alerte.
Dans l'écran détail, la ligne « Véhicule » affiche déjà la Tesla (`TripDetailView.swift:105`) pour un
trajet fait en Clio.

### D8 — CONFIRMÉ · MINEUR — `stopTrip()` ne rafraîchit pas l'instantané widget

`App/AppDependencies.swift:190-206` : aucun `refreshWidgetSnapshot()`. Voir **W3**.

---

## 2. CloudKit

État du build : `Config/Base.xcconfig:26 → CLOUDKIT_AVAILABLE = NO`, entitlements vides
(`App/MileagePocket.entitlements`). `CloudKitAvailability.isEntitled` renvoie donc `false` et
`makeContainerWithFallback` (`PersistenceController.swift:37-47`) ouvre un store **local**. Tous les
constats ci-dessous sauf C1 sont donc **latents** : ils se déclenchent le jour où le conteneur existe.

### C1 — CONFIRMÉ · Le schéma est réellement compatible

Vérifié par grep sur tout le projet : **aucune** occurrence de `@Attribute`, `@Relationship` ou
`@Transient`. Les huit modèles (`PersistenceController.swift:11-20`) n'ont que des propriétés scalaires,
toutes optionnelles ou avec valeur par défaut — y compris `ActiveTripState.id/tripID/startedAt/...`
(`Models/ActiveTripState.swift:10-21`) et `LocationPoint` (`Models/LocationPoint.swift:10-19`).
`Decimal?` (`Trip.mileageRate`, `calculatedAmount`) et `Data?` (`encodedRoute`) sont des types supportés.

Réserve : `Tests/PersistenceTests.swift:44-55` (`testEveryModelCanBeCreatedWithoutArguments`) est présenté
comme le garde-fou CloudKit, mais il ouvre un store **local en mémoire** (`:7`). Il prouve que les modèles
ont des défauts, il ne prouve rien sur l'ouverture d'un store CloudKit. Le chemin
`makeContainer(cloudKitEnabled: true)` n'est exercé par aucun test.

### C2 — CONFIRMÉ · MAJEUR (latent) — Le réglage iCloud n'est pas câblé

`Features/Settings/SettingsView.swift:181-182` écrit dans **SwiftData** :

```
set: { settings.iCloudSyncEnabled = $0; dependencies.settingsStore.save() }
```

`App/MileagePocketApp.swift:11` lit dans **UserDefaults** :

```
let cloudEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
```

Grep sur tout le projet : `UserDefaults` n'apparaît que là (plus un commentaire dans
`InstallDateStore.swift:6`). **Rien n'écrit jamais cette clé.** Elle vaut donc toujours `nil` → `true`.

**Scénario (le jour où le conteneur existe).** L'utilisateur coupe « Synchronisation iCloud ». La bascule
reste visuellement à off (elle lit `settings.iCloudSyncEnabled`). Il relance l'app : le store est rouvert
avec `.private(cloudKitContainerIdentifier)`. Ses trajets continuent de partir dans iCloud. Le
commentaire de `SettingsView.swift:184-185` — « a sync switch that lies about syncing is how someone
loses data they believed was backed up » — décrit exactement le défaut présent dans le fichier.

### C3 — CONFIRMÉ · CRITIQUE (latent) — `ActiveTripState` est synchronisé : deux appareils, un même trajet

`Core/Persistence/PersistenceController.swift:19` (`ActiveTripState.self` dans le schéma synchronisé) ·
`Services/Location/TripRecorder.swift:287-291`

```
private func fetchActiveState() throws -> ActiveTripState? {
    try context.fetch(
        FetchDescriptor<ActiveTripState>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
    ).first
}
```

Aucun filtre d'appareil, aucune notion de propriétaire, aucune configuration local-only pour ce modèle.

**Scénario.** L'utilisateur démarre un trajet sur son iPhone. L'`ActiveTripState` est écrit et sauvé à
chaque fix, donc poussé dans iCloud. Il ouvre l'app sur son iPad (qui est dans la voiture, ou resté chez
lui). `bootstrap()` → `try? recorder.resumeIfNeeded()` (`AppDependencies.swift:118`) trouve la ligne,
la croit sienne, et **démarre un enregistrement** avec le `tripID` de l'iPhone. Les deux appareils
écrivent des `LocationPoint` sous le même `tripID`. À l'arrêt, chacun exécute
`Trip(id: tripID)` + `context.insert` (`TripRecorder.swift:179, 193`) : comme `id` n'est pas `.unique`,
**deux `Trip` distincts portent le même `id`**.

Conséquences en aval : `Trip: Identifiable` (`Models/Trip.swift:13`) → `ForEach`/`List` sur un id dupliqué,
et `.sheet(item: $dependencies.finishedTrip)` (`RootView.swift:24`) ne peut plus distinguer les deux.
`ReportBuilder.yearlyDistanceMeters` exclut par `$0.id != trip.id` (`ReportBuilder.swift:98`) et écartera
donc le jumeau, faussant le cumul annuel.

### C4 — CONFIRMÉ · MAJEUR (latent) — `UserSettings` n'est « unique » que par convention

`Core/Persistence/SettingsStore.swift:20-33`

```
let descriptor = FetchDescriptor<UserSettings>(sortBy: [SortDescriptor(\.id)])
if let existing = try? context.fetch(descriptor).first { return existing }
```

Le tri porte sur un `UUID` aléatoire. Sur un appareil unique, `fetchOrCreate` garantit bien une ligne
(c'est ce que le commentaire promet). Avec CloudKit, deux appareils qui ont lancé l'app avant la première
synchro ont chacun créé la leur : après fusion il y a **deux** `UserSettings`, et celle qui gagne est
décidée par l'ordre des UUID.

**Scénario.** L'utilisateur configure la France sur son iPhone, puis installe l'app sur son iPad qui crée
sa propre ligne aux valeurs détectées (`:26-29`). Après synchro, au lancement suivant, le pays, la devise,
l'unité, le véhicule par défaut et le mode de taux peuvent basculer sur l'autre ligne. Pire : `applyCountry`
n'agit que sur l'instance détenue par le `SettingsStore` — l'autre ligne reste et peut regagner plus tard.
**Et comme `applyCalculation` fige `settings.countryCode` sur chaque nouveau trajet
(`AppDependencies.swift:261`), un basculement de ligne fige un mauvais pays dans l'historique.**

### C5 — CONFIRMÉ · MOYEN (latent) — Les points bruts vont bien dans iCloud, contrairement à ce que dit la doc

`Models/Trip.swift:49-52`, `Models/LocationPoint.swift:6-7`, `Services/Location/TripRecorder.swift:195-196`
et `Services/Location/RouteCompactor.swift:5-7` affirment tous que garder les `LocationPoint` mettrait
« des centaines de milliers d'enregistrements dans la base CloudKit de l'utilisateur ».

`LocationPoint` est dans le schéma synchronisé (`PersistenceController.swift:13`) et chaque fix est
inséré **et sauvé** pendant la conduite (`TripRecorder.swift:240-257`). Ils sont donc bien poussés vers
CloudKit en direct, puis supprimés à l'arrêt. La suppression n'annule ni le trafic réseau, ni la
consommation batterie, ni le quota consommé pendant le trajet.

### C6 — SOUPÇONNÉ · MOYEN — Deux appareils modifiant le même trajet

Aucun code de résolution de conflit nulle part. `Trip.updatedAt` existe (`Models/Trip.swift:55`) et est
mis à jour partout, mais **n'est lu par aucune ligne du projet** (grep : uniquement des écritures).
NSPersistentCloudKitContainer applique un dernier-écrivain-gagne par enregistrement.

**Scénario attendu.** L'iPhone corrige la distance d'un trajet à 42 km (`correctedDistanceMeters`,
`isManuallyEdited = true`) ; l'iPad, hors ligne, reclasse le même trajet en « personnel ». À la
reconnexion, l'une des deux modifications est écrasée en silence. Aucune trace, aucun avertissement.

---

## 3. Les 16 cas limites du §39

| # | Cas | Verdict | Preuve |
|---|-----|---------|--------|
| 1 | GPS désactivé (Localisation coupée système) | **Pas traité** | `locationServicesEnabled()` absent du projet (grep). `startTrip` `AppDependencies.swift:166-188` n'a aucune garde. Voir **D1**. |
| 2 | Permission refusée ou limitée | **Pas traité** | `authorizationStatus` lu seulement en `AppDependencies.swift:170`, et uniquement contre `.notDetermined`. `TripRecorder.start:106-131` sans garde. Pas de `locationManagerDidChangeAuthorization` (`CoreLocationProvider.swift:108-122`). Voir **D1**, **D2**. |
| 3 | Perte réseau | **Traité** | Rien dans le chemin d'enregistrement n'exige le réseau. `GeocodingService.swift:21-23` renvoie `nil` sur échec. Le trajet est sauvé **avant** les `await` de géocodage (`TripRecorder.swift:199` puis `:205-210`). `RulePackUpdater` en `Task.detached` best-effort (`AppDependencies.swift:123-125`). |
| 4 | Géocodage indisponible | **Traité** | Idem ; l'UI affiche « — » (`TripSummarySheet.swift:72`, `TripDetailView.swift:100-101`). *Réserve* : aucun réessai ultérieur et aucune saisie manuelle d'adresse sur un trajet enregistré — l'adresse manquante l'est définitivement. |
| 5 | Tunnel | **Traité** | `LocationFilter.swift:138-141` (silence > 300 s → rejet, pas d'invention), `:172-190` (pont 20 s–300 s si la vitesse implicite est plausible), `:178-181` (un `refusedJump` interdit le pont). Couvert par `Tests/LocationFilterTests.swift`. |
| 6 | Batterie faible | **Pas traité** | Aucune lecture de `batteryLevel`/`batteryState` dans le projet (grep vide). Aucune dégradation gracieuse, aucun avertissement. |
| 7 | Mode économie d'énergie | **Pas traité** | `ProcessInfo.isLowPowerModeEnabled` absent du projet (grep vide). Atténuations connexes mais non liées : `pausesLocationUpdatesAutomatically = false` (`CoreLocationProvider.swift:47`) et le `distanceFilter` adaptatif (`:94-105`). En LPM, iOS bride la localisation en arrière-plan : ni détecté, ni signalé. |
| 8 | Crash pendant un trajet | **Partiel** | Le socle est bon : `ActiveTripState` réécrit à chaque fix (`TripRecorder.swift:251-257`), `resumeIfNeeded:139-165` restaure distance, ancrages et route. **Mais** : (a) la reprise est silencieuse et sans borne d'ancienneté — un état vieux de 5 jours redevient un trajet actif de 5 jours ; le commentaire `ActiveTripState.swift:6-7` promet « offers to resume », le code reprend sans demander ; (b) le rappel 3 h n'est **pas** réarmé (voir **N2**) ; (c) la Live Activity du processus mort n'est ni réadoptée ni terminée (voir **W4**). |
| 9 | Changement de fuseau | **Partiel** | Choix assumé et correct pour la liste : `TripGrouping.swift:19-23` et `:40-45` (le bug `isDateInToday` a été vu et corrigé). **Mais** `Trip` ne stocke aucun fuseau et `ReportPeriod.range` utilise `Calendar.current` (`:22-45`) : un trajet du 31/01 23:30 à Tokyo bascule silencieusement dans le rapport de février une fois rentré à Paris — et donc change de total mensuel. |
| 10 | Changement de pays | **Partiel** | Bon : `SettingsStore.applyCountry:41-46` ne touche aucun trajet, `trip.countryCode` est gelé (`AppDependencies.swift:261`) et l'historique n'est réécrit que par l'action explicite `recalculate` (`:306-311`). **Mais** `ReportBuilder.build:74` somme `amount` toutes devises confondues et `:84` étiquette le total avec `rows.compactMap(\.currencyCode).first` — voir **R1**, un faux chiffre. |
| 11 | Trajet franchissant une frontière | **Traité par conception** | Un trajet porte un pays unique, celui des réglages, gelé à l'enregistrement (`Trip.swift:9-11`, `AppDependencies.swift:261`). Aucun découpage, aucune détection — c'est l'intention documentée et c'est le bon choix fiscal. Rien à corriger, mais rien n'est « géré » non plus. |
| 12 | Trajet à cheval sur minuit | **Traité** | `ReportPeriod.swift:4-8` (le trajet appartient à la période de son **début**), plages semi-ouvertes `:20-21`, `TripGrouping.section:46-55` sur `startedAt`. Couvert par `Tests/TripGroupingTests.swift` et `Tests/ReportTests.swift`. |
| 13 | Trajet sur deux exercices fiscaux | **Partiel — et faux pour le Royaume-Uni** | La règle « le début décide » est bonne et testée. **Mais** `ReportPeriod.taxYear:54-56` renvoie l'année **civile**, et le commentaire `:52-53` prétend que les pays à exercice décalé « sont gérés par la fenêtre de validité de leur pack ». Une fenêtre de validité ne remet pas à zéro un compteur cumulatif. Or `Resources/MileageRules/GB/2026.1.json` est un barème `marginal` à seuil 10 000 miles (0,55 puis 0,25 £) et l'exercice HMRC démarre le **6 avril**. `ReportBuilder.yearlyDistanceMeters:96-102` remet donc l'allocation à zéro le 1er janvier. Voir **R2**. |
| 14 | Modification d'un ancien trajet | **Partiel** | Bon : `correctedDistanceMeters` n'écrase jamais `rawDistanceMeters` (`Trip.swift:26-29`, testé `PersistenceTests.swift:57-65`) ; `recalculateWithFrozenRule` conserve le taux gelé (`AppDependencies.swift:291-302`). **Mais** la conversion utilise l'unité **courante** alors que le taux est dans l'unité du **barème** — voir **R3**, écart ×1,609 silencieux. Et `recalculate` (`:306-311`) re-fige `countryCode`, `rateMode` et le barème d'aujourd'hui sur un trajet ancien, en s'appuyant sur un véhicule qui peut avoir été substitué (**D7**). |
| 15 | Changement de véhicule | **Partiel** | Bon : `vehicleID` gelé sur le trajet, `Vehicle` porte le sur-ensemble des champs pour que changer de pays ne perde rien (`Vehicle.swift:4-5`), un seul véhicule par défaut garanti (`AppDependencies+Data.swift:66-77`). **Mais** aucune cascade et substitution silencieuse par le véhicule par défaut — voir **D7**. |
| 16 | Changement de barème en cours d'année | **Partiel** | La mécanique est là et correcte : `RulePackStore.pack(country:on:):36-43` sélectionne par date la plus haute version valide, `currentRule(on: trip.startedAt)` (`AppDependencies.swift:270`), `RulePack.isValid:26-30`, et `ReportData.ruleVersions` (`ReportBuilder.swift:85`) signale plusieurs barèmes dans une période. **Mais** il n'existe qu'un pack par pays et plusieurs démarrent en cours de 2026 : US `2026-07-01`, GB `2026-04-06`, AU `2026-07-01`, BE `2026-07-01`, PT `2026-01-30`. Un trajet daté avant cette borne ne trouve **aucun** pack et retombe sur `CustomRateRule(ratePerUnit: customRate ?? 0)` → voir **R4**, un trajet à 0,00 €. |

**Décompte : 5 cas sur 16 réellement traités** (3, 4, 5, 11, 12) · **7 partiels** (8, 9, 10, 13, 14, 15, 16)
· **4 pas traités du tout** (1, 2, 6, 7).

---

## 4. Défauts silencieux de calcul

### R1 — CONFIRMÉ · MAJEUR — Un total de rapport additionne des devises différentes

`Services/Reports/ReportBuilder.swift:74` et `:84`

```
let total = rows.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
...
currencyCode: rows.compactMap(\.currencyCode).first ?? fallbackCurrency,
```

`trip.currencyCode` est gelé par trajet (`AppDependencies.swift:283`). Le total additionne des `Decimal`
sans regarder leur devise, et l'étiquette est celle du **premier** trajet de la période.

**Scénario.** Un consultant s'installe en France le 15 mars. Trajets du 1er au 14 en USD, du 15 au 31 en
EUR. Le rapport de mars affiche `$1 240,00` — une somme de dollars et d'euros libellée en dollars.
Idem sur l'accueil (`HomeModel.swift:37`) et dans l'instantané widget (`AppDependencies+Data.swift:293-295`).
Le PDF part chez un employeur ou une administration avec ce chiffre.

**Ce qui devrait se produire.** Regrouper par devise, refuser de produire un total unique, ou afficher un
total par devise.

### R2 — CONFIRMÉ · MAJEUR — Le seuil britannique des 10 000 miles se réinitialise le 1er janvier

`Services/Reports/ReportPeriod.swift:51-56` · `Services/Reports/ReportBuilder.swift:91-103` ·
`Resources/MileageRules/GB/2026.1.json`

`taxYear(of:)` renvoie `calendar.component(.year, from: date)`. L'exercice HMRC court du 6 avril au
5 avril.

**Scénario.** Un utilisateur britannique a parcouru 12 000 miles professionnels entre le 6 avril 2026 et
le 31 décembre 2026. Il est donc dans la tranche à 0,25 £/mile. Le 4 janvier 2027 il fait 100 miles :
`yearlyDistanceMeters` ne compte que les trajets de **2027**, soit 0, et facture les 100 miles à
**0,55 £** au lieu de 0,25 £. Symétriquement, ses trajets de janvier à début avril 2026 ont été comptés
dans le cumul de 2026 alors qu'ils relèvent de l'exercice précédent. Le chiffre est faux dans les deux
sens et le rapport le présente comme officiel (`isOfficialRate = true`).

**Ce qui devrait se produire.** Le pack doit porter l'origine de son exercice (mois/jour) et `taxYear`
doit la respecter.

### R3 — CONFIRMÉ · MAJEUR — L'unité n'est pas stockée sur le trajet ; le taux gelé est réinterprété

`Models/Trip.swift:38-44` (aucun champ d'unité) · `App/AppDependencies.swift:291-302` ·
`Features/TripDetail/TripDetailView.swift:17, 79, 121, 134, 185` ·
`App/AppDependencies+Data.swift:260`

Le taux gelé `trip.mileageRate` est exprimé dans l'unité **du barème** :
`DeclarativeMileageRule.swift:38-49` convertit avec `distanceUnit` = `pack.distanceUnit`. Pour un
`CustomRateRule`, c'est l'unité des **réglages au moment du calcul** (`CountryRuleEngine.swift:38-44`).
Le `Trip` ne mémorise ni l'une ni l'autre.

Partout en aval, c'est l'unité **courante** qui est utilisée :

```
// AppDependencies.swift:296-298
let unit = settingsStore.settings.distanceUnit
let distance = Decimal(unit.value(fromMeters: trip.distanceMeters))
trip.calculatedAmount = MileageRounding.money(distance * rate)
```

Et l'unité des réglages est modifiable **indépendamment du pays** (`SettingsView.swift:94-95`) :
il n'est même pas nécessaire de déménager pour créer l'écart.

**Scénario A (affichage, aucun geste requis).** Utilisateur en France (barème en km, 0,647 €/km) qui
préfère les miles à l'affichage. `TripDetailView.swift:121` rend `Fmt.rate(rate, unit: unit)` →
« 0,647 €/mi ». Le taux affiché est faux de 61 %. Même chose dans le PDF et le CSV :
`reportProfile()` (`AppDependencies+Data.swift:260`) passe `settings.distanceUnit` pour **toutes** les
lignes historiques.

**Scénario B (recalcul, chiffre faux écrit en base).** Même utilisateur. Il ouvre un trajet ancien de
50 km et corrige la distance. `TripDetailView.swift:134` pré-remplit le champ en miles (31,07),
`applyDistanceEdit:185` convertit 31,07 mi → 50 000 m (correct), puis
`recalculateWithFrozenRule` reconvertit 50 000 m en **miles** (31,07) et multiplie par le taux **par
kilomètre** (0,647) → 20,10 € au lieu de 32,35 €. **Le montant faux est sauvé.** Aucune erreur, aucun
avertissement, et le trajet porte désormais le badge « modifié manuellement » qui laisse croire que
l'utilisateur a voulu ce chiffre.

### R4 — CONFIRMÉ · MAJEUR — Un trajet manuel antidaté vaut 0,00 €, en silence

`Features/ManualTrip/ManualTripView.swift:35` (`DatePicker(..., in: ...Date.now)` — tout le passé est
autorisé) · `Services/MileageRules/CountryRuleEngine.swift:33-44` · `Services/MileageRules/RulePackStore.swift:36-43`

```
if mode == .official, let pack = store.pack(country: countryCode, on: date) {
    return DeclarativeMileageRule(pack: pack)
}
return CustomRateRule(..., ratePerUnit: customRate ?? 0, ...)
```

Pas de pack valide à cette date → `CustomRateRule` avec `customRate ?? 0` → `rate = 0`, `amount = 0`,
`isOfficial = false`, `ruleVersion = "custom"`.

Dates de début des packs livrés : US `2026-07-01`, GB `2026-04-06`, AU `2026-07-01`, BE `2026-07-01`,
PT `2026-01-30`, CA/CH/DE/NL `2026-01-01`, FR `2025-01-01`, ES `2023-07-17`, IE `2022-09-01`.
Le pays par défaut du modèle est `"US"` (`Models/UserSettings.swift:13`, `Models/Trip.swift:38`).

**Scénario.** Un utilisateur américain (aujourd'hui 13 septembre 2026) saisit ses trajets de mars 2026
qu'il avait notés sur un carnet. `pack("US", on: 2026-03-xx)` → `nil` (validFrom = 1er juillet). Chaque
trajet est enregistré à **0,00 $**, marqué non officiel. L'écran de réglages affiche pourtant
« barème officiel disponible » parce que `hasOfficialRule()` est évalué à `.now`
(`AppDependencies+Data.swift:97-99`). L'utilisateur se retrouve avec une moitié d'année à zéro dollar
dans son rapport.

**Ce qui devrait se produire.** Soit livrer les packs antérieurs, soit refuser/avertir explicitement
quand aucun barème ne couvre la date saisie — jamais produire 0,00 en silence.

### R5 — CONFIRMÉ · MINEUR — Un trajet reclassé « personnel » garde son versionnement de règle

`App/AppDependencies.swift:263-268` : sur `.personal`, `calculatedAmount` et `mileageRate` sont remis à 0
mais `mileageRuleVersion` et `isOfficialRate` restent ceux du calcul précédent. `ReportData.ruleVersions`
(`ReportBuilder.swift:85`) est construit sur `selected`, qui exclut les personnels par défaut — donc sans
impact dans le rapport standard, mais l'export « toutes données » (`includePersonal: true`,
`AppDependencies+Data.swift:232-244`) les inclut.

---

## 5. Widget et Live Activity

### W1 — CONFIRMÉ · Sans App Group, le widget est honnête

`App/MileagePocket.entitlements` et `MileageWidgets/MileageWidgets.entitlements` sont des `<dict/>` vides :
aucun `com.apple.security.application-groups`.

`Shared/WidgetSnapshot.swift:30-34` : `containerURL(forSecurityApplicationGroupIdentifier:)` renvoie `nil`
→ `write` sort au premier `guard` (`:37`), `read()` renvoie `nil` (`:45`).

`StartTripWidget.swift:19` passe donc `snapshot: nil` à la timeline, et la vue tombe dans la branche
`else` (`:80-84`) : icône + « Start Trip » + « No trips yet » (valeurs anglaises vérifiées dans
`Resources/Localizable.xcstrings`). **Aucun zéro présenté comme un vrai chiffre sur ce chemin.**

### W2 — CONFIRMÉ · MOYEN — `getSnapshot` renvoie des chiffres inventés sans vérifier `isPreview`

`MileageWidgets/StartTripWidget.swift:14-16`

```
func getSnapshot(in context: Context, completion: ...) {
    completion(StartTripEntry(date: .now, snapshot: WidgetSnapshotStore.read() ?? .placeholder))
}
```

`WidgetSnapshot.placeholder` (`Shared/WidgetSnapshot.swift:16-23`) vaut **486 000 m** et « September ».
`context.isPreview` n'est jamais consulté. Dans la galerie de widgets c'est l'usage attendu ; hors
prévisualisation (instantané système), l'utilisateur voit **486 km qu'il n'a jamais parcourus**, présentés
exactement comme ses vrais chiffres. Dans ce build — App Group absent — `read()` renvoie toujours `nil`,
donc c'est **toujours** le placeholder qui sort de `getSnapshot`.

### W3 — CONFIRMÉ · MOYEN — `isTripInProgress` est un champ mort

`App/AppDependencies+Data.swift:296` écrit `isTripInProgress: isRecording`. Les cinq seuls appelants de
`refreshWidgetSnapshot()` sont `finishTrip` (`AppDependencies.swift:216`), `clearFinishedTrip` (`:222`),
`createManualTrip` (`AppDependencies+Data.swift:177`), `delete` (`:184`) et `deleteAllData` (`:278`).
**Ni `startTrip()` ni `stopTrip()` ne l'appellent.** À chacun de ces cinq points, `isRecording` vaut
`false`. Le widget ne peut donc jamais afficher « Trip in progress » (`StartTripWidget.swift:46-48`),
ni pendant un trajet, ni après. La branche `record.circle` est inatteignable.

### W4 — CONFIRMÉ · MAJEUR — La Live Activity ne se termine pas toujours

`Services/LiveActivity/TripActivityController.swift:17, 26-37, 55-64`

```
private var activityID: String?          // :17 — état de processus, non persisté
func start(...) { guard ..., activityID == nil else { return } ... }   // :27
func end(...)   { guard let activityID else { return } ... }          // :56
```

Rien ne balaie `Activity<TripAttributes>.activities` au lancement. `bootstrap()`
(`AppDependencies.swift:101-126`) ne touche pas `liveActivity`.

**Scénario.** Trajet en cours, Live Activity affichée sur l'écran verrouillé. L'app est tuée (OOM, crash,
ou balayage utilisateur). La Live Activity **survit** — c'est le propre d'ActivityKit. L'utilisateur
rouvre l'app : `resumeIfNeeded()` reprend le trajet, mais `activityID` est `nil`. La Live Activity
affiche pour toujours la distance et le chrono du processus mort. L'utilisateur appuie sur STOP :
`stopTrip()` appelle `liveActivity.end(...)` qui **sort immédiatement** au `guard` de la ligne 56.
La Live Activity reste sur l'écran verrouillé jusqu'au délai d'expiration d'iOS (8 h, 12 h max),
en affichant un trajet terminé comme s'il continuait. `start()` n'en créera pas de nouvelle non plus
tant que `activityID` est `nil`… si, justement — `start()` la recréerait au trajet **suivant**, en
laissant l'ancienne : deux activités simultanées.

**Ce qui devrait se produire.** Au lancement, énumérer `Activity<TripAttributes>.activities` : réadopter
la sienne si un `ActiveTripState` existe, la terminer sinon.

### W5 — CONFIRMÉ · MINEUR — Pas d'état « en pause » dans la Live Activity

`TripAttributes.ContentState` (`Shared/TripAttributes.swift:10-18`) ne transporte pas l'état pause.
`syncRecorderState` (`AppDependencies.swift:245-251`) pousse des mises à jour tant que `isRecording`,
donc y compris en `.paused`, où l'écran de l'app affiche « en pause » (`ActiveTripView.swift:94-98`) mais
pas le verrouillé.

---

## 6. Notifications

### N1 — CONFIRMÉ · Le rappel EST annulé sur tous les chemins qui passent par STOP

`App/AppDependencies.swift:195-200` : le `defer` s'exécute quel que soit le résultat de
`recorder.stop()`, donc y compris en cas d'échec. L'abandon depuis la feuille de résumé
(`TripSummarySheet.swift:208-213`) n'a **pas** besoin d'annuler : l'annulation a déjà eu lieu avant que
la feuille n'apparaisse (`finishedTrip` est posé ligne 204, après le `stop()`). ✔

### N2 — CONFIRMÉ · MAJEUR — Le rappel n'est pas réarmé après une reprise de crash

`scheduleTripStillRunningReminder()` n'est appelé qu'en `AppDependencies.swift:181`, dans `startTrip()`.
`bootstrap()` appelle `try? recorder.resumeIfNeeded()` (`:118`) sans rien programmer.

**Scénario.** L'app est tuée pendant un trajet à 9 h. L'utilisateur la rouvre à 9 h 05, le trajet reprend.
Il arrive à 9 h 30 et oublie STOP. **Aucune notification n'arrivera jamais.** Le filet de sécurité
décrit comme « the one that earns its place » (`NotificationService.swift:5-7`) est absent précisément
dans le scénario où personne n'a appuyé sur STOP.

### N3 — CONFIRMÉ · MOYEN — `deleteAllData()` n'annule pas le rappel

`AppDependencies+Data.swift:267-280` : aucun appel à `notifications`. Une notification « trajet toujours
en cours » peut arriver 3 h après une purge complète.

### N4 — CONFIRMÉ · MOYEN — Impossible de couper les notifications depuis l'app

- `NotificationService.cancelAll()` (`:72-74`) n'est appelé **nulle part** (grep).
- `UserSettings.notificationsEnabled` (`Models/UserSettings.swift:29`) est écrit une seule fois
  (`AppDependencies.swift:334`) et **lu nulle part**. C'est un champ mort, synchronisé via CloudKit.
- `SettingsView` n'a aucune bascule notifications (grep sur `notificationsEnabled` : aucune occurrence
  dans `Features/`).
- `scheduleMonthlyReportReminder()` pose un `UNCalendarNotificationTrigger(repeats: true)` (`:68`) que
  rien ne peut retirer depuis l'app.

### N5 — CONFIRMÉ · MINEUR — Le rappel ne se répète pas

`UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)` (`:37`). Un trajet oublié
pendant une semaine produit **une** notification, à H+3. Si elle est manquée, plus rien.

---

## 7. Migration

### M1 — CONFIRMÉ · Aucun versionnement de schéma

Grep : aucun `VersionedSchema`, `SchemaMigrationPlan`, `MigrationStage` ni `originalName` dans le projet.
`PersistenceController.schema` (`:11-20`) est un `Schema` nu.

### M2 — CONFIRMÉ · Ajouter un champ optionnel ou avec défaut ne cassera rien

C'est exactement la contrainte que les modèles respectent déjà pour CloudKit (voir **C1**). SwiftData
fait alors une migration légère automatique et une installation existante survit. **Tant que la règle
tient, le risque est nul.**

### M3 — CONFIRMÉ · CRITIQUE — Le repli de lancement transforme une migration ratée en « vous n'avez aucun trajet »

`Core/Persistence/PersistenceController.swift:37-47`

```
static func makeContainerWithFallback(cloudKitEnabled: Bool) -> ModelContainer {
    if cloudKitEnabled, CloudKitAvailability.isEntitled, let container = try? makeContainer(cloudKitEnabled: true) {
        return container
    }
    if let container = try? makeContainer(cloudKitEnabled: false) {
        return container
    }
    return try! makeContainer(cloudKitEnabled: false, inMemory: true)
}
```

Le jour où quelqu'un ajoute une propriété **non optionnelle sans défaut**, renomme un champ ou change un
type, `makeContainer(cloudKitEnabled: false)` lève. Le `try?` l'avale et l'app ouvre un conteneur
**en mémoire**.

**Scénario.** L'utilisateur installe la mise à jour. L'app se lance normalement — pas de crash, pas
d'alerte. `SettingsStore.fetchOrCreate` (`SettingsStore.swift:20-33`) ne trouve rien et **crée une
nouvelle ligne de réglages**, remettant le pays sur la détection automatique et effaçant le nom, la
société, le véhicule par défaut et le mode de taux. L'écran d'accueil affiche « Aucun trajet ».
L'onboarding se relance (`hasCompletedOnboarding = false`, `RootView.swift:13`). L'utilisateur croit
avoir tout perdu. Ses données sont intactes sur le disque, mais rien dans l'app ne le lui dit, et à la
prochaine fermeture tout ce qu'il aura saisi dans le store en mémoire disparaîtra à son tour.

Le commentaire de `:31-33` assume ce repli pour le cas « compte iCloud indisponible » — ce qui est juste.
Le problème est qu'il attrape aussi le cas « migration ratée », qui demande exactement l'inverse :
s'arrêter bruyamment.

**Ce qui devrait se produire.** Distinguer les deux : replier sur le local uniquement pour une erreur
CloudKit, et pour une erreur de migration afficher un écran d'erreur explicite sans jamais ouvrir un
store en mémoire par-dessus des données existantes.

### M4 — CONFIRMÉ · Le format de route est versionné, lui

`RouteCompactor.swift:89, 118` : un octet de version, et `decode` renvoie `[]` pour tout ce qu'il ne sait
pas lire. Une route illisible coûte une ligne sur une carte, pas le trajet. ✔

---

## 8. Ce qui est bien fait (pour ne pas le casser en corrigeant)

- `LocationFilter` : refus d'inventer sur un silence > 300 s (`:138-141`), blocage du pont après un saut
  refusé (`:178-181`), remise à zéro de la vitesse à l'arrêt (`:158-159`, +177 m mesurés sans elle).
- `Trip` sauvé **avant** le géocodage (`TripRecorder.swift:199` puis `:205-210`).
- `ActiveTripState` réécrit par fix accepté, pas par lot (`TripRecorder.swift:255-257`).
- `discardActiveState()` au `start()` (`:111`) : un état abandonné ne contamine pas le trajet suivant.
- Un seul `ModelContext` — `container.mainContext` — et le commentaire qui explique pourquoi
  (`AppDependencies.swift:74-80`).
- `MileageRounding.money` arrondi une seule fois en fin de calcul (`MileageRule.swift:84-89`) ;
  `DeclarativeMileageRule.cumulative` garantit que la somme des trajets d'une année égale le chiffre de
  l'année (`:70-93`).
- Un pack de règles illisible ne fait pas tomber les onze autres pays (`RulePackStore.swift:80-88`).
- La bascule iCloud est désactivée et affichée à off quand le build n'est pas habilité
  (`SettingsView.swift:181-187`) — l'intention est exactement la bonne, il ne manque que le câblage (**C2**).

---

## 9. Ordre de traitement suggéré

1. **D1 + D2** — sans quoi l'app ne mesure rien dans le parcours nominal.
2. **M3** — une migration ratée doit crier, jamais ouvrir un store en mémoire.
3. **R3** — stocker l'unité sur le `Trip` et s'en servir partout en aval.
4. **R4** puis **R2** — chiffres faux présentés comme officiels.
5. **W4** + **N2** — la Live Activity et le rappel après reprise de crash.
6. **C2** puis **C3/C4** — à régler **avant** d'activer `CLOUDKIT_AVAILABLE`.
7. **R1**, **D3**, **D4**, **D7**, **D5**, **W2**, **W3**, **N3/N4**.
