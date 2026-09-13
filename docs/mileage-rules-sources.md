# Mileage Pocket — sources des barèmes kilométriques

Date de consultation de **toutes** les sources ci-dessous : **2026-09-12**.
Chaque taux retenu provient d'une page gouvernementale ou fiscale officielle réellement consultée (WebFetch / WebSearch restreint aux domaines officiels). Aucun chiffre n'a été repris d'un blog, d'un cabinet comptable ou d'un agrégateur.

**12 pays retenus** : FR, US, GB, CA, DE, BE, CH, AU, IE, NL, ES, PT
**1 pays écarté** : IT

Fichiers : `Resources/MileageRules/<ISO>/2026.1.json`
Validateur : `Resources/MileageRules/validate_rules.py`

---

## Sémantique des tranches (`bandMode`)

Chaque `RateScheme` porte un champ `bandMode` :

| Valeur | Sens |
|---|---|
| `marginal` | Chaque tranche de distance annuelle est facturée à son propre taux ; un trajet qui franchit une borne est facturé en deux parties. |
| `whole` | Le barème **sélectionne une seule ligne** selon la distance annuelle totale, puis applique son taux (et sa constante) à **toute** la distance. |

Récapitulatif — la justification par pays figure dans chaque fiche :

| Pays | Tranches | `bandMode` | Preuve |
|---|---|---|---|
| FR | 3 (auto), 3 (2-roues) | **`whole`** | `d` = distance annuelle totale ; continuité exacte à 5 000 km |
| GB | 2 | `marginal` | Exemple chiffré HMRC : `10,000 x 45p plus 2,000 x 25p` |
| CA | 2 | `marginal` | « for each additional kilometre » |
| IE | 4 (auto), 2 (moto) | `marginal` | Exemple chiffré de la circulaire DPER 05/2017 |
| US, DE, NL, ES, PT, CH, BE, AU | 1 | `marginal` | Tranche unique — le champ est sans effet |

---

## FR — France 🇫🇷 · **retenu**

- **URL consultée** : <https://simulateur-ir-ifi.impots.gouv.fr/calcul_impot/2026/aides/frais.htm> (aide du simulateur officiel de l'impôt sur les revenus 2025, campagne déclarative 2026)
- **URL de recoupement** : <https://bofip.impots.gouv.fr/bofip/2185-PGP.html> (BOI-BAREME-000001) et <https://www.service-public.gouv.fr/particuliers/vosdroits/F1989>
- **Année fiscale** : **revenus 2025** (déclarés en 2026). ⚠️ **Aucun barème 2026 n'est publié à ce jour** : le barème kilométrique n'a pas été revalorisé, la dernière publication reste celle du BOI-BAREME-000001. `validFrom` = `2025-01-01`.

### Citations

> « Les tranches relatives à des distances annuelles parcourues à titre professionnel inférieures ou égales à 5 000 km et supérieures à 20 000 km permettent la lecture directe du coût kilométrique. »

> « d représente la distance annuelle parcourue à titre professionnel. »

> « Le barème pour les véhicules 100 % électriques correspond au barème applicable ci-dessous majoré de 20 %. »

### Valeurs retenues — automobiles (`powerBands` par CV)

| Puissance | ≤ 5 000 km | 5 001 – 20 000 km | > 20 000 km |
|---|---|---|---|
| ≤ 3 CV | d × 0,529 | d × 0,316 + 1 065 | d × 0,370 |
| 4 CV | d × 0,606 | d × 0,340 + 1 330 | d × 0,407 |
| 5 CV | d × 0,636 | d × 0,357 + 1 395 | d × 0,427 |
| 6 CV | d × 0,665 | d × 0,374 + 1 457 | d × 0,447 |
| ≥ 7 CV | d × 0,697 | d × 0,394 + 1 515 | d × 0,470 |

### Valeurs retenues — deux-roues (tranches 0 / 3 000 / 6 000 km)

| Catégorie | ≤ 3 000 km | 3 001 – 6 000 km | > 6 000 km |
|---|---|---|---|
| Cyclomoteur (`moped`) | d × 0,315 | d × 0,079 + 711 | d × 0,198 |
| Moto 1–2 CV | d × 0,395 | d × 0,099 + 891 | d × 0,248 |
| Moto 3–5 CV | d × 0,468 | d × 0,082 + 1 158 | d × 0,275 |
| Moto > 5 CV | d × 0,606 | d × 0,079 + 1 583 | d × 0,343 |

### `bandMode` = `whole` — preuve

Deux éléments concordants :

1. **Le texte** : `d` est défini comme « la distance annuelle parcourue à titre professionnel » — pas comme les kilomètres de la tranche. Les tranches extrêmes « permettent la lecture directe du coût kilométrique », c'est-à-dire taux × distance totale.
2. **L'arithmétique** : sous la sémantique `whole`, la borne des 5 000 km est **exactement continue**, ce qui prouve que la constante est un terme de raccordement sur la distance entière :

| CV | 5 000 × taux₁ | 5 000 × taux₂ + constante |
|---|---|---|
| ≤ 3 | 2 645 | 1 580 + 1 065 = **2 645** |
| 4 | 3 030 | 1 700 + 1 330 = **3 030** |
| 5 | 3 180 | 1 785 + 1 395 = **3 180** |
| 6 | 3 325 | 1 870 + 1 457 = 3 327 |
| ≥ 7 | 3 485 | 1 970 + 1 515 = **3 485** |

En `marginal`, le terme constant n'aurait aucun sens (il serait ajouté en plus des 5 000 premiers km déjà facturés).

### Subtilités

- **Repli** (`bands` du scheme, utilisé si la puissance fiscale du véhicule est inconnue) : la ligne **5 CV** pour les automobiles, **3–5 CV** pour les motos. Choix de la bande médiane du barème.
- **Majoration de 20 % pour les véhicules 100 % électriques** : la règle est officielle mais **les taux majorés ne sont publiés nulle part**. Ils n'ont donc **pas** été écrits dans le JSON (règle « ne jamais inventer un taux »), et `electricCar` est absent de `vehicleTypes`. Le schéma n'a pas de champ multiplicateur — à ajouter si on veut couvrir ce cas, sinon l'utilisateur passe en *Custom rate*.
- Les tranches diffèrent entre automobiles (5 000 / 20 000 km) et deux-roues (3 000 / 6 000 km).

---

## US — États-Unis 🇺🇸 · **retenu**

- **URL consultée** : <https://www.irs.gov/tax-professionals/standard-mileage-rates>
- **Année fiscale** : **2026**, second semestre.

### Citation

> Business use: **« 76 cents/mile »** (July 1 – Dec. 31) ; **« 72.5 »** cents/mile (Jan. 1 – June 30).

### Valeurs retenues

- **0,76 USD par mile**, tranche unique, `validFrom` = `2026-07-01`, `validUntil` = `2026-12-31`.

### Subtilités

- ⚠️ **Le taux a changé en cours d'année 2026** : 72,5 ¢ du 1ᵉʳ janvier au 30 juin, puis 76 ¢ à partir du 1ᵉʳ juillet (hausse liée aux prix des carburants). Le fichier porte le taux **en vigueur au 2026-09-12**. Un trajet antérieur au 1ᵉʳ juillet 2026 doit être calculé à 72,5 ¢ — prévoir un second fichier `2026.0.json` si l'app doit gérer l'historique intra-annuel.
- Le barème IRS *standard mileage rate* vise l'**automobile** (car, van, pickup, panel truck) : les motos en sont exclues, d'où `vehicleTypes` = `["car","van","electricCar"]`.
- Autres taux 2026 non retenus (hors périmètre de l'app) : charity 14 ¢/mile, medical & military moving 23,5 ¢/mile.

---

## GB — Royaume-Uni 🇬🇧 · **retenu**

- **URL consultée** : <https://www.gov.uk/government/publications/rates-and-allowances-travel-mileage-and-fuel-allowances/travel-mileage-and-fuel-rates-and-allowances>
- **URL de recoupement (sémantique des tranches)** : <https://www.gov.uk/expenses-and-benefits-business-travel-mileage/rules-for-tax>
- **Année fiscale** : **2026 to 2027** (l'année fiscale britannique démarre le 6 avril). Page mise à jour le 21 mai 2026, rétroactive au 6 avril 2026.

### Citations

> Cars and vans, first 10,000 miles : **« 55p »** — above 10,000 miles : **« 25p »**. Motorcycles : **« 24p »**. Bicycles : **« 20p »**.

> « Your employee travels 12,000 business miles in their car - the approved amount for the year would be £5,000 (10,000 x 45p plus 2,000 x 25p). »

### Valeurs retenues

| Scheme | Tranche | Taux (GBP / mile) |
|---|---|---|
| `car` (car, van, electricCar) | 0 – 10 000 miles | 0.55 |
| `car` | > 10 000 miles | 0.25 |
| `motorcycle` (motorcycle, moped) | toutes | 0.24 |
| `bicycle` | toutes | 0.20 |

### `bandMode` = `marginal` — preuve

L'exemple chiffré de HMRC est sans ambiguïté : `10,000 x 45p plus 2,000 x 25p`. Le taux réduit ne s'applique qu'aux miles **au-delà** de 10 000, pas à la totalité.

### Subtilités

- ⚠️ **Le taux voiture a changé pour la première fois depuis 2011** : 45p → **55p** pour les 10 000 premiers miles, à compter du 6 avril 2026. Le taux au-delà de 10 000 miles reste 25p. L'exemple chiffré cité ci-dessus est encore rédigé avec l'ancien 45p sur gov.uk — il vaut pour la **mécanique**, pas pour le taux.
- Unité : **miles**, pas kilomètres.
- Les taux moto et vélo sont inchangés.
- Non modélisé : le *passenger payment* de 5p/mile par passager transporté.

---

## CA — Canada 🇨🇦 · **retenu**

- **URL consultée** : <https://www.canada.ca/en/department-finance/news/2026/01/government-announces-the-2026-automobile-deduction-limits-and-expense-benefit-rates-for-businesses.html>
- **Année fiscale** : **2026**, en vigueur depuis le 1ᵉʳ janvier 2026.

### Citations

> Provinces : **« 73 cents per kilometre for the first 5,000 kilometres driven, and to 67 cents for each additional kilometre »**

> Territoires : **« 77 cents per kilometre for the first 5,000 kilometres driven, and to 71 cents for each additional kilometre »**

### Valeurs retenues

| Tranche | Taux (CAD / km) |
|---|---|
| 0 – 5 000 km | 0.73 |
| > 5 000 km | 0.67 |

### `bandMode` = `marginal` — preuve

« for **each additional** kilometre » : le second taux ne porte que sur les kilomètres au-delà de 5 000.

### Subtilités

- ⚠️ **Supplément des territoires du Nord** (Yukon, Territoires du Nord-Ouest, Nunavut) : **+4 ¢/km**, soit 77 ¢ puis 71 ¢. **Non modélisé** : le schéma n'a pas de notion de région infranationale, et deux `schemes` couvrant tous deux `car` seraient ambigus à la résolution. À traiter soit par un champ `region`, soit en *Custom rate*.
- Autres taux 2026 mentionnés par la même source et **non retenus** (ils ne servent pas au remboursement de frais kilométriques) : 34 ¢/km pour l'avantage imposable lié à l'usage personnel d'un véhicule de fonction, 31 ¢/km pour les vendeurs/loueurs d'automobiles.

---

## DE — Allemagne 🇩🇪 · **retenu**

- **URLs consultées** :
  - <https://www.gesetze-im-internet.de/estg/__9.html> (§ 9 Abs. 1 Satz 3 Nr. 4a EStG)
  - <https://www.gesetze-im-internet.de/brkg_2005/__5.html> (§ 5 BRKG, *Wegstreckenentschädigung*)
- **Année fiscale** : **2026** (textes en vigueur à la date de consultation).

### Citations

> § 9 Abs. 1 Satz 3 Nr. 4a EStG : « …können die Fahrtkosten mit den pauschalen Kilometersätzen angesetzt werden, die für das jeweils benutzte Beförderungsmittel…als **höchste Wegstreckenentschädigung nach dem Bundesreisekostengesetz** festgesetzt sind. »

> § 5 Abs. 2 BRKG (usage d'un *Kraftwagen* avec intérêt de service reconnu) : « **30 Cent je Kilometer** zurückgelegter Strecke. »

> § 5 Abs. 1 BRKG (cas général) : « 20 Cent je Kilometer zurückgelegter Strecke, höchstens jedoch 130 Euro. »

### Valeurs retenues

- **0,30 EUR par kilomètre**, tranche unique, voiture / utilitaire / voiture électrique.

### Subtilités

- La chaîne de raisonnement est purement textuelle et vérifiable : l'EStG renvoie à la **plus haute** *Wegstreckenentschädigung* du BRKG, et celle-ci est de **30 ¢** (§ 5 Abs. 2). D'où 0,30 €/km.
- ⚠️ **Motos non incluses.** La pratique fiscale allemande retient 0,20 €/km pour les « andere motorbetriebene Fahrzeuge », mais **ce chiffre n'a pas pu être confirmé sur une page officielle accessible** : le site du BMF (`bundesfinanzministerium.de`, sous-domaines `ao.`/`esth.`/`erbsth.`/`lsth.`) est protégé par un pare-feu Radware qui renvoie une page de vérification de navigateur. Les motos passeront donc en *Custom rate* côté app.
- ⚠️ **Ne pas confondre avec l'`Entfernungspauschale`** (trajet domicile ↔ lieu de travail) : 0,38 €/km **de distance à sens unique** depuis le 1ᵉʳ janvier 2026, plafonnée à 4 500 € (§ 9 Abs. 1 Satz 3 Nr. 4 EStG, texte consulté à la même URL). C'est un régime différent, non modélisé ici.

---

## BE — Belgique 🇧🇪 · **retenu**

- **URL consultée** : <https://bosa.belgium.be/fr/regulations/circulaire-ndeg-768-du-29-juin-2026-indemnite-kilometrique>
- **Période** : **1ᵉʳ juillet 2026 – 30 septembre 2026**.

### Citation

> Circulaire n° 768 du 29 juin 2026 : l'indemnité kilométrique est fixée à **0,4440 €** du kilomètre, du 1ᵉʳ juillet 2026 au 30 septembre 2026.

### Valeurs retenues

- **0,4440 EUR par kilomètre**, tranche unique. `validFrom` = `2026-07-01`, `validUntil` = `2026-09-30`.

### Subtilités

- ⚠️ **Révision trimestrielle.** Le montant est recalculé chaque trimestre (80 % indice santé lissé + 20 % prix des carburants). Le fichier **expire le 30 septembre 2026** — il faudra publier `2026.2.json` avec la circulaire du trimestre suivant. C'est le seul pays de la liste dont le barème a une date de fin connue à l'avance.
- Il s'agit de l'indemnité kilométrique forfaitaire du secteur public fédéral, qui sert de référence admise par l'administration fiscale pour les remboursements de frais de déplacement professionnels.

---

## CH — Suisse 🇨🇭 · **retenu**

- **URL consultée** : <https://www.admin.ch/de/newnsb/VzaAUrhkPx2EPde4a6e3O> — communiqué du Département fédéral des finances « EFD passt Steuertarife an Teuerung an », 11 septembre 2025
- **URL de recoupement** : <https://www.estv2.admin.ch/stp/sm/fahrkosten-de-fr.pdf> (Steuermäppchen AFC, période fiscale 2025 — donne encore 70 ct.)
- **Année fiscale** : **2026**.

### Citation

> « Der Abzug wird auf **75 Rappen pro Kilometer** erhöht (bisher 70 Rappen). » — applicable dès la période fiscale 2026, par modification de la *Berufskostenverordnung*.

### Valeurs retenues

- **0,75 CHF par kilomètre**, tranche unique, voiture.

### Subtilités

- ⚠️ **Plafond annuel de 3 200 CHF** pour l'impôt fédéral direct sur les frais de déplacement domicile ↔ travail (art. 26 al. 1 let. a LIFD, cité dans le Steuermäppchen de l'AFC). **Modélisé** depuis le 2026-09-13 via `annualCapAmount` sur le pack.
- ⚠️ **Motos non incluses.** Le brochure AFC *période fiscale 2025* donne 40 ct./km pour une moto à plaque blanche et un forfait annuel de 700 CHF pour vélo / cyclomoteur / moto à plaque jaune, mais le communiqué de 2026 ne mentionne **que** la voiture et ne reconduit pas explicitement ces montants. Ils ne sont donc pas repris.
- Le site `fedlex.admin.ch` (texte consolidé de la *Berufskostenverordnung*) exige JavaScript et n'a pas pu être lu directement ; le communiqué officiel du DFF fait foi.
- Les barèmes cantonaux diffèrent du fédéral (jusqu'à 4 paliers de distance dans certains cantons) — hors périmètre.

---

## AU — Australie 🇦🇺 · **retenu**

- **URL consultée** : <https://www.legislation.gov.au/F2026L00785/asmade/2026-06-23/text/original/epub/OEBPS/document_1/document_1.html> — *Income Tax Assessment (Cents per Kilometre Deduction Rate for Car Expenses) Determination 2026* (F2026L00785)
- **Année fiscale** : **2026-27** (l'année fiscale australienne démarre le 1ᵉʳ juillet).

### Citation

> « For the purposes of subsection 28-25(1) of the Act, the rate of cents per kilometre for cars for the income year commencing on 1 July 2026 is **91 cents per kilometre**. »

### Valeurs retenues

- **0,91 AUD par kilomètre**, tranche unique. `validFrom` = `2026-07-01`, `validUntil` = `2027-06-30`.

### Subtilités

- ⚠️ **Plafond de 5 000 km par véhicule et par an** (méthode *cents per kilometre*, ITAA 1997 s. 28-25). **Modélisé** depuis le 2026-09-13 via `annualCapDistance` sur le scheme : au-delà, la méthode ne rapporte rien. L'année australienne ouvre le 1er juillet (`taxYearStart`).
- Le taux 2026-27 de 91 ¢ intègre un relèvement exceptionnel et temporaire de 2 ¢ par rapport au taux de base de 89 ¢ : il faudra re-vérifier le taux 2027-28.
- `ato.gov.au` renvoie systématiquement un HTTP 403 aux requêtes automatisées ; le Federal Register of Legislation (source primaire) a servi de substitut.

---

## IE — Irlande 🇮🇪 · **retenu**

- **URLs consultées** :
  - <https://www.revenue.ie/en/employing-people/employee-expenses/travel-and-subsistence/civil-service-rates.aspx>
  - <https://www.revenue.ie/en/tax-professionals/tdm/income-tax-capital-gains-tax-corporation-tax/part-05/05-01-06.pdf> (Tax and Duty Manual Part 05-01-06, annexe 1 B/D/E)
  - <https://circulars.gov.ie/pdf/circular/per/2017/05.pdf> (circulaire DPER 05/2017, mécanique des bandes)
- **Année fiscale** : taux **en vigueur** — automobiles depuis le **1ᵉʳ septembre 2022**, motos depuis le **5 mars 2009**, vélos depuis le **1ᵉʳ avril 2017**. Aucun barème plus récent n'est publié.

### Citations

> « Band 1: 0 – 1,500 km 41.80 cent 43.40 cent 51.82 cent » (TDM Part 05-01-06, annexe 1 B)

> « Claims made for journeys undertaken in electric vehicles should use the rates applicable to the middle category of 1,201cc to 1,500cc. »

> Circulaire DPER 05/2017 : « an officer … who had claimed 1,400km on 1st April 2017 would then move to the new Band 1 and receive 39.86 cent per kilometre. Once they have driven a further 100km, they would then move to Band 2 and receive 73.21 cent per kilometre. »

### Valeurs retenues — automobiles (`powerBands` par cylindrée en cm³)

| Bande | ≤ 1200 cc | 1201–1500 cc | ≥ 1501 cc |
|---|---|---|---|
| Band 1 : 0 – 1 500 km | 0,4180 | 0,4340 | 0,5182 |
| Band 2 : 1 501 – 5 500 km | 0,7264 | 0,7918 | 0,9063 |
| Band 3 : 5 501 – 25 000 km | 0,3178 | 0,3179 | 0,3922 |
| Band 4 : > 25 000 km | 0,2056 | 0,2385 | 0,2587 |

### Valeurs retenues — motos (`powerBands` par cylindrée)

| Bande | ≤ 150 cc | 151–250 cc | 251–600 cc | ≥ 601 cc |
|---|---|---|---|---|
| 0 – 6 437 km | 0,1448 | 0,2010 | 0,2372 | 0,2859 |
| > 6 437 km | 0,0937 | 0,1331 | 0,1529 | 0,1760 |

### Valeurs retenues — vélos

- **0,08 EUR par kilomètre**, tranche unique.

### `bandMode` = `marginal` — preuve

L'exemple chiffré de la circulaire DPER 05/2017 est décisif : le kilométrage **s'accumule** sur l'année, et une fois les 1 500 km franchis l'agent « passe en Band 2 » et perçoit le taux de la Band 2 **pour les kilomètres suivants**. Le TDM confirme la notion de compteur annuel : « business travel from 1 January 2022 will … count towards **aggregated mileage for the year** ».

Contre-preuve arithmétique : le taux de la Band 2 (79,18 ¢) est **supérieur** à celui de la Band 1 (43,40 ¢). En `whole`, passer de 1 500 à 1 501 km ferait bondir le remboursement de 651 € à 1 188 € — absurde. En `marginal`, le total est continu, la Band 2 servant à récupérer les coûts fixes.

### Subtilités

- **`minPower` / `maxPower` représentent ici des cm³ de cylindrée**, pas des chevaux fiscaux. À documenter côté app : le même champ porte des CV en France et des cm³ en Irlande.
- **Repli** (`bands` du scheme) : la bande **1201–1500 cc** pour les automobiles — c'est aussi, d'après Revenue, celle à utiliser pour les **véhicules électriques**, ce qui en fait le repli le plus défendable. Pour les motos, repli sur **251–600 cc**.
- Les hybrides se déclarent au taux de la cylindrée thermique équivalente.
- La borne des 6 437 km du barème moto est la conversion de 4 000 miles.
- Non modélisé : les *reduced motor travel rates* (21,23 / 23,80 / 25,96 ¢) applicables aux déplacements liés à l'emploi mais non à l'exercice des fonctions (concours, formations, conférences).

---

## NL — Pays-Bas 🇳🇱 · **retenu**

- **URL consultée** : <https://www.belastingdienst.nl/wps/wcm/connect/bldcontentnl/belastingdienst/zakelijk/winst/inkomstenbelasting/veranderingen-inkomstenbelasting-2026/zakelijk-gebruik-privevervoermiddel-2026>
- **Année fiscale** : **2026**.

### Citations

> « Gebruikt u in uw onderneming een vervoermiddel dat uw eigendom is of dat u privé huurt, bijvoorbeeld een **auto, motor of een fiets**? »

> « Dan mag u in 2026 voor de zakelijke ritten **€ 0,25 per kilometer** van uw winst aftrekken. »

### Valeurs retenues

- **0,25 EUR par kilomètre**, tranche unique, pour voiture, utilitaire, voiture électrique, moto, cyclomoteur et vélo.

### Subtilités

- ⚠️ **Hausse rétroactive** : le montant passe de 0,23 € à 0,25 €/km, avec effet rétroactif au 1ᵉʳ janvier 2026.
- Le même montant est le plafond de l'indemnité kilométrique non imposable qu'un employeur peut verser (*onbelaste reiskostenvergoeding*) et le montant déductible du bénéfice pour un indépendant.
- Tous frais compris (carburant, assurance, péage, stationnement) : rien ne se déduit en plus.

---

## ES — Espagne 🇪🇸 · **retenu**

- **URLs consultées** :
  - <https://www.boe.es/buscar/doc.php?id=BOE-A-2023-16461> — Orden HFP/792/2023, de 12 de julio
  - <https://sede.agenciatributaria.gob.es/Sede/eu_es/ayuda/manuales-videos-folletos/manuales-practicos/irpf-2025/c03-rendimientos-trabajo/consideracion-fiscal-dietas-asignaciones-gastos-viaje/gastos-locomocion.html> — Manual práctico Renta 2025 (AEAT)
- **Année fiscale** : montant **toujours en vigueur**, entré en application le 17 juillet 2023 et confirmé par le manuel AEAT de l'exercice 2025. Aucune révision postérieure publiée.

### Citations

> Orden HFP/792/2023, article unique, point 1 : « se excluirá la cantidad que resulte de multiplicar **0,26 euros por el número de kilómetros recorridos** ».

> Manual AEAT Renta 2025 : « **0,26 euros por kilómetro recorrido** » plus péages et stationnement justifiés.

### Valeurs retenues

- **0,26 EUR par kilomètre**, tranche unique.

### Subtilités

- Montant *exceptuado de gravamen* au titre de l'art. 9 du Reglamento del IRPF : c'est le plafond au-delà duquel l'indemnité devient imposable, et non un barème de déduction à tranches.
- **Péages et stationnement se remboursent en sus**, sur justificatif — à prévoir comme frais annexes dans l'app.
- Le montant est passé de 0,19 € à 0,26 € en juillet 2023 ; c'est bien 0,26 € qui reste applicable.

---

## PT — Portugal 🇵🇹 · **retenu**

- **URL consultée** : <https://www.dgaep.gov.pt/index.cfm?OBJID=7EC1A7C9-E992-49F9-8801-08D5956C69FE> — DGAEP (Direção-Geral da Administração e do Emprego Público), tableau des *subsídios de transporte*
- **Année fiscale** : **2026**, valeur en vigueur au 2026-09-12, fixée par la **Portaria n.º 51-B/2026/1, de 30 de janeiro**.

### Citation

> *Viatura própria* (véhicule personnel) : **0,40 € par kilomètre**, montant en vigueur au titre de la Portaria n.º 51-B/2026/1 du 30 janvier 2026, qui actualise les tableaux issus de la Portaria n.º 1553-C/2008 et de la Portaria n.º 107-A/2023.

### Valeurs retenues

- **0,40 EUR par kilomètre**, tranche unique. `validFrom` = `2026-01-30` (date de la Portaria).

### Subtilités

- ⚠️ `validFrom` porte la **date de la Portaria**, pas une date d'effet vérifiée : le texte intégral de la Portaria n.º 51-B/2026/1 n'a pas pu être lu (les URL `dre.pt` / `diariodarepublica.pt` renvoient 301 puis un corps vide, et la page de détail `dgaep.gov.pt/stap/…` est en 404). Seul le tableau récapitulatif de la DGAEP — organisme gouvernemental compétent — a pu être consulté, et il présente 0,40 €/km comme la valeur courante.
- Il s'agit du régime des déplacements en service dans l'administration publique, qui sert de référence au plafond non imposable dans le privé.
- Motos : aucune valeur confirmée sur la page consultée, donc non modélisées.

---

## IT — Italie 🇮🇹 · ❌ **ÉCARTÉ**

- **URLs consultées** :
  - <https://www.gazzettaufficiale.it/eli/id/2025/12/23/25A06822/SG> — publication des tabelle ACI, *Gazzetta Ufficiale* Serie Generale n. 297 du 23/12/2025
  - <https://www.aci.it/i-servizi/servizi-online/costi-chilometrici.html> et <https://costikm.aci.it/home>
- **Année fiscale** : tabelle ACI 2026, publiées le 23 décembre 2025.

### Raison de l'exclusion

**Barème par modèle de véhicule, inexploitable dans notre schéma — et non consultable sans authentification.**

Trois blocages cumulés :

1. **Granularité incompatible.** L'art. 51, comma 4, lettera a) du TUIR renvoie aux « tabelle nazionali dei costi chilometrici di esercizio di autovetture e motocicli elaborate dall'ACI ». Le coût au kilomètre y est défini **par marque, modèle et motorisation** — plusieurs milliers de lignes — et non par puissance fiscale ou par tranche de distance. Notre schéma (`powerBands` + `bands`) ne peut pas représenter un index par modèle, et aucun taux unique national n'existe.
2. **Actualisation hebdomadaire.** L'ACI indique que les montants sont mis à jour **chaque semaine** avec les prix des carburants. Un fichier de règles versionné annuellement serait faux en permanence.
3. **Accès fermé.** La consultation des montants en euro/km passe par le service en ligne de l'ACI, qui exige une authentification **SPID, CIE, CNS ou eIDAS**. Aucun chiffre officiel n'a donc pu être lu.

**Conséquence pour l'app** : l'Italie bascule en **Custom rate**. L'utilisateur saisit le coût au kilomètre de son propre véhicule, relevé sur le service ACI. C'est d'ailleurs la seule méthode correcte pour l'Italie.

---

## Récapitulatif des limites du schéma rencontrées

Éléments officiels qui n'ont **pas** pu être encodés dans le format actuel, à traiter en *Custom rate* ou par une évolution du schéma :

| Pays | Élément | Manque dans le schéma |
|---|---|---|
| FR | Majoration de +20 % pour véhicule 100 % électrique | champ multiplicateur, ou taux dérivés (non publiés officiellement) |
| CA | Supplément de 4 ¢/km des territoires du Nord | notion de région infranationale |
| AU | Plafond de 5 000 km/an par véhicule | champ plafond de distance |
| CH | Plafond annuel de 3 200 CHF (IFD) | champ plafond de montant |
| US | Taux différent avant le 1ᵉʳ juillet 2026 (72,5 ¢) | un seul intervalle de validité par fichier |
| IT | Barème par modèle de véhicule, actualisé chaque semaine | — (hors de portée par nature) |

## Limites connues des barèmes livrés

Deux écarts sont documentés ici plutôt que codés, parce que les coder à moitié produirait un
montant faux présenté comme officiel — ce qui est pire que l'écart lui-même.

### Canada — territoires du Nord (+4 ¢/km)

L'ARC accorde 4 cents de plus par kilomètre au Yukon, dans les Territoires du Nord-Ouest et au
Nunavut. Le pack `CA` ne porte qu'un barème national : l'app applique donc **0,73 / 0,67**
partout, ce qui **sous-estime** l'indemnité d'un résident de ces trois territoires.

Le modèle de pack n'a pas de dimension régionale, et en ajouter une correctement suppose : un
champ région dans le pack, un sélecteur en Réglages visible uniquement pour les pays concernés,
la région figée sur le trajet pour que le rapport reste reproductible, et des tests sur chaque
combinaison. C'est une fonctionnalité, pas un correctif, et l'appliquer à la hâte sur un chemin
qui produit de l'argent serait moins bien que l'écart actuel.

**Contournement dans l'app** : Réglages → Calcul → taux personnalisé, à 0,77 / 0,71. Le rapport
indique alors explicitement « barème configuré par vous, pas un barème officiel publié », ce qui
est la mention correcte dans ce cas.

### Irlande — taux réduits

Revenue publie, à côté du barème « civil service », des **taux réduits** applicables dans des
circonstances précises (déplacement non effectué dans le cadre normal des fonctions, rappel au
travail…). L'app applique toujours le barème standard.

Le déclencheur est juridique, pas géométrique : rien dans un trajet GPS ne permet de savoir
qu'il relève du taux réduit. Choisir automatiquement serait produire une déclaration fausse.

**Contournement dans l'app** : taux personnalisé pour les trajets concernés.

---

## Sources

- [IRS — Standard mileage rates](https://www.irs.gov/tax-professionals/standard-mileage-rates)
- [GOV.UK — Travel: mileage and fuel rates and allowances](https://www.gov.uk/government/publications/rates-and-allowances-travel-mileage-and-fuel-allowances/travel-mileage-and-fuel-rates-and-allowances)
- [GOV.UK — Business travel mileage: rules for tax](https://www.gov.uk/expenses-and-benefits-business-travel-mileage/rules-for-tax)
- [Canada.ca — 2026 automobile deduction limits and expense benefit rates](https://www.canada.ca/en/department-finance/news/2026/01/government-announces-the-2026-automobile-deduction-limits-and-expense-benefit-rates-for-businesses.html)
- [impots.gouv.fr — Aide du simulateur, frais kilométriques (revenus 2025)](https://simulateur-ir-ifi.impots.gouv.fr/calcul_impot/2026/aides/frais.htm)
- [BOFiP — BOI-BAREME-000001](https://bofip.impots.gouv.fr/bofip/2185-PGP.html)
- [service-public.gouv.fr — Frais de transport, fiche F1989](https://www.service-public.gouv.fr/particuliers/vosdroits/F1989)
- [gesetze-im-internet.de — § 9 EStG](https://www.gesetze-im-internet.de/estg/__9.html)
- [gesetze-im-internet.de — § 5 BRKG](https://www.gesetze-im-internet.de/brkg_2005/__5.html)
- [SPF BOSA — Circulaire n° 768 du 29 juin 2026, indemnité kilométrique](https://bosa.belgium.be/fr/regulations/circulaire-ndeg-768-du-29-juin-2026-indemnite-kilometrique)
- [admin.ch — EFD passt Steuertarife an Teuerung an (11.09.2025)](https://www.admin.ch/de/newnsb/VzaAUrhkPx2EPde4a6e3O)
- [AFC/ESTV — Steuermäppchen, Abzug für Fahrkosten](https://www.estv2.admin.ch/stp/sm/fahrkosten-de-fr.pdf)
- [Federal Register of Legislation — Determination 2026 (F2026L00785)](https://www.legislation.gov.au/F2026L00785/asmade)
- [Revenue.ie — Civil service rates](https://www.revenue.ie/en/employing-people/employee-expenses/travel-and-subsistence/civil-service-rates.aspx)
- [Revenue.ie — Tax and Duty Manual Part 05-01-06](https://www.revenue.ie/en/tax-professionals/tdm/income-tax-capital-gains-tax-corporation-tax/part-05/05-01-06.pdf)
- [circulars.gov.ie — DPER Circular 05/2017: Motor Travel Rates](https://circulars.gov.ie/pdf/circular/per/2017/05.pdf)
- [Belastingdienst — Zakelijk gebruik privévervoermiddel 2026](https://www.belastingdienst.nl/wps/wcm/connect/bldcontentnl/belastingdienst/zakelijk/winst/inkomstenbelasting/veranderingen-inkomstenbelasting-2026/zakelijk-gebruik-privevervoermiddel-2026)
- [BOE — Orden HFP/792/2023, de 12 de julio](https://www.boe.es/buscar/doc.php?id=BOE-A-2023-16461)
- [AEAT — Manual práctico Renta 2025, gastos de locomoción](https://sede.agenciatributaria.gob.es/Sede/eu_es/ayuda/manuales-videos-folletos/manuales-practicos/irpf-2025/c03-rendimientos-trabajo/consideracion-fiscal-dietas-asignaciones-gastos-viaje/gastos-locomocion.html)
- [DGAEP — Subsídios de transporte](https://www.dgaep.gov.pt/index.cfm?OBJID=7EC1A7C9-E992-49F9-8801-08D5956C69FE)
- [Gazzetta Ufficiale — Tabelle ACI 2026 (25A06822)](https://www.gazzettaufficiale.it/eli/id/2025/12/23/25A06822/SG)
- [ACI — Costi chilometrici](https://www.aci.it/i-servizi/servizi-online/costi-chilometrici.html)
