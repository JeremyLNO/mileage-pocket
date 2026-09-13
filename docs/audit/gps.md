# Audit GPS & distance — Mileage Pocket

Périmètre : `Services/Location/*`, `Features/ActiveTrip/*`, `App/AppDependencies.swift`.
Méthode : lecture ligne à ligne + **port Python fidèle du `LocationFilter`** rejouant les
fixtures du dépôt. Le port reproduit à la décimale les quatre chiffres que les tests Swift
affirment (998,9 m sur la ligne propre ; 1 749 m de somme naïve contre 1 022,7 m filtrés à
σ = 8 m ; 1 523 m pontés sur le tunnel de 60 s ; 4 941 m après le trou de 10 min). Tous les
chiffres ci-dessous viennent de ce port.

Aucun fichier du projet n'a été modifié. Scripts de rejeu : scratchpad de session.

---

## 1. CRITIQUE — Le pontage efface le compteur d'arrêt : `.paused` est inatteignable

**Confirmé par lecture.**

`LocationFilter.swift:188` appelle `resync(to: sample)` dans la branche de pontage.
`resync` remet `stationarySince = nil` (`LocationFilter.swift:241`).

Conséquence mécanique : dès que deux fixes sont espacés de plus de `bridgeMinGap = 20 s`
(`:75`), chaque fix ponté remet à zéro l'horloge des 120 s de `stopDuration` (`:17`). Elle
n'atteint donc **jamais** 120 s, et `.paused` (`:164`) n'est jamais retourné. Pendant ce
temps la branche de pontage ajoute `straightLine` **brut** (`:187`) : ni plancher de bruit,
ni lissage α-β. Le garde-fou de vraisemblance ne sert à rien ici, parce que
`bridgeSpeedFloor = 36 m/s` (`:80`, utilisé `:182`) laisse passer tout ce qui implique moins
de 130 km/h — un téléphone immobile implique 1 à 2 m/s.

Le pire : c'est le `distanceFilter = 10 m` de l'app (`CoreLocationProvider.swift:29`) qui
produit précisément ces intervalles > 20 s quand le véhicule est à l'arrêt.

### Chiffres

Téléphone parfaitement immobile, positionnement Wi-Fi/cellulaire (parking souterrain, bureau
client, immeuble) : précision rapportée 25-65 m (celles > 50 m sont rejetées), sauts de
15-60 m, un fix toutes les 15-60 s, `speed = -1`. 5 graines :

| Durée immobile | Distance INVENTÉE |
|---|---|
| 15 min | 0,76 – 1,74 km (médiane 1,28) |
| 30 min | 2,05 – 3,11 km (médiane 2,61) |
| 60 min | 4,41 – 5,57 km (médiane 5,41) |
| 120 min | 9,44 – 11,07 km (médiane 9,65) |

Cas déterministe minimal, avec `speed = 0` **correctement rapporté par le GPS** (donc le
détecteur d'arrêt « devrait » fonctionner) : sauts de 25 m toutes les 30 s, précision 30 m →
**6 689 m inventés en 60 min, `paused` = 0, `bridged` = 143**.

Leak pendant les 10 premières minutes d'un arrêt réel, selon l'espacement des fixes :

| Espacement | Inventé en 10 min d'arrêt |
|---|---|
| 21 s | 990 m |
| 25 s | 817 m |
| 30 s | 643 m |
| 45 s | 410 m |
| 60 s | 254 m |

À 8 arrêts de plus de 2 min par journée de tournée : **+5,1 km/jour** de distance inventée.

En ciel ouvert avec un GPS sain (σ 2-6 m), la dérive franchit les 10 m assez souvent pour
que les intervalles restent courts : là le `.paused` fonctionne et l'invention tombe à
0-290 m sur 8 h. **Le défaut est donc conditionnel à un positionnement dégradé — c'est-à-dire
au cas le plus fréquent d'un véhicule garé.**

### Correctif de principe
Ne pas remettre `stationarySince` à `nil` dans le chemin de pontage ; et/ou refuser de ponter
quand `observedSpeed < stopSpeed`.

---

## 2. CRITIQUE — Le fond de tâche n'est jamais armé sur le premier trajet

**Confirmé par lecture.**

`CoreLocationProvider.swift:71-73` :
```swift
if manager.authorizationStatus == .authorizedAlways {
    manager.allowsBackgroundLocationUpdates = true
}
```
Trois problèmes cumulés :

1. `AppDependencies.swift:170-175` demande la permission puis appelle `recorder.start()`
   **immédiatement**. Le prompt est asynchrone : au moment où `startUpdates()` s'exécute, le
   statut vaut encore `.notDetermined`. Le flag reste `false`.
2. Il n'existe **aucun** `locationManagerDidChangeAuthorization` dans le fichier — le délégué
   ne déclare que `didUpdateLocations` (`:109`) et `didFailWithError` (`:119`). Le flag n'est
   donc jamais rearmé après que l'utilisateur a accordé la permission.
3. `startUpdates()` est gardé par `isUpdating` (`:66`) : aucune seconde chance dans le trajet.

De plus la restriction à `.authorizedAlways` est gratuite : `App/Info.plist:49-52` déclare
bien `UIBackgroundModes = location`, et iOS autorise les mises à jour en arrière-plan avec
« Pendant l'utilisation » dès lors que l'indicateur bleu est affiché — ce que le code fait
déjà (`:74`).

**Effet** : le tout premier trajet de chaque utilisateur, et **tous** les trajets d'un
utilisateur resté en « Pendant l'utilisation », s'arrêtent de compter dès que l'écran se
verrouille. Aucun message, aucune trace, le chrono continue de tourner à l'écran.

---

## 3. CRITIQUE — Refus de permission = zéro silencieux

**Confirmé par lecture + grep exhaustif.**

`authorizationStatus` n'est lu que par `AppDependencies.swift:170` et par le
provider/protocole. **Aucune vue ne le lit.** `ActiveTripView.swift` n'affiche que le chrono,
la distance, le véhicule et un badge « en pause » — rien sur la permission.

`TripRecorder.start()` (`:106-131`) ne vérifie pas l'autorisation et ne lève que
`.alreadyRecording` (`:107`). Le commentaire de `AppDependencies.swift:184-185` — « Starting
can only fail for want of location permission; the view already shows the permission state »
— est **faux sur les deux points**.

- **Refus** : START ouvre l'écran de trajet, `RECORDING 0,0 km`, indéfiniment.
- **« Autoriser une fois »** : au lancement suivant le statut retombe à `.notDetermined`
  (pas à `.denied`) ; `startTrip()` redemande, et la course du §2 se reproduit à l'identique —
  le trajet démarre avant la réponse, en foreground seulement.
- **« Pendant l'utilisation »** : voir §2.

---

## 4. ÉLEVÉ — `resumeIfNeeded()` n'a aucune limite d'âge

**Confirmé par lecture.** `TripRecorder.swift:139-165` ne teste ni `active.startedAt` ni
`active.lastUpdatedAt`. Il est appelé une seule fois par lancement de processus
(`AppDependencies.swift:118`, dans `bootstrap()` attaché à un `.task`), sans observation de
`scenePhase`.

**Effet** : un trajet oublié lundi à Paris est repris jeudi à Lyon. Un seul `Trip`, distance =
somme des deux conduites, durée = 3 jours, adresses Paris → Lyon. Le premier fix jeudi se
ré-ancre sans rien compter (`:148-150`), donc le trajet Paris→Lyon lui-même n'apparaît pas :
le document final est faux dans les deux sens à la fois.

---

## 5. ÉLEVÉ — Aucune relance après un kill

**Confirmé par grep.** `startMonitoringSignificantLocationChanges`, `CLVisit`, région
monitorée : **zéro occurrence** dans le dépôt. Le service `startUpdatingLocation` standard ne
fait pas relancer l'app par iOS après une terminaison, contrairement au service
« changements significatifs ».

La partie bancarisée est correctement protégée : `ActiveTripState` est réécrit et sauvé à
chaque fix accepté (`TripRecorder.swift:251-257`), et le test `TripRecorderTests.swift:196`
le prouve fix par fix. Mais tout ce qui est roulé entre le kill et la réouverture manuelle de
l'app est perdu, et le premier fix au retour se ré-ancre sans compter (`:148-150`).

**Effet chiffré** : kill mémoire sur autoroute, app rouverte 20 min plus tard à 110 km/h →
**36,6 km disparus**, dans un trajet qui garde pourtant l'apparence d'un enregistrement
continu (même `Trip`, mêmes extrémités).

---

## 6. ÉLEVÉ — Falaise à 300 s : le tunnel long ne compte rien du tout

**Confirmé par lecture + mesure.** `LocationFilter.swift:138-141`, `tunnelBridgeMaxGap = 300`
(`:13`). Pas de dégradé : au-delà, `resync` + `.gapTooLong`, zéro mètre.

Autoroute à 110 km/h, 27,4 km de vérité terrain :

| Silence | Mesuré | Perdu |
|---|---|---|
| 180 s | 27 365 m | 54 m (bridged) |
| **299 s** | 27 365 m | 54 m (bridged) |
| **301 s** | 18 172 m | **9 247 m** |
| 420 s | 14 552 m | 12 868 m |
| 900 s | 9 107 m | 18 313 m (−67 %) |

Deux secondes de silence en plus font passer 9,1 km de « comptés » à « effacés ». Concerne
tout tunnel alpin (Mont-Blanc 11,6 km, Fréjus 12,9 km, Gothard 17 km) et les longs parkings
souterrains.

---

## 7. ÉLEVÉ — Un réflecteur urbain tenu > 20 s détruit le trajet réel de la fenêtre

**Confirmé par lecture + mesure.** Un fix refusé pose `refusedJump` (`:146`). La branche de
pontage voit ensuite `refusedJump == true` et fait `resync` + `.gapTooLong` (`:178-181`) :
tout ce qui a été roulé depuis le dernier fix accepté est jeté.

Autoroute 110 km/h, réflexion classique à 5 km sur laquelle le récepteur se verrouille :

| Durée du blocage | Distance perdue |
|---|---|
| 19 s | 0 m |
| **21 s** | **724 m** |
| 60 s | 1 912 m |
| 240 s | 6 446 m (−23,5 % du trajet) |

Le test `LocationFilterTests.swift:203-236` ne prouve que le côté « rien n'est inventé »
(véhicule immobile pendant le blocage). Le côté « le kilométrage réel disparaît » n'est testé
nulle part, et le commentaire `:76-78` affirme l'inverse de ce qui se passe ici : « losing
real distance is the costlier error here » — c'est pourtant exactement ce que fait ce chemin.

---

## 8. ÉLEVÉ — Le plancher de bruit coupe les virages : sous-évaluation urbaine systématique

**Confirmé par lecture + mesure.** `LocationFilter.swift:202-206` :
plancher = `max(10, précision × 2)`. Avec une précision de 25 m (courante en ville) le
plancher vaut 50 m ; à la précision maximale acceptée (50 m, `:6`) il vaut **100 m**. L'ancre
ne bouge que lorsque la corde ancre→estimation dépasse ce plancher : la trajectoire comptée
est une décimation en cordes, qui coupe systématiquement à l'intérieur des virages.

Grille urbaine, rayon de braquage réaliste de 10 m, 4,86 km, 10 graines :

| Conditions | Erreur (min / médiane / max) |
|---|---|
| GPS propre (précision 5 m, σ 3 m) | −7,1 % / **−5,7 %** / −4,4 % |
| Ville (précision 15 m, σ 10 m) | −2,9 % / −0,9 % / +1,7 % |
| Ville dégradée (précision 30 m, σ 18 m) | −9,1 % / **−6,1 %** / −1,0 % |

Rond-point r = 20 m à 20 km/h, GPS propre : l'arc de 125,7 m n'en mesure que 103 →
**−18 % sur l'arc seul**, et médiane **−24 %** sur le motif complet entrée/rond-point/sortie.
Un livreur avec 30 ronds-points par jour perd le kilométrage d'un rond-point sur cinq.

**Ce comportement n'est couvert par aucun test** : *tous* les tests de distance de
`LocationFilterTests.swift` utilisent `RouteFixtures.straightLine`. Le seul fixture avec des
virages, `parisToVersailles` (`RouteFixtures.swift:102`), n'est utilisé que par
`RouteCompactorTests.swift:49` — jamais par le filtre.

---

## 9. MOYEN — La calibration documentée n'est pas reproductible

`LocationFilter.swift:63-66` : « alpha/beta: tuned by simulation over 10 noise seeds, a
curved 20 km route and a roundabout fixture. 0.25/0.03 keeps every case inside ±4 % ».

Il n'existe dans le dépôt **ni fixture de rond-point, ni route courbe branchée sur le
filtre**. Ma mesure sur un rond-point de géométrie réaliste donne −18 % à −32 %, ordre de
grandeur au-dessus du « ±4 % » annoncé. La constante peut être bonne, mais l'affirmation qui
la justifie ne repose sur rien de vérifiable dans le code livré.

---

## 10. MOYEN — Livraison par lots en arrière-plan : la staleness jette les fixes

`maxStaleness = 30 s` (`:11`), comparée à `now()` réel (`TripRecorder.swift:229`). Quand iOS
remet une file de positions au réveil de l'app, tout ce qui a plus de 30 s est jeté (`:119`).

30 km à 90 km/h, fixes 1 Hz, livrés par lots :

| Fenêtre de lot | Mesuré | Erreur | Fixes jetés |
|---|---|---|---|
| direct (1 Hz) | 29 913 m | −0,2 % | 0 |
| 30 s | 29 913 m | −0,2 % | 0 |
| 60 s | 29 189 m | −2,6 % | 580 |
| 120 s | 27 691 m | −7,6 % | 890 |
| 300 s | 23 197 m | **−22,6 %** | 1 076 |

Tous les tests livrent chaque fix avec `now == sample.timestamp`
(`LocationFilterTests.swift:15`, `TripRecorderTests.swift:74`) : la règle n'est jamais
exercée dans les conditions où elle mord.

---

## 11. MOYEN — Le `distanceFilter` adaptatif est câblé, mais il ne sert à rien et alimente le §1

Il est **bien câblé** : `CoreLocationProvider.swift:90` appelle `adaptDistanceFilter` pour
chaque échantillon reçu, et celui-ci écrit réellement `manager.distanceFilter` (`:104`).

Mais l'économie est illusoire : à 25 km/h et plus, un récepteur 1 Hz parcourt déjà plus de
10 m par seconde, donc le filtre ne supprime quasiment aucune livraison en roulant. Passer de
10 m à 25 m en dessous de 90 km/h ne change rien non plus (à 90 km/h on parcourt 25 m/s).
`desiredAccuracy` reste `kCLLocationAccuracyBest` en permanence (`:41`), et c'est lui qui
coûte la batterie.

Son seul effet mesurable est **à l'arrêt** — c'est-à-dire exactement là où il crée les
intervalles > 20 s qui déclenchent le défaut §1.

En revanche `pausesLocationUpdatesAutomatically = false` (`:47`) et
`activityType = .automotiveNavigation` (`:42`) sont les bons choix, et le commentaire qui les
justifie (`:44-46`) est exact.

---

## 12. MOYEN — `ActiveTripState` et `LocationPoint` sont dans le schéma CloudKit

`PersistenceController.swift:13` et `:19`. L'entitlement iCloud est absent de ce build
(`App/MileagePocket.entitlements`, commentaire explicite), donc c'est inerte aujourd'hui — et
ce même commentaire annonce qu'il sera rajouté.

Le jour où il l'est : `fetchActiveState()` (`TripRecorder.swift:287-291`) trie par `startedAt`
décroissant **sans aucun filtre d'appareil**. L'iPad de l'utilisateur reprendra donc le trajet
en cours de son iPhone, et chaque fix GPS d'un trajet en cours transitera par iCloud (~3 600
lignes par heure de conduite) avant d'être supprimé à l'arrêt (`:197`).

---

## 13. MOYEN — Géocodage : exactement deux appels, mais aucun rattrapage

**Deux appels par trajet : confirmé et correctement testé.** `TripRecorder.swift:205-210`,
prouvé par `TripRecorderTests.swift:122-138`. L'ordre est bon : le `Trip` est sauvé (`:199`)
**avant** les awaits de géocodage.

En échec (hors réseau, `CLGeocoder` limité), `GeocodingService.address` renvoie `nil`
(`:21-23`) et rien ne le rattrape jamais : grep confirme qu'aucune autre écriture de
`startAddress`/`endAddress` n'existe hors saisie manuelle et mode démo. Un trajet enregistré
en zone blanche porte « — → — » dans le rapport pour toujours (`ReportBuilder.swift:60-61`).
Pour un contrôle fiscal, c'est une ligne sans origine ni destination.

---

## 14. MOYEN — Le rappel « trajet toujours en cours » n'est pas replanifié à la reprise

`AppDependencies.startTrip()` le pose (`:181`), à 3 h (`NotificationService.swift:28`).
`bootstrap()` → `recorder.resumeIfNeeded()` (`:118`) ne le pose pas. Un trajet repris après un
crash n'a plus aucun garde-fou anti-oubli — et c'est justement le trajet le plus susceptible
d'être oublié. Combiné au §1, c'est le scénario qui produit les plus gros écarts.

---

## 15. Ce que les tests prouvent — et ce qu'ils ne prouvent pas

### Prouvent réellement (vérifié par rejeu indépendant)
- `testCleanStraightLineMeasuresItsTrueLength` : 998,9 m pour 1 000 m. Vrai.
- `testNoisyStraightLineStaysWithinFivePercent…` : assertion explicite que le fixture est
  hostile (`:42-45`, somme naïve > 1 200 m — mesurée à 1 749 m). C'est de la bonne discipline :
  sans elle le test passerait sans filtre du tout.
- `testImpliedSpeedBoundaryIsInclusive` : marche la borne ulp par ulp. Excellent, et rare.
- `testSixtySecondTunnelIsBridgedAndItsDistanceCounted` : 1 523 m pontés. Vrai.
- `testTenMinuteGapIsNotBridged…` : 4 941 m. Vrai.
- `testStoppingReverseGeocodesExactlyTwice` : vrai.
- `testActiveTripStateIsRewrittenForEveryAcceptedFix` : vrai, fix par fix.

### Passeraient à l'identique avec le défaut présent
- `testThreeMinutesParkedIsPausedAndAddsNoDistance` (`LocationFilterTests.swift:181`) et
  `testPausingKeepsTheDistanceTheStateCannotCarry` (`TripRecorderTests.swift:259`) utilisent
  `intervalSeconds: 5`. La branche de pontage n'est **jamais** atteinte → le défaut §1 leur
  est structurellement invisible. Ce sont les deux tests censés couvrir les arrêts.
- `testResumeIfNeededPicksUpAnInterruptedTrip` (`:142`) utilise un écart de 700 s → §4 passe.
- Tous les tests de distance sont des lignes droites → §8 et §9 sont hors de portée.
- Toute la livraison se fait à `now == timestamp` → §10 est hors de portée.
- `FakeLocationProvider` (`TripRecorderTests.swift:14-25`) n'a ni notion de
  `allowsBackgroundLocationUpdates`, ni de changement d'autorisation, ni de statut autre que
  `.authorizedAlways` par défaut → §2 et §3 ne sont pas testables dans cette suite telle
  qu'elle est construite.

### Manque au minimum
1. Un arrêt avec des fixes espacés de 25-45 s (le cas réel du `distanceFilter`).
2. Une route avec des virages passée dans le `LocationFilter` — `parisToVersailles` existe
   déjà, il suffit de la brancher.
3. Un rond-point / un virage de rayon 15-20 m.
4. Une reprise d'un `ActiveTripState` vieux de 3 jours.
5. Une livraison par lots (`now` très en avance sur `timestamp`).
6. Un `FakeLocationProvider` qui expose `allowsBackgroundLocationUpdates` et un statut qui
   change **après** `startUpdates()`.

---

## Verdict

La partie « mathématiques de la distance » est solide et honnêtement testée dans son domaine :
ligne droite, bruit gaussien, pontage de tunnel, bornes exactes. Le port indépendant reproduit
tous ses chiffres.

Mais ce domaine est étroit. **Hors de la ligne droite en ciel ouvert, l'app se trompe des deux
côtés à la fois**, silencieusement : elle invente jusqu'à 5 km par heure de stationnement en
positionnement dégradé (§1), elle sous-évalue de 5 à 6 % en ville et jusqu'à 24 % sur un motif
de rond-point (§8), elle jette 9 km sur un tunnel de 5 minutes et une seconde (§6), et elle
n'enregistre tout simplement rien en arrière-plan tant que l'utilisateur n'a pas accordé
« Toujours » ET relancé l'app (§2, §3).

Un chiffre qui peut être trop haut de plusieurs kilomètres et trop bas de 6 % dans le même
trajet, sans que rien à l'écran ne l'indique, n'est pas un chiffre défendable devant un
contrôle fiscal.
