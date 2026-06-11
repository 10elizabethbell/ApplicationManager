import Foundation

enum MenuBarAppsDiscovery {
    private static let folderName = "Menu Bar Applications"
    private static let maxSearchDepth = 5

    static func menuBarApplicationsFolder() -> URL? {
        var url = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<8 {
            if url.lastPathComponent == folderName {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                break
            }
            url = parent
        }

        if let parent = parentOfContainingProject() {
            return parent
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/\(folderName)", isDirectory: true)
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }

        return nil
    }

    /// Parent of the project folder that contains this app (e.g. `ApplicationManager/build` → `Menu Bar Applications`).
    private static func parentOfContainingProject() -> URL? {
        var url = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<8 {
            if url.lastPathComponent == "build" {
                let projectFolder = url.deletingLastPathComponent()
                let parent = projectFolder.deletingLastPathComponent()
                if parent.path != projectFolder.path {
                    return parent
                }
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                break
            }
            url = parent
        }
        return nil
    }

    static func discoverApps() -> [LibraryApp] {
        guard let menuBarFolder = menuBarApplicationsFolder() else { return [] }

        let selfBundleID = Bundle.main.bundleIdentifier
        let selfAppName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String

        var bundleURLs: [URL] = []
        bundleURLs.append(contentsOf: immediateAppBundles(in: menuBarFolder))

        for projectFolder in immediateSubfolders(in: menuBarFolder) {
            bundleURLs.append(contentsOf: findAppBundles(in: projectFolder, remainingDepth: maxSearchDepth))
        }

        let discovered = bundleURLs.compactMap { url in
            makeLibraryApp(from: url, selfBundleID: selfBundleID, selfAppName: selfAppName)
        }
        return deduplicated(discovered)
    }

    private static func immediateAppBundles(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { $0.pathExtension == "app" }
    }

    private static func immediateSubfolders(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { url in
            guard url.pathExtension != "app" else { return false }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            let name = url.lastPathComponent
            return name != ".git" && !name.hasPrefix(".")
        }
    }

    private static func findAppBundles(in directory: URL, remainingDepth: Int) -> [URL] {
        guard remainingDepth >= 0 else { return [] }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var apps: [URL] = []
        for item in contents {
            if item.pathExtension == "app" {
                apps.append(item)
                continue
            }

            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            let name = item.lastPathComponent
            if name == ".git" || name.hasPrefix(".") {
                continue
            }

            apps.append(contentsOf: findAppBundles(in: item, remainingDepth: remainingDepth - 1))
        }

        return apps
    }

    private static func makeLibraryApp(
        from url: URL,
        selfBundleID: String?,
        selfAppName: String?
    ) -> LibraryApp? {
        guard let bundle = Bundle(url: url) else { return nil }

        let bundleID = bundle.bundleIdentifier
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        if bundleID == selfBundleID || name == selfAppName {
            return nil
        }

        let id = bundleID ?? url.deletingPathExtension().lastPathComponent.lowercased()
        let symbolName = AppBundleIcon.resolvedSymbolName(for: url)
        return LibraryApp(
            id: id,
            name: name,
            path: url.path,
            bundleIdentifier: bundleID,
            symbolName: symbolName
        )
    }

    private static func deduplicated(_ apps: [LibraryApp]) -> [LibraryApp] {
        var seen = Set<String>()
        var result: [LibraryApp] = []

        for app in apps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let key = app.resolvedBundleIdentifier ?? app.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(app)
        }

        return result
    }
}
