# Audit Mileage Pocket — 2026-09-13

Six audits indépendants, en lecture seule, sur des périmètres disjoints. ~4 000 lignes.

| Rapport | Périmètre | Verdict |
|---|---|---|
| [conformite.md](conformite.md) | cahier des charges V1 | suivi en arrière-plan et iCloud non tenus ; 8 priorités à moitié |
| [gps.md](gps.md) | distance et suivi | **non défendable** : +2,6 km/30 min à l'arrêt, −24 % en rond-point |
| [fiscal.md](fiscal.md) | barèmes et rapports | **non** : arithmétique juste, alimentée avec le mauvais barème |
| [abonnement.md](abonnement.md) | accès et paywall | ne tient pas : deux fuites de premium, abonné bloqué hors-ligne |
| [donnees.md](donnees.md) | données et cas limites | 5 des 16 cas du §39 réellement traités |
| [tests.md](tests.md) | valeur des tests | 8 tests ne peuvent pas échouer ; câblage à 0 % |

## Ce que les six confirment ensemble

Le socle calculatoire est bon et prouvé : filtre de distance, interpréteur de barèmes,
compaction de tracé, politique d'accès, regroupement par date. L'arithmétique a été
recalculée à la main, au centime.

Ce qui ne l'est pas, c'est **le câblage entre ce socle et l'utilisateur** : quel barème
est choisi, quel véhicule, quelle unité, quelle autorisation, quel cumul annuel. C'est
là que vivent tous les défauts graves, et c'est exactement la zone que les tests ne
couvrent pas (`AppDependencies`, 330 lignes, 0 %).

Un moteur prouvé qu'on ne prouve jamais branché.
