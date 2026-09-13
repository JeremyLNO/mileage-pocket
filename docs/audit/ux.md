# Audit UX / interface — Mileage Pocket

Périmètre : `Features/`, `Core/DesignSystem/`, `App/RootView.swift`, `App/MainTabView.swift`,
`Resources/Localizable.xcstrings`. Lecture seule, aucun build, aucun simulateur.
Promesse mesurée : **Start. Drive. Stop. Export.**

Chaque constat porte `chemin:ligne`, ce que l'utilisateur voit, ce qu'il devrait voir, et un
statut **CONFIRMÉ** (lu dans le code, comportement déductible sans ambiguïté) ou
**SOUPÇONNÉ** (demande une exécution pour trancher).

---

## 1. Le parcours quotidien

### Le compte de gestes est bon

`App/RootView.swift:12-20` — trois états seulement (onboarding / trajet actif / onglets).
`Features/Home/HomeView.swift:82-102` — le dial START occupe 220 pt au centre.
`Features/ActiveTrip/TripSummarySheet.swift:183` — `prepare()` pré-sélectionne
`settings.defaultTripType`, donc la qualification est déjà faite.

Parcours minimal réel : **ouvrir → START → STOP → Enregistrer = 3 taps.**
C'est conforme, et `UITests/TripFlowUITests.swift:68-90` le verrouille à 4.

Rien à corriger sur le nombre de gestes. Les problèmes sont **entre** les gestes.

---

### 1.1 CONFIRMÉ — Après STOP, rien ne bouge pendant deux géocodages réseau

`Features/ActiveTrip/ActiveTripView.swift:104-118` → `AppDependencies.stopTrip()`
(`App/AppDependencies.swift:190-206`) → `TripRecorder.stop()`
(`Services/Location/TripRecorder.swift:167-215`).

La chaîne est :

```
stopTrip()  →  Task { await recorder.stop() }        // AppDependencies.swift:195-205
recorder.stop()  →  context.save()                   // TripRecorder.swift:199
                 →  await geocoder.address(start)    // TripRecorder.swift:206
                 →  await geocoder.address(end)      // TripRecorder.swift:209
                 →  return trip
puis seulement   →  finishedTrip = trip              // AppDependencies.swift:204
et le defer      →  syncRecorderState()              // AppDependencies.swift:199
```

`Services/Location/GeocodingService.swift:19-25` n'a **aucun timeout** : `CLGeocoder`
répond quand il répond (hors réseau, en tunnel, en parking souterrain : plusieurs
secondes, jusqu'au timeout système).

Ce que l'utilisateur voit : il appuie sur STOP. Le chronomètre continue de tourner
(`ActiveTripView.swift:23,39` — un `Timer` local indépendant du recorder), la distance
reste affichée, le bouton rouge STOP est toujours là, actif, et **rien n'indique que
quelque chose est en cours**. Il rappuie. Le second appel jette `.notRecording`
(`TripRecorder.swift:168`, `tripID` déjà remis à nil par `reset()` ligne 201), le `guard`
sort, le `defer` bascule `isRecording = false`, l'écran de trajet disparaît — puis, une
fois le géocodage terminé, la feuille de résumé apparaît par-dessus les onglets.

Ce qu'il devrait voir : l'état du bouton change **immédiatement** au tap (libellé
« Enregistrement… », bouton désactivé, indicateur), et le géocodage ne bloque pas
l'affichage du résumé — il est déjà « best-effort » (`TripRecorder.swift:212 try?`) et la
course est sauvegardée ligne 199, donc il peut être déplacé après l'ouverture de la feuille,
les adresses se remplissant ensuite.

Gravité : **HAUTE**. C'est le seul geste du parcours quotidien qui n'a pas d'accusé de
réception, et c'est celui sur lequel l'utilisateur est le plus impatient.

---

### 1.2 CONFIRMÉ — START fonctionne visuellement même sans permission de localisation

`Services/Location/TripRecorder.swift:106-131` — `start(vehicleID:)` ne consulte **jamais**
`authorizationStatus`. Le seul `throw` possible est `.alreadyRecording` (ligne 107).

`App/AppDependencies.swift:170-172` demande la permission si `.notDetermined`, puis appelle
`recorder.start()` **dans la foulée**, sans attendre la réponse de l'utilisateur.

Le commentaire `App/AppDependencies.swift:183-186` dit :

> « Starting can only fail for want of location permission; the view already shows the
> permission state, so there is nothing useful to raise here. »

Les deux affirmations sont fausses. `start()` ne peut pas échouer pour cette raison, et
**aucune vue de l'app ne lit `authorizationStatus`** :

```
$ grep -rn "authorizationStatus" Features/ App/ Core/
App/AppDependencies.swift:170
```

Une seule occurrence, dans le modèle, jamais dans l'UI.

Ce que l'utilisateur voit, permission refusée (ou « Don't Allow » sur le prompt qui vient
de s'afficher par-dessus l'écran de trajet) : `ActiveTripView` s'ouvre,
`ActiveTripView.swift:14-20` centre la carte sur **Paris** (le fallback codé en dur), le
chronomètre monte, la distance reste à `0,00 km` pour toujours, la Live Activity démarre
(`AppDependencies.swift:176-180`), la notification « trajet toujours en cours » est
programmée (ligne 181). Au bout de 40 minutes de route il appuie sur STOP et enregistre un
trajet de 0 km.

Ce qu'il devrait voir : un écran qui dit que la localisation est refusée, avec un bouton
vers Réglages iOS — soit avant de démarrer, soit en bandeau permanent sur l'écran de trajet.

Le commentaire de `TripRecorder.swift:55-60` nomme exactement ce risque :
« a trip that records nothing because nobody ever asked is the worst possible outcome — it
looks like it is working ». Le garde-fou a été pensé, il n'a jamais été câblé à une vue.

Gravité : **CRITIQUE**. Défaut silencieux : le résultat est faux et rien ne lève.

---

### 1.3 CONFIRMÉ — L'onboarding promet le suivi écran verrouillé, l'app ne le demande jamais

`Resources/Localizable.xcstrings` → `onboarding.location.subtitle` (EN) :
« Location access lets the app calculate your mileage **even when your iPhone is locked**. »

`Features/Onboarding/OnboardingFlow.swift:191-194` appelle `requestLocationPermission()`
→ `CoreLocationProvider.requestAlways()` (`Services/Location/CoreLocationProvider.swift:52-63`)
qui, depuis `.notDetermined`, affiche le prompt **When In Use** (ligne 57, à raison).

Il n'existe ensuite **aucun chemin** qui appelle `requestAlways()` une seconde fois depuis
`.authorizedWhenInUse` : la seule autre invocation est `AppDependencies.swift:170`, gardée
par `== .notDetermined`.

Conséquence : `CoreLocationProvider.swift:71-73` ne met
`allowsBackgroundLocationUpdates = true` que si le statut est `.authorizedAlways` — statut
que l'utilisateur ne peut atteindre qu'en allant lui-même dans les Réglages iOS. En
« Pendant l'utilisation », verrouiller l'iPhone (ce que fait tout conducteur) suspend les
mises à jour : la distance gèle, l'app ne le dit pas.

Ce qu'il devrait se passer : réappeler `requestAlways()` au premier START en
`.authorizedWhenInUse` (iOS affiche alors l'escalade vers « Toujours »), ou retirer la
promesse du texte.

Gravité : **HAUTE**.

---

### 1.4 CONFIRMÉ — La fin de la période gratuite est invisible là où on appuie

`Core/Access/AccessPolicy.swift:5,28-34` : 3 jours, après quoi `canAccess(.startTrip)`
devient faux. `Features/Home/HomeView.swift:156-162` : au 4ᵉ jour, appuyer sur START
n'ouvre pas un trajet — ça ouvre le paywall, assis dans la voiture, moteur tournant.

Le décompte n'est affiché que dans Réglages > Abonnement
(`App/AppDependencies+Data.swift:303-311`, `settings.plan.freedays`). L'écran Home n'en dit
rien.

Or `Core/DesignSystem/Components.swift:99-100` : `DialButton` **a** un paramètre
`subtitle`, et `Features/Home/HomeView.swift:84` le passe explicitement à `nil`. La place
existe, sous le mot START, et elle est laissée vide.

Ce qu'il devrait voir : « 2 jours d'accès gratuit » sous START à partir du moment où
l'échéance approche.

Gravité : **MOYENNE**.

---

### 1.5 CONFIRMÉ — Le widget « Start Trip » ne fait rien quand l'accès est expiré

`App/MileagePocketApp.swift:22-28` :

```swift
guard url.host == "start" || url.path == "/start" else { return }
if dependencies.canAccess(.startTrip), !dependencies.isRecording {
    dependencies.startTrip()
}
```

Pas de `else`. Ce que l'utilisateur voit : il tape le widget, l'app s'ouvre sur Home, aucun
trajet ne démarre, aucun paywall. Le widget est mort sans le dire.
Ce qu'il devrait voir : le paywall, comme quand il appuie sur START dans l'app.

Cas limite additionnel : si l'onboarding n'est pas terminé, `RootView.swift:13` affiche
`OnboardingFlow` en priorité — un trajet démarré par le widget tournerait **derrière**
l'onboarding, invisible.

Gravité : **MOYENNE**.

---

## 2. Impasses, boutons sans effet, feuilles sans sortie

### 2.1 CONFIRMÉ — « Discard » occupe la place de « Annuler » et supprime sans confirmation

`Features/ActiveTrip/TripSummarySheet.swift:49-53` :

```swift
ToolbarItem(placement: .cancellationAction) {
    Button("common.discard", role: .destructive) { discard() }
}
```

`placement: .cancellationAction` = coin haut-gauche, l'emplacement d'« Annuler » dans tout
iOS. `discard()` (lignes 208-213) fait `context.delete(trip)` + `save()`. Irréversible, un
seul tap, **aucune confirmation**. La feuille est par ailleurs
`.interactiveDismissDisabled()` (ligne 55), donc c'est le seul bouton d'échappement visible.

Ce que l'utilisateur voit : il vient de rouler 45 minutes, il cherche à fermer la feuille
« pour y revenir plus tard », il tape en haut à gauche : le trajet n'existe plus.

Calibrage incohérent dans la même app :
- `Features/TripDetail/TripDetailView.swift:48-53` — « Recalculer » (**réversible**) a une
  `confirmationDialog`.
- `Features/Settings/SettingsView.swift:38-43` — « Tout supprimer » a une `confirmationDialog`.
- Ici, la destruction du trajet qu'on vient d'enregistrer : rien.

Ce qu'il devrait voir : soit une confirmation, soit un vrai « Fermer » non destructif qui
garde le trajet en brouillon, avec « Supprimer » ailleurs.

Gravité : **CRITIQUE** (perte de données sur un geste réflexe).

---

### 2.2 CONFIRMÉ — Supprimer un trajet, sans confirmation non plus

`Features/TripDetail/TripDetailView.swift:142-149` : `Button(role: .destructive)` →
`dependencies.delete(trip)` → `dismiss()`. Pas de dialogue. Même incohérence qu'en 2.1 :
l'action réversible juste au-dessus (ligne 137) en a un, celle-ci non.

Gravité : **HAUTE**.

---

### 2.3 CONFIRMÉ — Modifier la distance : saisie invalide = bouton sans effet

`Features/TripDetail/TripDetailView.swift:183-186` :

```swift
guard let value = Double(editedDistance.replacingOccurrences(of: ",", with: ".")), value > 0
else { return }
```

Ce que l'utilisateur voit : il tape `12 km` ou `12.5.0` ou vide le champ, appuie sur
« Enregistrer », l'alerte se ferme, la distance n'a pas changé, aucun message.
Ce qu'il devrait voir : soit « Enregistrer » désactivé tant que la valeur est invalide (ce
que fait déjà `ManualTripView.swift:78`), soit un message.

Gravité : **MOYENNE**. Incohérence interne : le même problème est correctement traité dans
la saisie manuelle et pas ici.

---

### 2.4 CONFIRMÉ — Export : état de chargement inerte + échec muet

`Features/Reports/ReportsView.swift:130-140` :

```swift
isExporting = true
defer { isExporting = false }
if let url = dependencies.export(data, format: format) { exportURL = ExportedFile(url: url) }
```

Tout est **synchrone** : `isExporting` repasse à `false` avant que SwiftUI ne redessine.
Le `isEnabled: !isExporting` de la ligne 117 ne peut jamais se voir. C'est un état de
chargement qui n'existe pas.

Et `App/AppDependencies+Data.swift:215-228` retourne `nil` en cas d'échec
(`try? CSVExporter.write`, `try? PDFReportRenderer().render`). Dans ce cas `ReportsView` ne
fait **rien** : pas de feuille de partage, pas d'alerte.

Ce que l'utilisateur voit : « GÉNÉRER LE RAPPORT » — rien. Il rappuie. Rien.
Ce qu'il devrait voir : soit le rapport, soit une erreur.

Le même défaut existe dans `Features/Settings/SettingsView.swift:187-189` :
`if let url = dependencies.exportAllData() { … }`, sans `else`.

C'est le **E** de « Start. Drive. Stop. Export. » qui peut échouer sans un mot.

Gravité : **HAUTE**.

---

### 2.5 CONFIRMÉ — « Restaurer les achats » sans aucun retour dans Réglages

`Features/Settings/SettingsView.swift:208` :

```swift
Button("paywall.restore") { Task { try? await dependencies.subscriptions.restore() } }
```

`try?` avale l'erreur, aucune alerte, aucun changement visible si rien n'est à restaurer.
Le même bouton dans le paywall (`Features/Paywall/PaywallView.swift:272-279`) gère
l'erreur **et** ferme l'écran en cas de succès. Deux comportements pour un même libellé.

Gravité : **MOYENNE**.

---

### 2.6 CONFIRMÉ — Le « + » véhicule crée un véhicule fantôme si on ferme la feuille

`App/AppDependencies+Data.swift:59-64` : `makeVehicle()` fait `context.insert(vehicle)`
**avant** que la feuille ne s'affiche, avec `name: ""`.
`Features/Vehicles/VehiclesView.swift:39-51` : `editing = dependencies.makeVehicle()`.
`Features/Vehicles/VehiclesView.swift:132-137` : la barre d'outils de `VehicleEditor` n'a
**que** `common.done` (`.confirmationAction`), désactivé tant que le nom est vide. **Pas de
bouton Annuler.** La feuille n'est pas `interactiveDismissDisabled`, donc on la ferme d'un
glissement vers le bas.

Ce que l'utilisateur voit : il tape « + », change d'avis, glisse la feuille vers le bas.
La liste contient maintenant une ligne sans nom, avec « Car » en sous-titre
(`VehiclesView.swift:68-73`). Le `@Query` ligne 8 la remonte immédiatement, et l'autosave
du `mainContext` la persiste.
Ce qu'il devrait voir : un bouton « Annuler » qui supprime le véhicule non validé, et pas
d'insertion avant validation.

Gravité : **HAUTE**.

---

### 2.7 CONFIRMÉ — Deux feuilles sans bouton de fermeture, dont une en cul-de-sac

- `Features/Settings/SettingsView.swift:222-255` — `CountryPickerSheet` : liste + recherche,
  aucune barre d'outils. On ne sort qu'en choisissant un pays ou en glissant vers le bas.
- `Features/Vehicles/VehiclesView.swift:153-182` — `VehiclePickerSheet` : idem, **et** si
  `vehicles.isEmpty` (lignes 176-180) elle affiche « Aucun véhicule / Ajoutez la voiture que
  vous conduisez pour le travail » **sans aucun moyen d'en ajouter une depuis cette
  feuille**. L'état vide donne une consigne et ne fournit pas le bouton.

Le paywall, lui, fait les choses correctement (`PaywallView.swift:50-53, 250-257` — la
croix qui avait été inerte a été réparée via `onClose`). Ces deux feuilles-ci n'ont jamais
eu de croix du tout.

Gravité : **MOYENNE** pour le cul-de-sac véhicule, **BASSE** pour le pays.

---

### 2.8 SOUPÇONNÉ — Supprimer le trajet pendant que la feuille le lit

`TripSummarySheet.discard()` (lignes 208-213) fait `context.delete(trip)` **avant**
`clearFinishedTrip()`. Entre les deux, SwiftUI peut redessiner le corps de la feuille, qui
lit `trip.distanceMeters`, `trip.calculatedAmount`, `trip.startAddress`
(lignes 62, 66, 72) sur un objet supprimé. SwiftData renvoie en général des valeurs par
défaut plutôt que de crasher, mais l'ordre correct est d'annuler la présentation d'abord.
À trancher à l'exécution.

Gravité : **BASSE** (à vérifier).

---

## 3. États vides et erreurs

### 3.1 CONFIRMÉ — La liste filtrée / recherchée affiche l'état « aucun trajet »

`Features/Trips/TripsView.swift:16-25` construit `filtered` (filtre type + recherche
texte), puis ligne 30 :

```swift
if filtered.isEmpty { EmptyStateView(title: "trips.empty.title", message: "trips.empty.message") }
```

Textes (EN) : « No trips to show » / « Trips you record appear here, newest first. You can
also add one by hand. »

Ce que l'utilisateur voit : il a 200 trajets, il tape « zzz » dans la recherche, et l'app lui
explique comment enregistrer son premier trajet.
Ce qu'il devrait voir : « Aucun résultat pour “zzz” » avec un moyen d'effacer la recherche,
distinct de l'état « aucun trajet du tout ».

Gravité : **MOYENNE**.

---

### 3.2 CONFIRMÉ — Sans réseau, les trajets s'affichent « — → — » sans explication

`Features/Home/HomeView.swift:113`, `Features/Trips/TripsView.swift:94`,
`Features/ActiveTrip/TripSummarySheet.swift:72` — tous les trois :

```swift
Text("\(trip.startAddress ?? "—") → \(trip.endAddress ?? "—")")
```

`GeocodingService.swift:19-25` retourne `nil` silencieusement en cas d'échec (hors réseau,
en tunnel, quota `CLGeocoder` atteint). Le titre du trajet devient littéralement « — → — ».

Le même affichage survient pour un trajet manuel où « De » et « À » sont laissés vides —
`ManualTripView.swift:76-79` ne rend obligatoire que la distance.

Ce qu'il devrait voir : un repli utile (heure + véhicule, ou « Trajet du 13 sept., 14 h 20 »)
plutôt qu'une paire de tirets.

Gravité : **MOYENNE**.

---

### 3.3 CONFIRMÉ — Aucun état « permission refusée » nulle part

Voir 1.2. Zéro vue ne consulte `authorizationStatus`. C'est le trou le plus grave de cette
section : la seule permission dont dépend le produit n'a pas d'état d'erreur dans l'UI.

Gravité : **CRITIQUE**.

---

### 3.4 CONFIRMÉ — Le rapport vide reste générable

`Features/Reports/ReportsView.swift:115-128` — quand `data.isEmpty`, la phrase
`reports.empty.hint` (« No business trips in this period yet. The report will be empty. »)
s'affiche **sous** les deux boutons, qui restent actifs. L'utilisateur produit un PDF vide,
le partage, et découvre après coup.
Ce qu'il devrait voir : les boutons désactivés, et l'explication au-dessus d'eux, pas en
dessous.

Gravité : **BASSE**.

---

### 3.5 Bien fait — à conserver

- `Features/Paywall/PaywallView.swift:116-148` : trois états distincts (chargement, échec
  avec message + « Réessayer », plans), et une sortie garantie dans tous les cas
  (`onClose`/`dismiss`, lignes 250-257). C'est le seul écran de l'app qui traite
  correctement chargement, erreur et sortie.
- `Features/Home/HomeView.swift:134-142` : l'état vide de Home dit quoi faire
  (« Press START when you set off »), pas ce qui manque.
- `Features/Settings/SettingsView.swift:180-197` : l'interrupteur iCloud est désactivé et
  éteint quand `CLOUDKIT_AVAILABLE = NO` (`Config/Base.xcconfig:23`), avec une note en pied
  de section. Le paywall retire la ligne iCloud en conséquence
  (`PaywallView.swift:102-114`). Cohérent, honnête.

---

## 4. Les textes

Le catalogue est **complet** : 202 clés, 6 langues (en/fr/es/de/it/pt), **aucune clé
manquante dans aucune langue**, aucun `state` en attente de relecture.

### 4.1 CONFIRMÉ — Aucune clé construite par interpolation : le piège n'a pas été refait

Vérifié en balayant tout `Features/ App/ Core/ MileageWidgets/` :

- `LocalizedStringKey("…\(…)")` : **0 occurrence** (seules deux occurrences de
  `LocalizedStringKey(_:)` avec une `String` déjà complète —
  `Features/Trips/TripsView.swift:40` (clés `trips.section.*`, présentes au catalogue) et
  `Features/Paywall/PaywallView.swift:90` (clés `paywall.feature.*`, présentes)).
- `String.LocalizationValue("…\(…)")` : **0 occurrence**.
- `String(localized: "…\(…)")` : **0 occurrence**.

Les clés dynamiques passent par `L.string(_:)`
(`Core/Localization/LocalizationService.swift:54-56`), qui interpole dans une **`String`
Swift** puis appelle `NSLocalizedString` — la composition se fait avant la recherche, donc
la recherche aboutit. Correct, et documenté lignes 42-53.

Les 12 clés que le catalogue possède sans littéral correspondant en source sont exactement
celles-là, plus une vraie orpheline :

```
purpose.clientVisit / delivery / meeting / other / siteVisit     → L.string("purpose.\(raw)")       TripSummarySheet.swift:136,138
vehicle.type.bicycle / car / electricCar / moped / motorcycle / van
                                                                  → L.string("vehicle.type.\(raw)") VehiclesView.swift:69,103
                                                                                                     OnboardingFlow.swift:128
widget.month.total                                                → ORPHELINE
```

### 4.2 CONFIRMÉ — Deux clés traduites en 6 langues et jamais affichées

- `widget.month.total` (« This month ») : `MileageWidgets/StartTripWidget.swift:58` affiche
  `snapshot.monthLabel` (une date formatée) à la place.
- `notification.trip.saved.title` / `.body` : `NotificationService.notifyTripSaved`
  (`Services/Notifications/NotificationService.swift:46-52`) n'est **appelée nulle part**.

Gravité : **BASSE** (pas de défaut visible, mais du poids mort traduit 6 fois).

---

### 4.3 CONFIRMÉ — `activetrip.paused` dit « Stopped » sur un trajet en cours

`Features/ActiveTrip/ActiveTripView.swift:94-98` affiche `activetrip.paused` sous le
compteur quand `dependencies.isTripPaused`. Cet état survient après **120 s** à l'arrêt
(`Services/Location/LocationFilter.swift:17` `stopDuration = 120`).

| langue | valeur |
|---|---|
| **en** | **Stopped** |
| fr | À l'arrêt |

Ce que l'utilisateur voit (EN) : bouchon, 2 minutes sans bouger. L'écran affiche
« **Stopped** », et 400 pt plus bas un gros bouton rouge « **STOP** ». Il conclut que le
trajet s'est arrêté tout seul.
Ce qu'il devrait voir : « Paused » / « Stationary » / « Waiting ». Le français est juste ;
c'est l'anglais — la langue source — qui est faux.

Gravité : **MOYENNE**.

---

### 4.4 CONFIRMÉ — `summary.title` annonce « Trip saved » avant que le trajet soit enregistré

`Features/ActiveTrip/TripSummarySheet.swift:47` : `navigationTitle("summary.title")`
= « Trip saved » / « Trajet enregistré ». Or la feuille comporte un bouton
« Enregistrer » (ligne 43) et un bouton « Abandonner » (ligne 51) : rien n'est acquis.

Le titre affirme un résultat qui n'a pas eu lieu, et rend « Abandonner » incompréhensible
(abandonner quelque chose de déjà enregistré ?).
Ce qu'il devrait voir : « Ce trajet » / « Trajet terminé » / « Qualifier le trajet ».

Gravité : **MOYENNE**.

---

### 4.5 CONFIRMÉ — La paire START/STOP est traduite à moitié

| langue | `home.start` | `activetrip.stop` |
|---|---|---|
| en | START | STOP |
| fr | START | STOP |
| de | START | STOP |
| **es** | **INICIAR** | **STOP** |
| **it** | **AVVIA** | **STOP** |
| **pt** | **INICIAR** | **STOP** |

Soit les deux mots restent en anglais (choix de marque, défendable — c'est ce que font
fr/de), soit les deux sont traduits. Trois langues sur six montrent une moitié traduite et
l'autre non, sur la paire de contrôles la plus visible du produit.

Gravité : **MOYENNE**.

---

### 4.6 CONFIRMÉ — Deux formulations pour le même état vide

| clé | en | fr |
|---|---|---|
| `home.empty.title` | No trips yet | Aucun trajet |
| `trips.empty.title` | No trips to show | Aucun trajet à afficher |

Même situation (base vide), deux phrases. « to show / à afficher » décrit en plus le
système (« ce que je peux afficher ») plutôt que l'utilisateur.

Autres formulations orientées système :
- `settings.plan.free` = « No subscription » — décrit l'absence d'un objet technique. « Accès
  gratuit terminé » dirait ce qui concerne l'utilisateur.
- `settings.icloud.unavailable` = « iCloud sync is not available **in this build** » —
  « in this build » est un mot de développeur, jamais d'utilisateur.
- `reports.empty.hint` = « The report **will be** empty » — annonce un état système au lieu
  de proposer une action (changer de période).

Incohérence de casse sur deux actions voisines :
`reports.generate` = « GENERATE REPORT » (capitales) vs `reports.csv` = « Export as CSV ».
Les capitales sont par ailleurs réservées à START/STOP dans tout le reste de l'app.

Gravité : **BASSE**.

---

### 4.7 CONFIRMÉ — La langue choisie dans Réglages ne s'applique qu'à la moitié des textes

`App/RootView.swift:23` pousse `dependencies.localization.locale` dans
`\.locale`. Les `Text("clé")` suivent bien cette locale.

Mais `Core/Localization/LocalizationService.swift:54-66` (`L.string` / `L.format` /
`L.plural`) appelle `NSLocalizedString`, et `String(localized:)` sans argument `locale:`
fait de même : les deux résolvent contre **`Bundle.main.preferredLocalizations`**, c'est-à-dire
la langue du **système**, en ignorant totalement `\.locale`.

`Features/Settings/SettingsView.swift:114-121` permet de choisir une langue différente de
celle du téléphone. Dès que c'est fait, l'écran d'accueil mélange deux langues :

| `Features/Home/HomeView.swift` | mécanisme | langue |
|---|---|---|
| :57 `Text(model.monthTitle)` | `.formatted` + locale système | système |
| :66 `L.format("home.estimated", …)` | `NSLocalizedString` | **système** |
| :72 `L.plural("home.business.trips", …)` | `NSLocalizedString` | **système** |
| :112 `Text("home.last.trip")` | `LocalizedStringKey` | **choisie** |
| :153 `String(localized: "home.no.vehicle")` | bundle | **système** |

Même mélange ailleurs : `TripSummarySheet.swift:118,136,138` (bannière de suggestion et
puces d'objet), `TripDetailView.swift:123` (`rate.official`/`rate.custom`),
`VehiclesView.swift:69,103` et `OnboardingFlow.swift:128` (types de véhicule),
`PaywallView.swift:157,231,233` (« Save 20% » et le pied de tarif),
`SettingsView.swift:82`, et surtout **`AppDependencies+Data.swift:246-263`
(`reportProfile`) — donc le PDF exporté** est étiqueté dans la langue système, pas dans
celle que l'utilisateur a choisie.

Correctif : passer la locale explicitement (`String(localized:locale:)`, ou un `Bundle`
résolu depuis `localization.currentLanguage`) dans les helpers `L`.

Gravité : **HAUTE** (visible dès la première utilisation du sélecteur de langue, et
contamine le livrable exporté).

---

### 4.8 CONFIRMÉ — Le texte de permission de localisation n'est traduit dans aucune langue

`App/Info.plist` porte `NSLocationWhenInUseUsageDescription` et
`NSLocationAlwaysAndWhenInUseUsageDescription` en **anglais uniquement**. Il n'existe
aucun `InfoPlist.xcstrings` ni aucun `.lproj` dans le dépôt :

```
$ find . -name "InfoPlist*" -not -path "./build/*"     → (rien)
$ find . -name "*.lproj"    -not -path "./build/*"     → (rien)
```

Ce que l'utilisateur français voit à l'étape 4 de l'onboarding : une page entièrement en
français, puis une alerte système en anglais lui demandant l'accès à sa position. C'est le
moment où il décide d'autoriser ou non le suivi — le texte le plus consé­quent du produit,
et le seul qui n'est pas traduit.

Gravité : **HAUTE**.

---

### 4.9 CONFIRMÉ — « Suivre la langue du système » est écrit mais pas branché

`Core/Localization/LocalizationService.swift:31-39` définit `useSystemLanguage()`.
Aucun appel dans tout le dépôt (ni app, ni tests). `AppLanguage`
(`Core/Localization/AppLanguage.swift:5-11`) n'a pas de cas « système », et le `Picker`
(`SettingsView.swift:114-121`) liste les 6 langues sans option de retour.

Ce que l'utilisateur voit : une fois qu'il a touché le sélecteur, il ne peut plus revenir à
« comme mon iPhone ». Et comme `setLanguage` pose `hasExplicitLanguageOverride = true`
(ligne 26), changer la langue du téléphone n'a plus d'effet sur l'app.

Gravité : **BASSE**.

---

## 5. Accessibilité

Le plan (`docs/superpowers/plans/2026-09-12-mileage-pocket-v1.md:460`, Task 18 / Step 3)
exigeait : « Dynamic Type jusqu'à AX5 sans troncature sur Home/ActiveTrip/Trips, labels
VoiceOver sur START/STOP/BUSINESS/PERSONAL, `Reduce Motion` respecté, cibles ≥ 44 pt.
Vérifier au simulateur en AX5. »

Le journal (`.superpowers/sdd/2026-09-12-mileage-pocket-v1/progress.md`) indique
« Tasks 11-18 : **écrits** ». La vérification au simulateur n'a jamais eu lieu, et cela se
voit dans le code.

### 5.1 CONFIRMÉ — Dynamic Type n'a quasiment aucun effet sur le contenu de l'app

```
$ grep -rc "\.system(size:" Features/ Core/ App/   → 64 occurrences
$ grep -rn "relativeTo"      Features/ Core/ App/   → 0
$ grep -rn "ScaledMetric"    Features/ Core/ App/   → 0
$ grep -rn "dynamicTypeSize" Features/ Core/ App/   → 0
```

`Font.system(size:)` est une taille **fixe** : elle ne suit pas Dynamic Type. Les variantes
qui le font (`.system(size:relativeTo:)`, `@ScaledMetric`, les styles `.body`/`.headline`…)
ne sont utilisées **nulle part**, y compris dans le design system lui-même
(`Core/DesignSystem/Typography.swift:11-20`, `Components.swift:36,42,68,82,92,131,135,170,
176,193,196,199`).

Ce que l'utilisateur voit en AX5 : rien ne casse par troncature — **rien ne grossit**. La
liste des trajets reste à 16/13 pt (`TripsView.swift:95,109,114`), le détail du trajet à
14/15 pt (`TripDetailView.swift:156,160`), l'onboarding à 27/16 pt
(`OnboardingFlow.swift:232,237`). Une personne malvoyante qui a réglé son iPhone en AX5 lit
son carnet de bord en corps 13.

Pire : ce qui **suit** Dynamic Type est le chrome système (titres de navigation, en-têtes de
`Section`, libellés de `Form`, `Picker`, barre d'onglets, alertes). D'où des lignes
schizophrènes en AX5 :

- `Features/Settings/SettingsView.swift:157-161` — `LabeledContent("settings.active.rule")`
  dont le **libellé** grossit et dont la **valeur** est figée à 13 pt.
- Idem lignes 152, 160, 164, 166.
- `Features/Trips/TripsView.swift:38-48` — en-têtes de section énormes au-dessus de lignes
  restées minuscules.

Correctif : `.system(size: X, relativeTo: .body)` partout dans le design system, `MeterReadout`
et `DialButton` compris (leurs `minimumScaleFactor` gèrent déjà le débordement).

Gravité : **HAUTE**.

### 5.2 SOUPÇONNÉ — Troncature dans le sélecteur de période

`Features/Reports/ReportsView.swift:79-84` — `Picker` segmenté à **4** segments. Le contrôle
segmenté, lui, suit Dynamic Type. « Trimestre » (9 caractères, fr/es/it/pt) sur ~87 pt de
large : correct à la taille par défaut, tronqué aux grandes tailles. À confirmer au
simulateur.

Gravité : **BASSE** (à vérifier).

### 5.3 CONFIRMÉ — Les quatre contrôles principaux ont leurs libellés VoiceOver

| contrôle | ligne | label |
|---|---|---|
| START | `Features/Home/HomeView.swift:87` | `home.start.accessibility` = « Start trip » |
| STOP | `Features/ActiveTrip/ActiveTripView.swift:117` | `activetrip.stop.accessibility` = « Stop trip » |
| BUSINESS | `TripSummarySheet.swift:93` | via le `Text` du label + `.isSelected` (ligne 104) |
| PERSONAL | `TripSummarySheet.swift:93` | idem |

C'est conforme. **C'est le seul point de l'accessibilité qui a été fait.**

### 5.4 CONFIRMÉ — Deux contrôles sans libellé VoiceOver, dont un juste à côté d'un qui en a un

`Features/Trips/TripsView.swift:56-78` — dans la **même** barre d'outils :

```swift
// gauche : filtre — AUCUN accessibilityLabel
Image(systemName: filter == nil ? "line.3.horizontal.decrease.circle" : "…fill")
// droite : ajout manuel — label présent
Image(systemName: "plus")
.accessibilityLabel(Text("trips.add.manual"))
```

VoiceOver annonce le filtre par le nom du symbole SF. Et ligne 64, l'**état** du filtre
(actif / inactif) n'est porté que par la variante `.fill` du glyphe — invisible à VoiceOver,
et très faible visuellement.

`Features/Home/HomeView.swift:89-99` — le sélecteur de véhicule est un `Button` dont le label
est « icône + nom du véhicule + chevron ». VoiceOver lit le nom de la voiture ; rien ne dit
que c'est un contrôle qui change de véhicule.

Gravité : **MOYENNE**.

### 5.5 CONFIRMÉ — Reduce Motion n'est respecté nulle part (sauf dans du code mort)

La seule lecture de `accessibilityReduceMotion` du dépôt est
`Core/DesignSystem/Components.swift:106`, utilisée ligne 121 pour l'animation de l'anneau
de progression du `DialButton`. Or ce `progress` est **toujours `nil`** :
`Features/Home/HomeView.swift:84` appelle `DialButton(title:subtitle:)` sans lui. Le seul
garde-fou Reduce Motion de l'app protège une animation qui ne se produit jamais.

Les animations réelles ne le consultent pas :
- `App/RootView.swift:30` — `.animation(.snappy(duration: 0.25), value: isRecording)`, la
  transition plein écran vers l'écran de trajet.
- `Features/Onboarding/OnboardingFlow.swift:37` — la pagination de l'onboarding.
- `Features/ActiveTrip/TripSummarySheet.swift:89` — `withAnimation(.snappy)` sur la
  sélection Business/Personal.
- `Core/DesignSystem/Components.swift:40` — `.contentTransition(.numericText())` sur le
  compteur, qui s'anime à chaque mise à jour de distance pendant tout le trajet.

Gravité : **MOYENNE**.

### 5.6 CONFIRMÉ — Cibles tactiles sous 44 pt

| élément | ligne | hauteur estimée |
|---|---|---|
| sélecteur de véhicule sur Home | `HomeView.swift:89-99` | ~20 pt (texte 15 pt, aucun `frame`) |
| « Skip for now » (véhicule) | `OnboardingFlow.swift:171-173` | ~20 pt |
| « Skip for now » (notifications) | `OnboardingFlow.swift:214-216` | ~20 pt |
| « Terms » / « Privacy » | `PaywallView.swift:236-243` | **~15 pt** (texte 12 pt) |
| puces d'objet | `TripSummarySheet.swift:135-145` | ~33 pt (8 pt de padding vertical) |
| puces de client | `TripSummarySheet.swift:166-172` | ~33 pt |

Les boutons principaux sont corrects (`PrimaryButton` 54 pt, `SecondaryButton` 50 pt,
`DialButton` 220 pt, STOP 76 pt). Ce sont les actions secondaires — dont les liens légaux
que l'App Review vérifie — qui sont hors norme.

Gravité : **MOYENNE**.

### 5.7 CONFIRMÉ — L'ambre de la marque ne passe pas le contraste AA sur fond clair

`Core/DesignSystem/Theme.swift:15` — `signal` clair = `#E8730A`.
Luminance relative calculée : 0,2945.

| fond | ratio | AA texte < 18 pt (4,5:1) |
|---|---|---|
| `Theme.background` `#F3F5F8` | **2,79 : 1** | échec |
| `Theme.surface` `#FFFFFF` | **3,05 : 1** | échec |

Usages en **texte** sur fond clair, tous en corps 12-15 pt :

| ligne | texte |
|---|---|
| `Features/Vehicles/VehiclesView.swift:29` | « Par défaut » (12 pt) |
| `Features/TripDetail/TripDetailView.swift:92` | « Distance modifiée » (12 pt) |
| `Features/ActiveTrip/TripSummarySheet.swift:120` | « Utiliser » (12 pt) |
| `Features/Paywall/PaywallView.swift:210` | « Démarrer l'essai gratuit de 3 jours » (15 pt) |

En mode sombre (`signal` = `#FF9A2E` sur `#080D15`) le contraste est bon : le défaut ne
concerne que l'apparence claire — qui est la valeur par défaut de l'app.

Les usages de `signal` en **remplissage** (dial, anneau, bordures de plan, polyligne de
carte) ne sont pas concernés.

Gravité : **MOYENNE**.

### 5.8 Bien fait

`Core/DesignSystem/Components.swift:147-158` — `TripTypePill` porte toujours son libellé
texte à côté de la couleur. Les boutons Business/Personal
(`TripSummarySheet.swift:97-104`) distinguent l'état sélectionné par l'inversion
fond/texte **et** par le trait `.isSelected`, pas par la teinte seule. Les cartes de plan du
paywall (`PaywallView.swift:184-187`) changent d'épaisseur de bordure (2 pt vs 0,5 pt) en
plus de la couleur. Sur ce point, la règle « jamais la couleur seule » est tenue — sauf au
point 5.4 (état du filtre).

---

## 6. Cohérence visuelle

### 6.1 CONFIRMÉ — Le design system est contourné presque partout

`Core/DesignSystem/Typography.swift` expose `meterLarge` (64), `meterMedium` (34),
`meterSmall` (17), `eyebrow` (12). Seuls `meterSmall` (`Components.swift:175`) et `eyebrow`
sont réellement utilisés ; `meterLarge` et `meterMedium` ne le sont **jamais**.

À la place, 64 tailles en dur, dont une large majorité de valeurs uniques :

| écran | tailles en dur |
|---|---|
| `HomeView.swift` | 72 (`MeterReadout size:`), 17, 14, 15, 11 |
| `TripSummarySheet.swift` | 62, 22, 14, 22, 16, 15, 14, 14 |
| `TripDetailView.swift` | 56, 20, 16, 14, 15 |
| `TripsView.swift` | 16, 13 |
| `ReportsView.swift` | 22, 13 |
| `PaywallView.swift` | 42, 30, 16, 24, 15, 12, 13 |
| `OnboardingFlow.swift` | 32, 27, 26, 18, 17, 16, 15, 14, 56 |

Trois tailles distinctes pour le même rôle « chiffre héros » : 72 (Home), 62 (résumé), 56
(détail). Cinq tailles distinctes pour du corps de texte secondaire : 12, 13, 14, 15, 16.
Deux tailles de titre de section : 22 (`ReportsView.swift:97`) et 18
(`Components.swift:196`).

Ce que l'utilisateur voit : des écarts de hiérarchie qui ne veulent rien dire, et — surtout —
une application qui ne peut pas changer d'échelle d'un coup (cf. 5.1).

Gravité : **MOYENNE**.

### 6.2 CONFIRMÉ — Le même « chiffre héros » est présenté de trois façons

- Home (`HomeView.swift:55-80`) : eyebrow (mois) → `MeterReadout` 72 → montant 17 pt →
  nombre de trajets 14 pt. **Aligné à gauche.**
- Résumé (`TripSummarySheet.swift:59-78`) : `MeterReadout` 62 → montant 22 pt → adresses
  14 pt. **Centré**, sans eyebrow.
- Détail (`TripDetailView.swift:76-95`) : `MeterReadout` 56 → montant 20 pt → pilule →
  éventuel « modifié ». **Centré.**
- Rapports (`ReportsView.swift:100-110`) : trois `StatTile` de 17 pt. **Aucun chiffre héros.**

Quatre écrans, quatre grammaires pour « voilà votre distance ».

Gravité : **BASSE**.

### 6.3 CONFIRMÉ — Le `DialButton` documente une fonction qui n'existe pas

`Core/DesignSystem/Components.swift:96-97` :

> « The signature control: a dial, not a pill. A tick ring marks the face; **while a trip
> runs the ring fills with the distance covered**, so the button itself is the instrument. »

L'écran de trajet actif n'utilise **pas** le `DialButton` : `ActiveTripView.swift:104-114`
dessine un rectangle rouge de 76 pt. Le seul appelant du dial est
`HomeView.swift:84`, sans `progress`. L'anneau de progression (lignes 115-122), son
animation et son garde-fou Reduce Motion sont du code mort, et le commentaire décrit une
identité visuelle que le produit n'a pas.

Gravité : **BASSE** (mais c'est la promesse visuelle centrale du design system qui n'est pas
tenue).

### 6.4 CONFIRMÉ — Trois conteneurs différents pour le même rôle

- `Card` (`Components.swift:7-21`) : rayon 22, fond `surface`, bordure `separator` 0,5.
- `Form` / `Section` : chrome système, rayon et fond iOS. Utilisé par `SettingsView`,
  `ManualTripView`, `VehicleEditor`.
- Fonds ad hoc : `TripSummarySheet.swift:152,162` (rayon 14),
  `OnboardingFlow.swift:96` (rayon `Theme.cardRadius` = 22), `:124,134,139,147,152`
  (rayon **16**), `TripSummarySheet.swift:99,123` (rayon **20** et **16**),
  `PaywallView.swift:181,185` (rayon **20**), `ActiveTripView.swift:113` (rayon **24**),
  `TripDetailView.swift:71` (rayon `cardRadius`).

`Theme` ne définit que deux rayons (`cardRadius = 22`, `controlRadius = 16`,
`Theme.swift:36-37`). Les valeurs 14, 20 et 24 sont inventées sur place.

Gravité : **BASSE**.

### 6.5 CONFIRMÉ — La marge horizontale change d'un écran à l'autre

`HomeView.swift:28` → 20 · `TripSummarySheet.swift:39` → 20 ·
`TripDetailView.swift:35` → 20 · `ReportsView.swift:66` → 20 · `PaywallView.swift:46` → 20 ·
`OnboardingFlow.swift:261,266` → **24** · `ActiveTripView.swift:115` → **24**.

Gravité : **BASSE**.

---

## 7. Fonctions qui alourdissent le parcours sans le servir

### 7.1 L'onboarding en 6 écrans avant le premier START

`Features/Onboarding/OnboardingFlow.swift:28-35` : welcome → pays → véhicule →
localisation → notifications → paywall. Deux d'entre eux seulement sont nécessaires au
premier trajet (localisation ; pays, qui fixe barème/devise/unité).

- L'écran véhicule est déjà passable (`onboarding.skip`, ligne 171) — mais il pose 3 à 4
  champs avant qu'on ait vu l'app fonctionner une seule fois. `VehiclesView` permet de le
  faire plus tard, et le calcul retombe sur `defaultVehicle()`
  (`AppDependencies+Data.swift:17-23`) en attendant.
- L'écran notifications sert une fonctionnalité dont une seule notification est vraiment
  utile (le rappel de trajet oublié). Il pourrait être demandé **au premier STOP**, quand
  l'utilité est démontrée, plutôt qu'avant le premier trajet.
- Le paywall en 6ᵉ position, avant tout usage, sur une app vendue 3 jours d'essai : il
  arrive avant que quoi que ce soit ait été prouvé.

Recommandation : **welcome → pays → localisation → START**. Véhicule, notifications et
paywall se rattrapent en contexte.

### 7.2 CONFIRMÉ — Le pays n'est enregistré que si l'on appuie sur « Continuer »

`Features/Onboarding/OnboardingFlow.swift:107-110` : `applyCountry(country)` est dans
l'action du bouton. Le `TabView` est en `.tabViewStyle(.page(…))` (ligne 36), donc le
balayage latéral reste actif et permet de passer l'écran **sans** déclencher
`applyCountry`.

Filet de sécurité : `SettingsStore.fetchOrCreate` (`Core/Persistence/SettingsStore.swift:25-32`)
a déjà posé le pays détecté à la création. Le pays affiché et le pays enregistré coïncident
donc **sauf** si l'utilisateur change la sélection puis balaye au lieu d'appuyer — auquel
cas il a vu son choix et l'app garde l'autre.

Gravité : **BASSE**.

### 7.3 « Dupliquer un trajet » — à interroger

`Features/TripDetail/TripDetailView.swift:138-141` → `duplicate` (`AppDependencies+Data.swift:188-211`).
Crée une copie datée de maintenant, sans tracé. Sur une app dont la promesse est
l'enregistrement automatique, c'est un raccourci de saisie manuelle, déjà couvert par
`ManualTripView`. Il ajoute un bouton dans une pile qui en compte déjà quatre (dont
« Supprimer » sans confirmation, cf. 2.2). À reconsidérer.

---

## Récapitulatif

| # | gravité | statut | emplacement | constat |
|---|---|---|---|---|
| 1.2 / 3.3 | CRITIQUE | confirmé | `TripRecorder.swift:106-131`, `AppDependencies.swift:170-187` | Trajet « enregistré » sans permission : carte de Paris, 0,00 km, aucun message |
| 2.1 | CRITIQUE | confirmé | `TripSummarySheet.swift:49-53` | « Discard » à la place d'« Annuler », supprime le trajet sans confirmation |
| 1.1 | HAUTE | confirmé | `AppDependencies.swift:190-206`, `TripRecorder.swift:205-212` | STOP : deux géocodages sans timeout, aucun retour à l'écran |
| 1.3 | HAUTE | confirmé | `CoreLocationProvider.swift:52-73`, `OnboardingFlow.swift:191` | « Even when your iPhone is locked » jamais demandé ni obtenu |
| 2.2 | HAUTE | confirmé | `TripDetailView.swift:142-149` | Suppression de trajet sans confirmation |
| 2.4 | HAUTE | confirmé | `ReportsView.swift:130-140`, `SettingsView.swift:187` | Export : état de chargement inerte, échec totalement muet |
| 2.6 | HAUTE | confirmé | `AppDependencies+Data.swift:59-64`, `VehiclesView.swift:132-137` | Véhicule vide créé si on ferme la feuille (pas de bouton Annuler) |
| 4.7 | HAUTE | confirmé | `LocalizationService.swift:54-66` | La langue choisie ne s'applique qu'à la moitié des textes, PDF compris |
| 4.8 | HAUTE | confirmé | `App/Info.plist` | Texte de permission de localisation en anglais dans les 6 langues |
| 5.1 | HAUTE | confirmé | 64 × `.system(size:)`, 0 × `relativeTo` | Dynamic Type sans effet sur le contenu ; chrome système désaligné |
| 1.4 | MOYENNE | confirmé | `HomeView.swift:84`, `AccessPolicy.swift:5` | Fin des 3 jours invisible sur Home ; paywall en pleine voiture |
| 1.5 | MOYENNE | confirmé | `MileagePocketApp.swift:22-28` | Widget START sans effet ni paywall quand l'accès est expiré |
| 2.3 | MOYENNE | confirmé | `TripDetailView.swift:183-186` | Distance invalide : « Enregistrer » sans effet ni message |
| 2.5 | MOYENNE | confirmé | `SettingsView.swift:208` | « Restaurer » sans aucun retour (le paywall, lui, gère l'erreur) |
| 2.7 | MOYENNE | confirmé | `VehiclesView.swift:153-182` | Feuille de choix de véhicule vide : consigne sans bouton, sans croix |
| 3.1 | MOYENNE | confirmé | `TripsView.swift:30-36` | Recherche sans résultat → « enregistrez votre premier trajet » |
| 3.2 | MOYENNE | confirmé | `HomeView.swift:113` + 2 autres | Sans réseau, le trajet s'intitule « — → — » |
| 4.3 | MOYENNE | confirmé | `Localizable.xcstrings` `activetrip.paused` | « Stopped » affiché pendant un trajet en cours (EN seulement) |
| 4.4 | MOYENNE | confirmé | `TripSummarySheet.swift:47` | « Trip saved » au-dessus des boutons Enregistrer / Abandonner |
| 4.5 | MOYENNE | confirmé | `home.start` vs `activetrip.stop` | INICIAR/STOP, AVVIA/STOP : paire traduite à moitié en es/it/pt |
| 5.4 | MOYENNE | confirmé | `TripsView.swift:56-65` | Bouton filtre sans label VoiceOver ; état porté par le seul glyphe |
| 5.5 | MOYENNE | confirmé | `RootView.swift:30`, `Components.swift:106` | Reduce Motion ignoré ; le seul garde-fou protège du code mort |
| 5.6 | MOYENNE | confirmé | `PaywallView.swift:236-243` + 5 autres | Cibles tactiles jusqu'à ~15 pt (liens légaux) |
| 5.7 | MOYENNE | confirmé | `Theme.swift:15` | Ambre `#E8730A` : 2,79:1 sur fond clair, échec AA sur 4 libellés |
| 6.1 | MOYENNE | confirmé | `Typography.swift`, 64 tailles en dur | Design system contourné ; `meterLarge`/`meterMedium` jamais utilisés |
| 3.4 | BASSE | confirmé | `ReportsView.swift:115-128` | Rapport vide générable, l'avertissement est sous les boutons |
| 4.2 | BASSE | confirmé | `widget.month.total`, `notification.trip.saved.*` | 3 clés traduites 6 fois, jamais affichées |
| 4.6 | BASSE | confirmé | `home.empty.title` vs `trips.empty.title` | Deux formulations pour le même état ; vocabulaire système |
| 4.9 | BASSE | confirmé | `LocalizationService.swift:31-39` | « Suivre le système » écrit, jamais branché : choix de langue sans retour |
| 6.2-6.5 | BASSE | confirmé | 4 écrans | Chiffre héros en 3 tailles, 5 rayons, 2 marges |
| 7.2 | BASSE | confirmé | `OnboardingFlow.swift:107-110,36` | Le pays n'est appliqué que par le bouton, pas par le balayage |
| 2.8 | BASSE | soupçonné | `TripSummarySheet.swift:208-213` | `delete` avant `clearFinishedTrip` : la feuille lit un objet supprimé |
| 5.2 | BASSE | soupçonné | `ReportsView.swift:79-84` | 4 segments, « Trimestre » : troncature probable aux grandes tailles |

---

## Verdict

**« Start. Drive. Stop. Export. » tient sur le squelette et casse sur la chair.**

Le *Start* et le *Drive* sont bons en nombre de gestes — 3 taps, un dial de 220 pt, une
feuille de résumé pré-remplie — mais *Start* peut démarrer un trajet fantôme sans permission
(1.2), *Stop* n'a aucun accusé de réception pendant deux appels réseau sans timeout (1.1),
et *Export* peut échouer sans dire un mot (2.4). Entre les deux, le seul bouton d'évasion de
la feuille de résumé détruit le trajet sans confirmation (2.1).

Le squelette est juste. Ce qui manque, ce sont les états : chargement, erreur, permission,
recherche vide, hors-ligne. L'app n'a qu'un seul écran qui les traite correctement — le
paywall — et le reste du produit devrait s'aligner sur lui.

Deux corrections rendraient la promesse tenable immédiatement : **un état visible pour la
permission de localisation**, et **un retour immédiat au tap sur STOP**. Les deux sont
locales.
