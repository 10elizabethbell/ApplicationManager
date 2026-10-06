import Foundation

enum LibraryStore {
    private static let bundleID = "com.applicationmanager.app"
    private static let legacyBundleIDs = [
        "com.applicationorchestrator.app",
        "com.processlibrary.app",
        "com.applicationlibrary.app"
    ]
    private static let fileName = "library.json"

    static var configURL: URL {
        configDirectory.appendingPathComponent(fileName)
    }

    private static var configDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(bundleID, isDirectory: true)
    }

    static func load() -> LibraryConfig {
        migrateLegacyConfigIfNeeded()
        ensureConfigExists()

        let saved: LibraryConfig
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(LibraryConfig.self, from: data) {
            saved = sanitize(config)
        } else {
            saved = LibraryConfig(apps: [])
        }

        let merged = mergeDiscoveredApps(into: saved)
        if shouldPersistMergedChanges(from: saved, to: merged) {
            save(merged)
        }
        return merged
    }

    static func save(_ config: LibraryConfig) {
        let sanitized = sanitize(config)
        let directory = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.pretty.encode(sanitized) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    private static func mergeDiscoveredApps(into config: LibraryConfig) -> LibraryConfig {
        var merged = config
        let excluded = Set(config.excludedIDs)
        var indexByKey = Dictionary(
            uniqueKeysWithValues: merged.apps.enumerated().map { (identityKey(for: $0.element), $0.offset) }
        )

        for discovered in MenuBarAppsDiscovery.discoverApps() + MenuBarOnlyApps.installedApps() {
            let key = identityKey(for: discovered)
            guard !excluded.contains(key) else { continue }

            if let index = indexByKey[key] {
                let existing = merged.apps[index]
                let existingMissing = !FileManager.default.fileExists(atPath: existing.url.path)
                let discoveredExists = FileManager.default.fileExists(atPath: discovered.url.path)
                if existingMissing && discoveredExists {
                    merged.apps[index].path = discovered.path
                }
                if existing.symbolName == nil || existing.symbolName == "app",
                   let discoveredSymbol = discovered.symbolName,
                   discoveredSymbol != "app" {
                    merged.apps[index].symbolName = discoveredSymbol
                }
                continue
            }

            merged.apps.append(discovered)
            indexByKey[key] = merged.apps.count - 1
        }

        merged.apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return merged
    }

    private static func shouldPersistMergedChanges(from saved: LibraryConfig, to merged: LibraryConfig) -> Bool {
        let savedPathsByKey = Dictionary(uniqueKeysWithValues: saved.apps.map { (identityKey(for: $0), $0.path) })
        for app in merged.apps {
            let key = identityKey(for: app)
            guard let savedPath = savedPathsByKey[key] else { continue }
            if savedPath != app.path,
               !FileManager.default.fileExists(atPath: (savedPath as NSString).expandingTildeInPath),
               FileManager.default.fileExists(atPath: app.url.path) {
                return true
            }
        }
        return false
    }

    static func excludeApp(_ app: LibraryApp, from config: inout LibraryConfig) {
        let key = identityKey(for: app)
        if !config.excludedIDs.contains(key) {
            config.excludedIDs.append(key)
        }
        config.apps.removeAll { identityKey(for: $0) == key }
    }

    static func includeApp(_ app: LibraryApp, in config: inout LibraryConfig) {
        let key = identityKey(for: app)
        config.excludedIDs.removeAll { $0 == key }
    }

    private static func identityKey(for app: LibraryApp) -> String {
        app.resolvedBundleIdentifier ?? app.id
    }

    private static func migrateLegacyConfigIfNeeded() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        for legacyBundleID in legacyBundleIDs {
            let legacyURL = appSupport
                .appendingPathComponent(legacyBundleID, isDirectory: true)
                .appendingPathComponent(fileName)

            guard FileManager.default.fileExists(atPath: legacyURL.path) else { continue }

            try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: legacyURL, to: configURL)
            return
        }
    }

    private static func ensureConfigExists() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        save(LibraryConfig())
    }

    private static func sanitize(_ config: LibraryConfig) -> LibraryConfig {
        var seen = Set<String>()
        let apps = config.apps.filter { app in
            guard !app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard !app.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let key = app.id.isEmpty ? app.path : app.id
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        return LibraryConfig(apps: apps)
    }
}

private extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
