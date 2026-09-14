# CarPlay Driving Task — demande d'entitlement

Apple accorde `com.apple.developer.carplay-driving-task` **au compte**, à la main, via
<https://developer.apple.com/contact/carplay/>. Il n'y a pas d'API : le formulaire est
derrière une authentification Apple Developer et doit être soumis par le titulaire du compte.

> Le dossier Dashcam disait « par app ». C'est faux : le mail d'Apple dit *« assigned to your
> account, and you can now configure this capability for eligible apps »*, et la capability
> apparaît ensuite sur tous les App ID du compte, à cocher un par un.

**Demandée et accordée le 2026-09-14**, une vingtaine de minutes plus tard. Activée dans la
foulée sur `Mileage.lno.company`.

## Activer sur un App ID

CarPlay est une **managed capability** : absente de l'énumération acceptée par
`POST /v1/bundleIdCapabilities`, elle ne s'active que dans le portail — Identifiers → l'App
ID → *CarPlay Driving Task App* → Save → Confirm. L'API la **lit** ensuite très bien
(`CARPLAY_DRIVING_TASK`), ce qui est ce que vérifie le guetteur.

⚠️ Cocher une capability **invalide les profils de provisionnement** qui portent cet App ID.
Et `-allowProvisioningUpdates` **ne sauve pas** un profil nommé par
`PROVISIONING_PROFILE_SPECIFIER` en signature manuelle : xcodebuild lit le profil périmé et
échoue avec

> Provisioning profile "MileagePocket AppStore" doesn't include the CarPlay Driving Task App
> capability. […] needs to be assigned to your team and bundle identifier by Apple

ce qui se lit comme « l'entitlement n'a pas été accordé » alors qu'il l'est. L'API ne sait pas
*mettre à jour* un profil : il faut le supprimer et le recréer sous le même nom.

```bash
python3 tools/regenerate_profile.py "MileagePocket AppStore"
```

L'outil réutilise le même App ID et le même certificat, réinstalle le `.mobileprovision` dans
les deux dossiers que lit la chaîne, et **relit** le contenu du profil pour confirmer qu'il
porte `carplay-driving-task` — un POST qui répond 201 ne prouve pas ce qu'il y a dedans.

À refaire à chaque fois qu'une capability change sur `Mileage.lno.company`.

⚠️ **Le volet Driving Task ne demande aucune description, ni même le nom de l'app.** Les
champs « Tell us about your app » et « What specific CarPlay features do you plan to
implement? », ainsi que les téléversements de captures, n'existent que pour la catégorie
**Navigation** : ils sont dans le DOM mais en `display:none` partout ailleurs. La demande se
résume donc à choisir la catégorie et à accepter le **CarPlay Entitlement Addendum**, un
avenant à l'Apple Developer Program License Agreement — déjà accepté le 2026-09-12 pour le
même compte, à l'occasion de la demande Dashcam Pocket.

Le dossier ci-dessous n'a donc pas servi au formulaire. Il existe pour être servi tel quel
si Apple demande des précisions par mail.

## Identité

| Champ | Valeur |
|---|---|
| Nom de l'app | Mileage Pocket |
| Bundle ID | `Mileage.lno.company` |
| App Store ID | 6811426601 (pas encore publiée — TestFlight) |
| Team ID | 2E6D4Q69QB |
| Catégorie CarPlay | **Driving Task** |

## Ce qu'il faut répondre

> Mileage Pocket is a mileage log. It records a business trip by GPS and prices it with the
> official mileage rate published by the driver's own tax authority, so the drive can be
> claimed as an expense or a deduction. It has no navigation, no map guidance and no route
> planning, and it never competes for the screen the driver uses to navigate.
>
> The CarPlay interface is a single `CPInformationTemplate` showing whether a trip is
> recording, the distance so far and the elapsed time, with at most two `CPTextButton`s:
> Start and Stop. Nothing else — no list to browse, no report to read, no settings.
>
> Starting and stopping is the entire driving task. Pressing START before pulling away is
> the one thing a mileage log depends on, and it is also the thing a driver forgets: a trip
> not started is a deduction lost, and a trip not stopped is a record with an arrival that
> never happened. Both are corrections a driver should not be making on a phone while
> driving.
>
> The app already starts and stops automatically when the iPhone connects to and disconnects
> from CarPlay, read from the audio route. Without the entitlement iOS does not launch a
> closed app for CarPlay, so that automation only works when the app happens to be running.
> The entitlement is what makes it reliable — and what lets a driver who prefers to decide
> for themselves press one button on the car's screen instead of picking up their phone.

## Garde-fou

```bash
python3 tools/check-carplay-entitlement.py
```

Sort en 0 tant que `CARPLAY_DRIVING_TASK` est sur l'App ID, en 1 sinon. L'entitlement est
déclaré dans `App/MileagePocket.entitlements` : si la capability disparaît, ce n'est pas la
compilation qui casse, c'est la **signature** — et le message d'Xcode ne nomme pas la cause.

Référence au 2026-09-14 : `Mileage.lno.company` porte `APP_GROUPS`, `ICLOUD`,
`IN_APP_PURCHASE`, `PUSH_NOTIFICATIONS`. Aucune capacité CarPlay, ni ici ni sur
`dashcam.lno.company` — la demande du 12 septembre est donc toujours en attente elle aussi.

⚠️ Piège rencontré en écrivant ce guetteur : `/v1/bundleIds/{id}/bundleIdCapabilities`
**refuse le paramètre `limit`**. L'appel répond 400, et un script qui avale l'erreur rend une
liste vide — ce qui se lit « aucune capacité » alors que l'App ID en porte quatre.
