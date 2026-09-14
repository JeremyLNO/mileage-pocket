# CarPlay Driving Task — demande d'entitlement

Apple accorde `com.apple.developer.carplay-driving-task` **par app**, à la main, via
<https://developer.apple.com/contact/carplay/>. Il n'y a pas d'API : le formulaire est
derrière une authentification Apple Developer et doit être soumis par le titulaire du compte.

**Demandée le 2026-09-14** — réponse d'Apple : « Thank you for your submission. We'll review
your request and contact you soon with a status update. » En attente.

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

## Guetteur

Un droit accordé apparaît comme capacité sur l'App ID :

```bash
python3 tools/check-carplay-entitlement.py
```

⚠️ **Il ne peut annoncer qu'un oui, jamais un non.** Un refus ne laisse aucune trace dans
l'API et arrive uniquement par mail à jeremy@k-b.so. Ne jamais lire « pas de capacité
CarPlay » comme un refus.

Référence au 2026-09-14 : `Mileage.lno.company` porte `APP_GROUPS`, `ICLOUD`,
`IN_APP_PURCHASE`, `PUSH_NOTIFICATIONS`. Aucune capacité CarPlay, ni ici ni sur
`dashcam.lno.company` — la demande du 12 septembre est donc toujours en attente elle aussi.

⚠️ Piège rencontré en écrivant ce guetteur : `/v1/bundleIds/{id}/bundleIdCapabilities`
**refuse le paramètre `limit`**. L'appel répond 400, et un script qui avale l'erreur rend une
liste vide — ce qui se lit « aucune capacité » alors que l'App ID en porte quatre.
