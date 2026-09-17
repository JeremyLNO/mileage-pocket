import Foundation
import SwiftData

/// Force CloudKit à fabriquer **tous** les types d'enregistrement, pas seulement ceux qu'un
/// usage ordinaire finit par produire.
///
/// CloudKit ne crée un type que lorsqu'il a un enregistrement à exporter. Un lancement de
/// démonstration produit des trajets, des véhicules, des clients et des réglages — et laisse
/// donc sans type les cinq modèles qu'on ne rencontre qu'en roulant, en clôturant un mois ou
/// en apprenant une destination. Déployer un schéma partiel en Production ne casse rien tout
/// de suite : ça casse le jour où un utilisateur crée son premier projet, et la
/// synchronisation de cet objet-là échoue en silence, pour lui seul.
///
/// SwiftData n'expose pas `initializeCloudKitSchema()` de `NSPersistentCloudKitContainer`,
/// qui existe précisément pour ça. À défaut : un exemplaire de chaque modèle, exporté, puis
/// retiré — le type reste au schéma une fois l'enregistrement parti.
///
/// Deux lancements, volontairement, plutôt qu'un avec une temporisation : insérer et
/// supprimer dans la même session courrait après l'export au lieu de l'attendre.
///
///     --seed-cloudkit-schema   puis, une fois les types visibles dans la console :
///     --clear-cloudkit-seed
#if DEBUG
enum CloudKitSchemaSeed {
    static var isRequested: Bool { CommandLine.arguments.contains("--seed-cloudkit-schema") }
    static var isCleanupRequested: Bool { CommandLine.arguments.contains("--clear-cloudkit-seed") }

    private static let key = "cloudkit.schema.seed.ids"

    @MainActor
    static func insertOneOfEachModel(context: ModelContext) {
        let now = Date()
        let tripID = UUID()

        let point = LocationPoint(
            tripID: tripID, latitude: 48.8566, longitude: 2.3522,
            timestamp: now, horizontalAccuracy: 5
        )
        let project = Project(name: "__cloudkit schema__")
        let place = FrequentLocation(latitude: 48.8566, longitude: 2.3522, address: "__cloudkit schema__")
        let active = ActiveTripState(tripID: tripID, startedAt: now)
        let period = ClosedPeriod(startedAt: now, endedAt: now, closedAt: now)

        context.insert(point)
        context.insert(project)
        context.insert(place)
        context.insert(active)
        context.insert(period)
        try? context.save()

        // Les identifiants sont mémorisés pour que la passe de nettoyage supprime
        // exactement ces objets-là, et rien d'autre : la base peut contenir entre-temps de
        // vrais points de tracé ou une vraie période clôturée.
        UserDefaults.standard.set(
            [point.id, project.id, place.id, active.id, period.id].map(\.uuidString),
            forKey: key
        )
        print("[CloudKitSchemaSeed] inséré : LocationPoint, Project, FrequentLocation, ActiveTripState, ClosedPeriod")
    }

    @MainActor
    static func removeSeed(context: ModelContext) {
        let ids = Set((UserDefaults.standard.array(forKey: key) as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        guard !ids.isEmpty else {
            print("[CloudKitSchemaSeed] rien à nettoyer")
            return
        }
        var removed = 0
        for point in (try? context.fetch(FetchDescriptor<LocationPoint>()))?.filter({ ids.contains($0.id) }) ?? [] {
            context.delete(point); removed += 1
        }
        for project in (try? context.fetch(FetchDescriptor<Project>()))?.filter({ ids.contains($0.id) }) ?? [] {
            context.delete(project); removed += 1
        }
        for place in (try? context.fetch(FetchDescriptor<FrequentLocation>()))?.filter({ ids.contains($0.id) }) ?? [] {
            context.delete(place); removed += 1
        }
        for state in (try? context.fetch(FetchDescriptor<ActiveTripState>()))?.filter({ ids.contains($0.id) }) ?? [] {
            context.delete(state); removed += 1
        }
        for period in (try? context.fetch(FetchDescriptor<ClosedPeriod>()))?.filter({ ids.contains($0.id) }) ?? [] {
            context.delete(period); removed += 1
        }
        try? context.save()
        UserDefaults.standard.removeObject(forKey: key)
        print("[CloudKitSchemaSeed] retiré \(removed) objet(s) — les types restent au schéma")
    }
}
#endif
