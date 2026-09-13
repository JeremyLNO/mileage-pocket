# Audit — Abonnement, paywall et droits d'accès

**App** : Mileage Pocket (`/Users/jeremy/mileage-pocket`)
**Date** : 2026-09-13
**Périmètre** : `Services/Subscription/`, `Core/Access/`, `Features/Paywall/`, `Core/Debug/DemoMode.swift`, tous les sites d'appel de `canAccess`.
**Méthode** : lecture seule. Aucun fichier du projet modifié, aucun build, aucun test lancé. Les seules commandes exécutées sont des lectures (`cat`, `grep`, `plutil -p`, `strings`) sur les sources et sur les binaires **déjà présents** dans `build/`.

---

## 1. Ce que la politique dit, et ce qu'elle vaut

`Core/Access/AccessPolicy.swift:28-34` implémente exactement la règle voulue :

```swift
static func allows(_ feature: PremiumFeature, entitlement: Entitlement, freePeriodActive: Bool) -> Bool {
    if entitlement.isActive { return true }
    if feature == .exportReport { return false }
    return freePeriodActive
}
```

`PremiumFeature` (`Services/Subscription/Entitlement.swift:45-50`) couvre les quatre bonnes portes : `startTrip`, `manualTrip`, `exportReport`, `multipleVehicles`. L'historique et la suppression ne sont volontairement pas des cas de l'enum — conforme.

**La fonction pure est juste. Toutes les fuites trouvées sont aux sites d'appel, pas dans la règle.**

Sites d'appel de `canAccess` — les cinq existants sont corrects :

| Site | Fonctionnalité | Comportement si refusé |
|---|---|---|
| `App/MileagePocketApp.swift:25` | `.startTrip` (lien profond widget) | **ne fait rien** (voir A-12) |
| `Features/Home/HomeView.swift:157` | `.startTrip` | présente le paywall |
| `Features/Trips/TripsView.swift:69` | `.manualTrip` | présente le paywall |
| `Features/Vehicles/VehiclesView.swift:42` | `.multipleVehicles` (1er véhicule toujours libre) | présente le paywall |
| `Features/Reports/ReportsView.swift:131` | `.exportReport` | présente le paywall |

Le problème est ailleurs : **deux chemins qui écrivent ou exportent sans jamais passer par `canAccess`.**

---

## 2. Constats

### A-1 — ÉLEVÉ — « Dupliquer » crée un trajet sans aucune vérification (CONFIRMÉ)

`Features/TripDetail/TripDetailView.swift:138-141`

```swift
SecondaryButton(title: "detail.duplicate") {
    dependencies.duplicate(trip)
    dismiss()
}
```

`duplicate(_:)` (`App/AppDependencies+Data.swift:188-211`) insère un **trajet neuf** : `Trip(startedAt: .now)`, distance, adresses, type, client, véhicule copiés, `isManualEntry = true`, `applyCalculation`, `context.save()`. C'est fonctionnellement la saisie manuelle, avec les champs pré-remplis. Aucun `canAccess(.manualTrip)` nulle part sur ce chemin.

**Geste exact** (utilisateur non payant, 3 jours écoulés) :
1. Onglet **Trajets** (ou la carte « Dernier trajet » de l'accueil)
2. Taper n'importe quel trajet → écran de détail
3. **« Dupliquer »** → un trajet daté d'aujourd'hui est créé et enregistré
4. Rouvrir la copie → **« Modifier la distance »** (`TripDetailView.swift:133`, non gardé non plus) → saisir le kilométrage voulu → Enregistrer

Répétable autant de fois qu'on veut. Le gate `.manualTrip` de `TripsView.swift:69` ne protège que le bouton `+`.

**Note** : `detail.edit.distance` et `detail.recalculate` non gardés est défendable (édition d'une donnée existante = historique). `detail.duplicate` ne l'est pas : il **crée**.

---

### A-2 — ÉLEVÉ — « Exporter toutes mes données » donne le CSV vendu (CONFIRMÉ)

`Features/Settings/SettingsView.swift:187-189`

```swift
Button("settings.export.all") {
    if let url = dependencies.exportAllData() { exportFile = ExportedFile(url: url) }
}
```
présenté par `.sheet(item: $exportFile) { file in ShareSheet(url: file.url) }` (`SettingsView.swift:37`), c'est-à-dire un `UIActivityViewController` (`ReportsView.swift:152-159`).

`exportAllData()` (`App/AppDependencies+Data.swift:232-244`) :

```swift
let data = ReportBuilder.build(trips: trips, period: .custom(...), includePersonal: true, ...)
try? CSVExporter.write(CSVExporter.csv(data, profile: reportProfile()), to: url)
```

C'est **le même `CSVExporter.csv(_:profile:)`** que l'export payant (`AppDependencies+Data.swift:221`) : mêmes 7 colonnes `Date, From, To, Purpose, Distance, Rate, Amount`, même ligne TOTAL, même `reportProfile()`. Sur **tous** les trajets et avec `includePersonal: true` — donc un **sur-ensemble strict** du CSV que le paywall vend sous l'intitulé « CSV exports » (`paywall.feature.csv`).

**Geste exact** (jour 1, jamais payé) :
1. Onglet **Réglages** → section **Données**
2. **« Exporter toutes mes données »**
3. Feuille de partage → Enregistrer dans Fichiers / Mail / AirDrop

Le commentaire de `AppDependencies+Data.swift:230-231` défend le choix (« a person's own record has to remain retrievable »). L'intention est bonne et l'argument RGPD tient, **mais l'implémentation actuelle ne fait aucune différence entre un vidage de données et le livrable commercial** : c'est le même fichier, en mieux. Si le dump doit rester libre, il doit être un format distinct (JSON brut, pas de colonnes Rate/Amount, pas de `reportProfile()` d'en-tête) ; sinon il doit passer par `canAccess(.exportReport)`.

---

### A-3 — ÉLEVÉ — Un abonné est bloqué au lancement tant que le réseau n'a pas répondu (CONFIRMÉ)

`Services/Subscription/SubscriptionService.swift:94-105`

```swift
func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
        let loaded = try await Product.products(for: ProductIDs.all)   // ← appel réseau App Store
        products = loaded.sorted { ... }
        lastError = nil
    } catch {
        lastError = error.localizedDescription
    }
    await refreshEntitlement()                                          // ← seulement après
}
```

`entitlement` vaut `.none` à l'initialisation (`SubscriptionService.swift:8`). `start()` (ligne 77-92) lance `load()` dans une `Task` détachée depuis `bootstrap()` (`App/AppDependencies.swift:117`). Le droit n'est donc résolu qu'**après** la requête catalogue, qui est un aller-retour réseau vers l'App Store.

Or `refreshEntitlement()` → `Transaction.currentEntitlements` lit des transactions **signées localement** : elle n'a pas besoin du catalogue. La séquence actuelle fait dépendre un état local d'un appel distant.

Pendant cette fenêtre, pour un abonné dont les 3 jours sont passés : `entitlement.isActive == false` et `freePeriod.isActive() == false` ⇒ `canAccess` rend `false` pour **tout**.

**Geste exact** :
1. Activer le mode Avion (ou se garer dans un parking souterrain, ou un réseau saturé)
2. Forcer la fermeture de Mileage Pocket
3. Rouvrir l'app
4. Appuyer sur **START** dans les premières secondes → **paywall**, alors que l'abonnement est actif

C'est le bouton le plus important de l'app, pressé au moment où le réseau est le plus mauvais (voiture, sous-sol, départ).

**Correctif** : appeler `refreshEntitlement()` **avant** le `Product.products(...)`, ou dans une `Task` parallèle. Le catalogue ne sert qu'à dessiner le paywall.

---

### A-4 — MOYEN — La période de grâce de facturation est inaccessible hors-ligne (CONFIRMÉ)

`Services/Subscription/SubscriptionService.swift:147-163`

```swift
private func gracePeriodEntitlement() async -> Entitlement? {
    guard let subscription = products.first?.subscription else { return nil }
    ...
}
```

Le repli « période de grâce » dépend de `products`, donc du même appel réseau qu'en A-3. Si `Product.products` a échoué (hors-ligne, App Store injoignable, produits pas encore approuvés), `products` est vide et **toute** la détection de grâce est morte : un abonné dont la carte a été refusée, et qu'Apple est en train de relancer, est refusé.

Il faut passer par `Product.SubscriptionInfo.status` obtenu autrement, ou au minimum retenter le chargement du catalogue avant de conclure `.none`.

**Aucun test ne couvre ce chemin** : `gracePeriodEntitlement()` est `private` et `refreshEntitlement()` n'est exercé de bout en bout que dans `SubscriptionTests.testWithNoTransactionsPremiumIsClosed` (achat puis `clearTransactions`), qui ne met jamais de statut en grâce.

---

### A-5 — MOYEN — Aucun rafraîchissement au retour au premier plan (CONFIRMÉ)

`bootstrap()` (`App/AppDependencies.swift:101`) n'est appelé qu'une fois, par `.task { dependencies.bootstrap() }` (`App/MileagePocketApp.swift:21`). `grep -rn "scenePhase\|willEnterForeground\|didBecomeActive"` sur `App/`, `Features/`, `Services/` : **zéro résultat**.

Conséquences, dans les deux sens :
- Un lancement qui a résolu `.none` à tort (cf. A-3) ne se corrige que par `Transaction.updates` (`SubscriptionService.swift:83`) — qui couvre bien un renouvellement ou un achat sur un autre appareil — ou en ouvrant le paywall, dont le `.task` relance `load()` seulement `if service.products.isEmpty` (`PaywallView.swift:60-62`). L'utilisateur doit donc se heurter au paywall pour que son droit soit re-vérifié.
- À l'inverse, un abonnement qui **expire** pendant que l'app tourne reste actif jusqu'au prochain lancement. Fuite dans le sens clément, bénigne.

---

### A-6 — MOYEN — La période gratuite est rouvrable en reculant l'horloge (CONFIRMÉ)

`Core/Access/AccessPolicy.swift:9-19`

```swift
var endsAt: Date { startedAt.addingTimeInterval(Self.duration) }
func isActive(now: Date = .now) -> Bool { now < endsAt }
```

La date d'installation est bien protégée : `InstallDateStore` (`Core/Access/InstallDateStore.swift`) écrit dans le keychain avec `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, qui survit à la suppression de l'app — la réinstallation ne redonne donc rien. **Mais rien ne surveille l'horloge** : pas d'ancre monotone, pas de « date maximale déjà vue », aucune comparaison avec un temps serveur.

**Geste exact** :
1. Réglages iOS → Général → **Date et heure** → désactiver « Réglage automatique »
2. Reculer la date de 30 jours
3. Rouvrir Mileage Pocket

`now < endsAt` redevient vrai → START, saisie manuelle et véhicules multiples sont rouverts. `daysRemaining` (ligne 16-19) rend alors `ceil((endsAt - now)/86400)` = **33**, affiché tel quel dans Réglages → Formule actuelle via `subscriptionDescription()` (`App/AppDependencies+Data.swift:308-310`).

Dissuasion naturelle partielle : les trajets enregistrés pendant ce temps portent la fausse date. Mais les fonctions marchent.

**Correctif minimal** : stocker aussi la date la plus élevée jamais observée et refuser tout `now` antérieur (ou borner `daysRemaining` à 3).

---

### A-7 — MOYEN — Un test prouve le contraire de son nom (CONFIRMÉ)

`Tests/AccessPolicyTests.swift:82-87`

```swift
/// A clock that has been moved backwards must not extend the period beyond its length.
func testAnEarlierClockDoesNotExtendThePeriod() {
    let period = FreeAccessPeriod(startedAt: start)
    XCTAssertTrue(period.isActive(now: start.addingTimeInterval(-86_400)))
    XCTAssertLessThanOrEqual(period.daysRemaining(now: start.addingTimeInterval(-86_400)), 4)
}
```

Le nom annonce une protection. Les assertions **entérinent la faille** : la période est déclarée active un jour **avant** l'installation, et le nombre de jours restants est accepté jusqu'à **4** alors que la politique en dit 3. La borne de 4 n'est pas une limite du système, c'est simplement la valeur que rend la fonction pour un décalage de 24 h ; à −30 jours elle rend 33, ce que le test ne vérifie pas.

C'est le cas d'école du garde-fou écrit sans avoir vérifié l'hypothèse : le test est vert, le trou est ouvert, et le nom du test empêche qu'on le rouvre.

---

### A-8 — MOYEN — `testEveryPremiumFeatureIsGuarded` ne teste aucun garde (CONFIRMÉ)

`Tests/EntitlementTests.swift:14-21` compare `Set(PremiumFeature.allCases.map(\.rawValue))` à une liste en dur. Il ne touche **aucun** site d'appel. A-1 et A-2 passent ce test au vert sans difficulté. Le nom promet « chaque fonctionnalité premium est gardée » ; le corps prouve « l'enum a quatre cas ».

Ce qui manquerait pour que le nom soit vrai : un test qui énumère les appels à `duplicate`, `createManualTrip`, `export`, `exportAllData`, `makeVehicle`, `startTrip` et vérifie qu'aucun n'est atteignable sans `canAccess` — ou, plus simplement, déplacer le garde **dans** `AppDependencies` (au début de `duplicate`, `createManualTrip`, `export`) plutôt que dans les vues.

---

### A-9 — MOYEN — L'état « période expirée » n'est testé nulle part dans l'app (CONFIRMÉ)

`DemoMode` (`Core/Debug/DemoMode.swift:46`) offre `--reset-free-period`, qui **redémarre** la période. Il n'existe aucun drapeau pour la faire **expirer**.

Conséquence : `UITests/PaywallUITests.swift:105-144` ne teste que la période **active** (`testStartingATripDoesNotShowThePaywall`, `testExportingDuringTheFreePeriodStillShowsThePaywall` — ces deux-là prouvent bien ce qu'ils annoncent, et le second couvre correctement la règle « export payant dès le jour 1 »).

La règle « après 3 jours, tout le reste passe derrière le paywall » n'est vérifiée que sur la fonction pure (`AccessPolicyTests.swift:28-35`), **jamais dans l'app**. Or c'est exactement l'état dans lequel A-1 et A-2 s'appliquent. Un `--expire-free-period` (écrivant une date d'installation à J-10) ferait tomber les deux.

---

### A-10 — MOYEN — Un commentaire de test UI qui n'est pas vrai (CONFIRMÉ)

`UITests/PaywallUITests.swift:31-36`

```swift
// Prices come from StoreKit, never from a literal in the UI. Asserting the configured
// amounts proves the products loaded *and* that nothing is hard-coded elsewhere.
let monthly = app.staticTexts["$2.99"]
```

Le test lance avec `--fake-store` (ligne 20). Dans ce mode, `SubscriptionService.plans` (`SubscriptionService.swift:27-34`) constate `products.isEmpty` et rend `PaywallPlan.fromBundledConfiguration()` — les prix sont lus dans `Config/MileagePocket.storekit` embarqué et reformatés localement (`PaywallPlan.swift:33-56`). **StoreKit n'a rien répondu.**

Le test prouve que le JSON a été lu et rendu correctement, ce qui a de la valeur pour la capture de revue App Store. Il ne prouve pas « the products loaded ». L'en-tête du fichier (lignes 14-19) explique honnêtement pourquoi la session StoreKit n'atteint pas l'app ; c'est le commentaire en ligne 31 qui sur-promet.

Ce qui prouve réellement l'absence de prix en dur : `SubscriptionTests.testBothPlansLoadFromStoreKit` + `testAnnualSavingIsDerivedFromTheLivePrices` (contre un vrai `SKTestSession`), et le fait que `fromBundledConfiguration()` soit `#if DEBUG`.

---

### A-11 — FAIBLE/MOYEN — Aucune mention du renouvellement automatique sur le paywall (CONFIRMÉ)

Textes (`Resources/Localizable.xcstrings`) :

| Clé | Valeur EN |
|---|---|
| `paywall.footer.plain` | `%@. Cancel anytime.` |
| `paywall.footer.trial` | `3 days free, then %@. Cancel anytime.` |
| `paywall.per.month` / `per.year` | `per month` / `per year` |

Ce qui est en place et correct :
- **Prix** : `Product.displayPrice` uniquement (`PaywallPlan.swift:19`), économie annuelle calculée sur les prix vivants (`SubscriptionService.swift:42-48`) — rien en dur en Release.
- **Durée et titre** : cartes « Monthly / $2.99 / per month » et « Annual / $29.99 / per year » (`PaywallView.swift:166-176`).
- **Restauration** : présente sur le paywall (`PaywallView.swift:55`) et dans Réglages (`SettingsView.swift:208`).
- **Conditions et confidentialité** : `PaywallView.swift:238-239` + `SettingsView.swift:214-215`. **URL vérifiées dans l'Info.plist compilé** (`plutil -p` sur `build/MileagePocket.xcarchive/.../Info.plist`) : `https://www.crazybeelabs.com/legal/apps` pour les deux, `https://crazybeelabs.com/support/`. Le contournement `$(SLASH)` de `Config/Base.xcconfig` fonctionne — pas de troncature à `https:`.
- **Sortie** : bouton Fermer toujours présent, plus le cas onboarding via `onClose` (`OnboardingFlow.swift:224`). Les deux couverts par `testPaywallCanBeDismissed` et `testClosingTheOnboardingPaywallEntersTheApp`, qui prouvent bien ce qu'ils annoncent.

Ce qui manque : **la phrase de renouvellement automatique**. « Cancel anytime » n'est pas une divulgation d'auto-renouvellement. La 3.1.2 exige que le binaire indique que l'abonnement se renouvelle automatiquement sauf annulation au moins 24 h avant la fin de la période. C'est un motif de rejet fréquent et facile à corriger (un mot dans les deux clés `paywall.footer.*`).

---

### A-12 — FAIBLE — Cohérence liste d'avantages / réalité

`PaywallView.featureKeys()` (`PaywallView.swift:102-114`) :

| Avantage affiché | Réellement gardé ? |
|---|---|
| `Unlimited trip tracking` | Oui (`.startTrip`). « Unlimited » suggère un plafond de trajets côté gratuit qui n'existe pas — c'est une limite de **temps**, pas de nombre. |
| `Mileage calculations` | **Non.** Aucun `PremiumFeature` ne couvre le calcul : `applyCalculation` tourne sur chaque trajet et le taux/montant s'affichent librement dans le détail, la liste et les rapports. |
| `Monthly PDF reports` | Oui (`.exportReport`). |
| `CSV exports` | Oui en théorie — **contredit par A-2**. |
| `Multiple vehicles` | Oui (`.multipleVehicles`, 1er véhicule libre). |
| `iCloud backup` | Correctement **masqué** : `CloudKitAvailability.isEntitled` lit `CloudKitAvailable` de l'Info.plist, qui vaut `"NO"` dans l'archive (vérifié). Bonne gestion — promettre une sauvegarde inexistante est le seul mensonge de cet écran qui coûterait des données. |

---

### A-13 — FAIBLE — Le lien profond du widget échoue en silence (CONFIRMÉ)

`App/MileagePocketApp.swift:22-28`

```swift
.onOpenURL { url in
    guard url.host == "start" || url.path == "/start" else { return }
    if dependencies.canAccess(.startTrip), !dependencies.isRecording {
        dependencies.startTrip()
    }
}
```

La vérification est **correcte** (pas de contournement par le widget). Mais quand elle refuse, il ne se passe **rien** : pas de paywall, pas de message. L'utilisateur tape le widget « Démarrer un trajet », l'app s'ouvre sur l'accueil, et il croit que le widget est cassé. `HomeView.swift:157-160` présente le paywall dans le même cas ; ce chemin devrait faire pareil.

Second effet : après les 3 jours, `isRecording == false` et `canAccess == false` sont indiscernables de l'extérieur — le widget continue d'afficher son bouton comme si de rien n'était.

---

### A-14 — FAIBLE — La restauration depuis Réglages est muette (CONFIRMÉ)

`Features/Settings/SettingsView.swift:208`

```swift
Button("paywall.restore") { Task { try? await dependencies.subscriptions.restore() } }
```

`try?` avale l'erreur, aucun indicateur d'activité, aucun message de succès. Un abonné qui restaure depuis Réglages ne voit **rien** — ni pendant, ni après, ni en cas d'échec. La version du paywall (`PaywallView.swift:272-279`) fait mieux : elle affiche l'erreur et ferme l'écran en cas de succès.

C'est un chemin « abonné bloqué » de plus : l'utilisateur qui restaure et ne voit rien conclut que la restauration ne marche pas.

---

### A-15 — FAIBLE — La configuration StoreKit de dev est livrée dans l'archive Release (CONFIRMÉ)

```
build/MileagePocket.xcarchive/Products/Applications/MileagePocket.app/MileagePocket.storekit   2248 octets
```

`gen_pbxproj.py:660` ajoute le fichier à la phase Resources **sans condition de configuration**. Il contient les identifiants produits, les prix de développement, `_developerTeamID: 2E6D4Q69QB` et les internalIDs.

Sans effet fonctionnel : le seul lecteur, `PaywallPlan.fromBundledConfiguration()`, est `#if DEBUG` et `DemoMode.usesBundledStoreConfiguration` rend `false` en Release. Mais c'est un artefact de développement dans l'IPA publié. À conditionner à Debug (ce qui obligera à un autre moyen pour `SubscriptionTests.setUp`, qui le lit via `Bundle.main`).

---

### A-16 — FAIBLE — Une transaction non vérifiée n'est jamais soldée (CONFIRMÉ)

`SubscriptionService.swift:110-118` (achat) et `83-89` (listener) ne `finish()` que les transactions `.verified`. Une transaction non vérifiée n'est jamais terminée : elle sera redélivrée dans `Transaction.updates` à chaque lancement, déclenchant un `refreshEntitlement()` inutile.

**Le droit reste correctement refusé** (lignes 112-114 et 206) — c'est le bon comportement de sécurité. Seul le cycle de vie de la transaction est incomplet.

---

### A-17 — INFO — Le mapping des états de renouvellement est mort en production

`SubscriptionService.entitlement(for:productID:expires:isTrial:)` (lignes 183-201) n'a **qu'un seul appelant en production** : `gracePeriodEntitlement()` ligne 155, qui a déjà fait `guard status.state == .inGracePeriod` ligne 154. Les branches `.subscribed`, `.expired`, `.revoked`, `.inBillingRetryPeriod` ne sont donc jamais atteintes par l'app.

`SubscriptionTests.testEveryRenewalStateMapsToTheRightEntitlement` (lignes 107-126) teste scrupuleusement les six cas d'une fonction dont un seul est vivant. Ce n'est **pas** un défaut de droit — `entitlementFromCurrentEntitlements` (lignes 203-216) couvre correctement expiré et remboursé par ailleurs, et le commentaire des lignes 131-138 explique honnêtement la répartition. Mais le test donne l'impression de couvrir les états StoreKit alors qu'il couvre une table de correspondance largement inutilisée.

---

### A-18 — INFO — Code mort et comparateur fragile

- `App/AppDependencies.swift:51` — `needsSubscription` n'a **aucun appelant** (`grep -rn` : une seule ligne, sa définition). Conséquence produit : rien dans l'app n'avertit qu'il reste X jours, sauf la ligne « Formule actuelle » enfouie dans Réglages (`AppDependencies+Data.swift:308-310`). L'utilisateur découvre la fin de sa période en s'y heurtant.
- `SubscriptionService.swift:99` — `sorted { lhs, _ in lhs.id == ProductIDs.monthly }` ignore son second argument : ce n'est pas un ordre strict-faible. Correct par accident pour 2 éléments, faux dès 3.

---

### A-19 — INFO — `InstallDateStore` échoue en s'ouvrant

`Core/Access/InstallDateStore.swift:18-22`

```swift
static func firstLaunchDate(now: Date = .now) -> Date {
    if let existing = read() { return existing }
    write(now)
    return read() ?? now
}
```

Si l'écriture keychain échoue, on retombe sur `now` sans rien signaler — et chaque lancement rendrait alors 3 nouveaux jours. Les statuts de `SecItemAdd` et `SecItemUpdate` (lignes 53-57) sont ignorés.

Peu probable en pratique (`bootstrap()` tourne depuis un `.task` de vue, donc au premier plan, donc appareil déverrouillé, et l'accessibilité est `AfterFirstUnlock`). Mais l'échec est **ouvert**, pas fermé.

---

## 3. Réponses aux six questions

### Q1 — Un non-payant peut-il atteindre une fonction premium ? **Oui, deux fois.**

- **A-1** : Trajets → un trajet → **Dupliquer** crée un trajet neuf (`isManualEntry = true`) sans gate. Puis « Modifier la distance » sur la copie. Répétable.
- **A-2** : Réglages → Données → **Exporter toutes mes données** rend un CSV produit par le même exporteur que la version payante, sur plus de trajets.

Les cinq sites de `canAccess` existants sont corrects. Le widget, le lien profond `mileagepocket://start`, la feuille de résumé de trajet, le sélecteur de véhicule et l'onboarding ne fournissent **aucun** contournement supplémentaire (vérifié un par un).

### Q2 — Un abonné peut-il être bloqué à tort ? **Oui, trois situations.**

- **A-3** (la plus grave) : réseau lent ou absent au lancement → `entitlement` reste `.none` jusqu'à ce que `Product.products` réponde → START rend le paywall à un abonné.
- **A-4** : hors-ligne, la période de grâce de facturation est indétectable (elle dépend de `products`).
- **A-5** : aucun rafraîchissement au premier plan, donc aucune correction automatique d'un mauvais verdict initial.
- **A-14** : la restauration depuis Réglages ne dit jamais si elle a marché.

**Ce qui marche bien** : achat sur un autre appareil et renouvellement sont couverts par le listener `Transaction.updates` qui tourne pour toute la vie de l'app (`SubscriptionService.swift:82-90`) ; la restauration après réinstallation est réellement testée (`SubscriptionTests.testRestoringBringsBackAPreviousPurchase`, lignes 164-176).

### Q3 — La période gratuite est-elle contournable ? **Oui, par l'horloge. Non, par les autres voies.**

| Voie | Verdict |
|---|---|
| Désinstaller / réinstaller | **Bloqué** — keychain `AfterFirstUnlockThisDeviceOnly`, survit à la suppression de l'app |
| Changer l'heure de l'appareil | **CONTOURNABLE (A-6)** — reculer la date rouvre la période, sans limite |
| « Supprimer toutes les données » | **Bloqué** — `deleteAllData()` ne touche pas `InstallDateStore` (`AppDependencies+Data.swift:276-277`), commentaire explicite |
| Mode démo en Release | **Impossible (Q4)** |
| Restauration sur un **nouveau** téléphone | Redonne 3 jours (`ThisDeviceOnly` ne migre pas) — clémence assumée et acceptable |

### Q4 — `DemoMode` fuit-il en Release ? **Non. Vérifié sur le binaire archivé.**

`strings -a build/MileagePocket.xcarchive/Products/Applications/MileagePocket.app/MileagePocket` :

```
--demo            -> 0      --reset-data        -> 0
--demo-data-only  -> 0      --reset-free-period -> 0
--fake-store      -> 0      --onboarding-step   -> 0
--screen          -> 0      Jane Doe            -> 0
--tab             -> 0      Doe Consulting      -> 0
--export-report   -> 0
```

**Contrôles, pour que ce zéro veuille dire quelque chose** :
- La dylib Debug **contient** bien ces chaînes (`--demo` ×1, `Jane Doe` ×1) → la méthode détecte ce qu'elle cherche.
- Le binaire Release contient bien d'autres chaînes de l'app (`company.lno.mileage` ×6) → il n'est pas dépouillé de toutes ses chaînes.

Et la raison pour laquelle c'est vrai :
- `gen_pbxproj.py:825` ne pose `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"` que pour la configuration **Debug** ; la branche Release ne définit rien de tel.
- Le `#else` de `DemoMode` (lignes 51-62) couvre bien les **dix** drapeaux du bloc `#if DEBUG` — aucun oublié, donc aucune erreur de compilation qui aurait masqué un trou.
- `DemoMode.seed(...)` n'est pas sous `#if DEBUG` mais démarre par `guard isEnabled else { return false }`, constante `false` en Release — code mort, éliminé (les chaînes de données démo sont absentes du binaire, ce qui le prouve).
- `SubscriptionService.plans` (ligne 28) et `fakeAnnualSavingsPercent` (ligne 52) sont gardés par `DemoMode.usesBundledStoreConfiguration`, `false` en Release, et leur corps est `#if DEBUG`.

Réserve mineure : le fichier `.storekit` lui-même est livré (A-15), mais aucun code ne le lit en Release.

### Q5 — Le paywall est-il conforme aux règles Apple ? **Presque — un manque.**

Prix jamais en dur ✔ · restauration présente ✔ (mais muette dans Réglages, A-14) · Conditions et Confidentialité accessibles avec des URL correctes dans l'Info.plist compilé ✔ · sortie possible et testée ✔ · un écran de secours avec « Réessayer » quand le store ne répond pas ✔ (`PaywallView.swift:118-140`) · iCloud correctement retiré de la liste quand l'app n'y a pas droit ✔.

**Manque** : la divulgation de **renouvellement automatique** (A-11). **Incohérences** : « Mileage calculations » n'est pas gardé, « CSV exports » est contredit par A-2 (A-12).

### Q6 — Les états StoreKit mènent-ils au bon droit ?

| État | Chemin | Verdict |
|---|---|---|
| Expiré | `grantsAccess(expiresAt:)` ligne 208, puis repli grâce → `nil` | **Correct** |
| Remboursé | `grantsAccess(revokedAt:)` ligne 208 | **Correct** — et testé sur la borne exacte (`SubscriptionTests:148-162`), avec un commentaire honnête expliquant pourquoi `SKTestSession.refundTransaction` ne pouvait pas servir de preuve |
| Annulé (renouvellement coupé, période en cours) | reste dans `currentEntitlements`, expiry future → `.subscribed` | **Correct** — accès jusqu'à l'échéance |
| Période de grâce | repli `gracePeriodEntitlement()` → `.gracePeriod` → `isActive` | **Correct en principe, cassé hors-ligne (A-4)** |
| Relance de facturation (sans grâce) | absent de `currentEntitlements`, `.inBillingRetryPeriod` ignoré ligne 154 | **Correct** |
| Non vérifié | `guard case let .verified` lignes 112 et 206 | **Correct** — jamais accordé (transaction non soldée, A-16) |
| Essai d'introduction | `transaction.offer?.type == .introductory` ligne 210 | **Correct** — `.trial`, actif, et jamais une date écrite par l'app |

La double lecture `currentEntitlements` (autorité sur la possession) + `status` (uniquement pour la grâce) est bien conçue et le commentaire des lignes 131-138 explique exactement pourquoi. Le seul défaut est la dépendance de la seconde au catalogue réseau.

---

## 4. Ce que valent les tests

| Test | Prouve-t-il ce qu'il prétend ? |
|---|---|
| `AccessPolicyTests.testTheAppWorksNormallyDuringTheFreePeriod` | **Oui** — sur la fonction pure |
| `AccessPolicyTests.testExportIsNeverFreeEvenDuringTheFreePeriod` | **Oui** — la règle la plus importante, sur la fonction pure |
| `AccessPolicyTests.testEverythingIsGatedOnceTheFreePeriodIsOver` | **Oui pour la fonction, non pour l'app** — A-1 et A-2 ne passent pas par elle (A-9) |
| `AccessPolicyTests.testTheBoundaryIsTestedOnTheBoundary` | **Oui** — borne exacte, les deux côtés |
| `AccessPolicyTests.testDaysRemainingCountsTheLastPartialDayAsOne` | **Oui** |
| `AccessPolicyTests.testAnEarlierClockDoesNotExtendThePeriod` | **NON — prouve l'inverse de son nom (A-7)** |
| `InstallDateStoreTests.*` | **Oui**, et le `setUp`/`tearDown` restaure proprement l'item keychain pour ne pas empoisonner les tests UI suivants |
| `EntitlementTests.testOnlyAnActiveEntitlementUnlocksPremium` | **Oui** |
| `EntitlementTests.testEveryPremiumFeatureIsGuarded` | **NON — ne teste aucun garde (A-8)** |
| `SubscriptionTests.testBothPlansLoadFromStoreKit` / `...ThreeDayIntroductoryOffer` / `...AnnualSavingIsDerived` | **Oui** — vrai `SKTestSession`, et le `XCTAssertFalse(session.storefront.isEmpty)` du `setUp` empêche une session morte de passer pour un catalogue vide |
| `SubscriptionTests.testPurchasing*` / `testAnIntroductoryPurchaseIsReportedAsATrial` | **Oui** |
| `SubscriptionTests.testRevokedOrExpiredTransactionsGrantNothing` | **Oui** — sur la borne, et le commentaire dit franchement pourquoi le chemin StoreKit ne pouvait pas servir |
| `SubscriptionTests.testEveryRenewalStateMapsToTheRightEntitlement` | **Oui sur la fonction, mais 5 branches sur 6 sont mortes en production (A-17)** |
| `SubscriptionTests.testRestoringBringsBackAPreviousPurchase` | **Oui** — vraie preuve de la restauration après réinstallation |
| `PaywallUITests.testPaywallShowsLivePricesAndTheTrialOffer` | **Partiellement** — prouve le rendu, pas que StoreKit a répondu (A-10) |
| `PaywallUITests.testPaywallCanBeDismissed` / `testClosingTheOnboardingPaywallEntersTheApp` | **Oui** — et le second couvre un vrai bug passé (le bouton Fermer inerte dans l'onboarding) |
| `PaywallUITests.testStartingATripDuringTheFreePeriodDoesNotShowThePaywall` | **Oui** |
| `PaywallUITests.testExportingDuringTheFreePeriodStillShowsThePaywall` | **Oui** — la meilleure preuve du jeu de tests : la règle « export payant dès le jour 1 » vérifiée dans l'app réelle |

**Trou principal** : aucun test n'exerce l'app dans l'état « période expirée, pas d'abonnement ». C'est le seul état où A-1 et A-2 mordent.

---

## 5. Ordre de correction proposé

1. **A-1** — ajouter `guard canAccess(.manualTrip)` dans `duplicate(_:)` (dans `AppDependencies+Data.swift`, pas dans la vue : c'est ce qui empêche la prochaine vue d'oublier), et présenter le paywall depuis `TripDetailView`.
2. **A-3** — appeler `refreshEntitlement()` avant, ou en parallèle de, `Product.products(...)`.
3. **A-2** — décider : soit le dump passe sous `canAccess(.exportReport)`, soit il devient un format qui n'est plus le livrable vendu (pas de colonnes Rate/Amount, pas d'en-tête `reportProfile()`).
4. **A-6** — ancre monotone dans le keychain (date maximale vue), ou plafonner `daysRemaining` à 3.
5. **A-11** — une phrase d'auto-renouvellement dans `paywall.footer.plain` et `paywall.footer.trial`, dans les 6 langues.
6. **A-4 / A-5** — repli de grâce indépendant du catalogue, et rafraîchissement sur `scenePhase == .active`.
7. **A-9 / A-7 / A-8** — drapeau `--expire-free-period`, puis deux tests UI (Dupliquer et Exporter toutes mes données doivent lever le paywall) ; réécrire ou supprimer `testAnEarlierClockDoesNotExtendThePeriod`.
8. Le reste (A-12 à A-19) au fil de l'eau.
