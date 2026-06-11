import Foundation

struct LibraryApp: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var path: String
    var bundleIdentifier: String?
    var symbolName: String?

    var url: URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    var resolvedBundleIdentifier: String? {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.bundleIdentifier
    }

    var displaySymbolName: String {
        symbolName ?? "app"
    }
}

struct LibraryConfig: Codable {
    var apps: [LibraryApp]
    var excludedIDs: [String]

    init(apps: [LibraryApp] = [], excludedIDs: [String] = []) {
        self.apps = apps
        self.excludedIDs = excludedIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decode([LibraryApp].self, forKey: .apps)
        excludedIDs = try container.decodeIfPresent([String].self, forKey: .excludedIDs) ?? []
    }
}
