import Foundation
import OSLog

/// Holds every rule pack the app knows about: the ones shipped in the bundle, plus any
/// newer signed pack that the updater has verified and cached on disk.
///
/// A cached pack only ever *replaces* a bundled one of the same country when its version is
/// higher, and a pack that fails to decode is skipped rather than taking the country down
/// with it.
final class RulePackStore: @unchecked Sendable {
    private let logger = Logger(subsystem: "company.lno.mileage", category: "RulePackStore")
    private let lock = NSLock()
    private var packsByCountry: [String: [RulePack]] = [:]

    init(bundle: Bundle = .main, cacheDirectory: URL? = RulePackStore.defaultCacheDirectory) {
        loadBundled(from: bundle)
        if let cacheDirectory {
            loadCached(from: cacheDirectory)
        }
    }

    /// Test seam: build a store from packs in memory, with no file system involved.
    init(packs: [RulePack]) {
        for pack in packs {
            packsByCountry[pack.country.uppercased(), default: []].append(pack)
        }
    }

    static var defaultCacheDirectory: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MileageRules", isDirectory: true)
    }

    /// The pack in force for a country on a given date — the highest version whose validity
    /// window contains the date. A trip recorded last year keeps last year's scale.
    func pack(country: String, on date: Date) -> RulePack? {
        lock.lock()
        defer { lock.unlock() }
        let candidates = packsByCountry[country.uppercased()] ?? []
        return candidates
            .filter { $0.isValid(on: date) }
            .max { lhs, rhs in lhs.version.compare(rhs.version, options: .numeric) == .orderedAscending }
    }

    /// Countries that have a verified official scale. Everything else is offered in custom
    /// rate mode, which is the whole world minus this set.
    func availableCountries() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(packsByCountry.keys)
    }

    func insert(_ pack: RulePack) {
        lock.lock()
        defer { lock.unlock() }
        var existing = packsByCountry[pack.country.uppercased()] ?? []
        existing.removeAll { $0.version == pack.version }
        existing.append(pack)
        packsByCountry[pack.country.uppercased()] = existing
    }

    // MARK: - Loading

    private func loadBundled(from bundle: Bundle) {
        guard let root = bundle.url(forResource: "MileageRules", withExtension: nil) else {
            logger.warning("No bundled MileageRules folder found")
            return
        }
        load(from: root)
    }

    private func loadCached(from directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        load(from: directory)
    }

    private func load(from root: URL) {
        let decoder = RulePack.decoder()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator where url.pathExtension == "json" {
            do {
                let pack = try decoder.decode(RulePack.self, from: Data(contentsOf: url))
                insert(pack)
            } catch {
                // One malformed file must not cost the user every other country.
                logger.error("Skipping rule pack \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
