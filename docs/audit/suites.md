# Suites de l'audit — ce qui a été traité, ce qui ne l'a pas été

Mise à jour du 2026-09-14. À lire avec [README.md](README.md), qui liste les constats.

## Traité

### Intégrité des données

| Constat | Correctif | Preuve |
|---|---|---|
| Le repli d'ouverture du store passait en mémoire **en silence** : l'app paraît neuve, l'utilisateur enregistre une semaine de trajets, tout disparaît au lancement suivant | `PersistenceController.openStore` rend un `StoreHealth` ; un store illisible est **mis de côté** (jamais supprimé) et une alerte le dit | `StoreRecoveryTests` |
| `ActiveTripState` se synchronise par CloudKit sans filtre d'appareil : l'iPad reprenait le trajet en cours de l'iPhone, deux appareils écrivant sous le même id | `deviceID` sur la ligne, lecture et purge limitées à cet appareil | `testATripInProgressOnAnotherDeviceIsLeftAlone`, mutation prouvée |
| Une ligne vieille de plusieurs jours était **reprise** : l'écart entre son dernier point et la position actuelle s'ajoutait à la distance | au-delà de 6 h, le trajet est **clôturé à son dernier point** et conservé | `testATripTooOldToStillBeRunningIsClosedRatherThanResumed`, mutation prouvée |
| `stop()` qui échoue coupait le flux GPS, laissait l'état à `.recording` et l'écran de conduite figé | `rollback()` + réarmement de l'écoute + alerte ; la Live Activity et les rappels restent en place puisque le trajet continue | revue de code |
| Une Live Activity survivait à la fermeture de l'app et n'était jamais réadoptée ; le START suivant en créait une **seconde** | `TripActivityController.adopt(isRecording:)` au lancement | revue de code |
| Le widget affichait le placeholder (486 km) hors contexte d'aperçu | `context.isPreview` | revue de code |

### GPS

| Constat | Correctif | Preuve |
|---|---|---|
| **La péremption s'appliquait à chaque point.** iOS livre les positions **par lots** quand l'app est en arrière-plan : tous les points du lot sauf le dernier ont plus de 30 s en arrivant. Mesuré : **623 m retenus sur 9 975 m réels** | la règle ne vaut plus que pour le **premier** point (le point en cache de CoreLocation, la faute qu'elle vise) | `testABatchDeliveredLateStillCountsEveryFixInIt`, mutation prouvée |
| Un silence trop long n'était pas comblé — c'est correct — mais **rien ne le disait** : le conducteur voit un trajet court sans savoir pourquoi | `unbridgedGapSeconds` porté jusqu'au trajet et affiché, avec renvoi vers l'édition de distance | `testTenMinuteGapIsNotBridged…`, mutation prouvée |
| Aucun filet si iOS termine l'app en pleine conduite | `startMonitoringSignificantLocationChanges` armé pendant le trajet sous « Toujours », et `bootstrap()` déplacé dans l'`init` de l'app pour qu'un lancement **en arrière-plan** reprenne le trajet | revue de code |

### Langue

| Constat | Correctif | Preuve |
|---|---|---|
| `NSLocalizedString` lit `Bundle.main`, donc la langue **de l'appareil** : notifications, libellé d'abonnement et **PDF exporté** restaient dans la langue système pendant que le reste de l'app changeait | `L` et `LocalizedStrings` résolvent dans la langue choisie ; 24 appels convertis | `testLookupsFollowTheInAppLanguage…`, mutation prouvée |
| Le PDF — le document remis au comptable — était **écrit en anglais en dur** | 29 clés, six langues, résolues dans la langue du profil de rapport | `testTheDocumentLanguageIsPinned…` |
| Les deux autorisations de localisation (`Info.plist`) n'étaient traduites dans aucune langue | `Resources/InfoPlist.xcstrings` | `testTheLocationPromptsAreTranslated…`, mutation prouvée |

### Accessibilité

| Constat | Correctif | Preuve |
|---|---|---|
| 64 tailles de police figées : Dynamic Type ne faisait **rien** | `scaledFont(_:relativeTo:…)` sur `@ScaledMetric`, plafonné là où le cadre ne peut pas grandir | revue de code |
| L'ambre de marque mesurait **3,05:1** sur blanc, et servait de couleur de **texte** partout | ambre approfondi (5,14:1), vert « business » approfondi (5,31:1) | `ContrastTests` |
| **Blanc sur l'ambre sombre : 2,12:1** — le bouton START était le texte le moins lisible de l'app | `Theme.onSignal`, encre sombre sur ambre clair (8,66:1) | `ContrastTests` |
| Blanc sur le rouge système : 3,55:1 | `Theme.stop`, rouge fixe (6,10:1) | `ContrastTests` |

### Manques fonctionnels

- **Clients et projets** : les clients naissaient en tapant un nom et étaient ensuite hors d'atteinte — une faute de frappe devenait un second client sur chaque rapport. Les projets existaient dans le modèle, sur le trajet, et **aucun écran ne pouvait en poser un**. Écran de gestion (renommer, supprimer sans perdre les trajets), et champ projet sur le récapitulatif.
- **Rapports sur les périodes passées** : l'écran ne montrait que la période **en cours** — celle que personne n'exporte, puisqu'une note de frais se dépose après coup.
- **Correction d'un trajet** : seule la distance était modifiable. Le classement, le motif, le véhicule, le client et le projet le sont désormais, avec recalcul de l'année au barème de la date du trajet.
- **Notifications** : décidées une fois à l'accueil, jamais réglables ensuite. Section dédiée, deux interrupteurs.
- **Éditeur de véhicule** : aucun bouton Annuler, et le véhicule était inséré **avant** la validation — abandonner la feuille laissait une voiture sans nom, par défaut.

### Valeur des tests

Les cinq tautologies confirmées par l'audit sont mortes, chacune avec la mutation qui les tuait :

- le « budget de taps » comptait une variable du test lui-même → il vérifie maintenant que **rien ne s'interpose** (dont le paywall au START) ;
- le comptage de visites testait `+=` de Swift → il passe par `finishTrip` ;
- le test de pluriel comparait deux chaînes qui diffèrent toujours → il fige les deux formes ;
- la borne « whole band » utilisait un barème **continu à la borne**, donc invisible → barème discontinu ;
- la borne de rayon sondait 149,83 m et 150,83 m (deux rayons terrestres différents) → l'offset est résolu dans le mètre du matcher.

Ajoutés : `RulePackUpdateTests` — le canal de mise à jour des barèmes signés avait **0 %** de couverture. La mutation « ne pas vérifier la signature » fait passer un taux forgé à **9,99** jusqu'au store ; le test l'attrape.

Corrigés aussi : le clamp d'horloge reculée (le test assertait `≤ 4`, c'est-à-dire exactement ce que le code non protégé rendait), le `if` sans `else` qui sautait en silence la seule vérification que `RawKeyUITests` existe pour faire, les trois paliers irlandais vérifiés par aucune valeur, et le budget de taille de tracé fixé au double de la réalité.

## Non traité, et pourquoi

- **Canada, territoires du Nord (+4 ¢/km)** et **Irlande, taux réduits** : voir [mileage-rules-sources.md](../mileage-rules-sources.md#limites-connues-des-barèmes-livrés). Les deux demandent une dimension que le modèle de pack n'a pas (région) ou un déclencheur qu'un trajet GPS ne porte pas (circonstance juridique). Les coder à moitié produirait un montant faux présenté comme officiel. Contournement documenté : taux personnalisé, que le rapport signale explicitement comme non officiel.
- **Plancher de bruit et α/β du filtre** : l'audit chiffre −6 % en ville et −18 à −24 % en rond-point. Les constantes actuelles ont été calibrées par simulation et le compromis est documenté dans le code ; les rejouer sans banc de mesure dédié reviendrait à échanger une erreur connue contre une erreur inconnue.
- **Seuil de tunnel à 300 s** : conservé. Combler dix minutes de silence en ligne droite inventerait des kilomètres sur un document fiscal. Le silence est désormais **déclaré** au conducteur, qui peut corriger la distance lui-même.
