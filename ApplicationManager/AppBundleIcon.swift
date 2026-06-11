import AppKit

enum AppBundleIcon {
    private static let menuPointSize = NSSize(width: 16, height: 16)

    static func menuIcon(for appURL: URL) -> NSImage? {
        guard let bundle = Bundle(url: appURL),
              let source = loadBundleIcon(from: bundle) else {
            return nil
        }
        return rasterize(source)
    }

    static func menuBarSymbolName(for appURL: URL) -> String? {
        guard let bundle = Bundle(url: appURL) else { return nil }
        return bundle.object(forInfoDictionaryKey: "MenuBarSymbolName") as? String
    }

    static func resolvedSymbolName(for appURL: URL, storedSymbolName: String? = nil) -> String {
        if let plistSymbol = menuBarSymbolName(for: appURL), !plistSymbol.isEmpty {
            return plistSymbol
        }
        if let sourceSymbol = MenuBarSymbolDiscovery.discoverSymbol(for: appURL), !sourceSymbol.isEmpty {
            return sourceSymbol
        }
        if let storedSymbolName, !storedSymbolName.isEmpty, storedSymbolName != "app" {
            return storedSymbolName
        }
        return "app"
    }

    private static func loadBundleIcon(from bundle: Bundle) -> NSImage? {
        if let icon = loadIconFile(from: bundle) {
            return icon
        }

        if let name = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let icon = bundle.image(forResource: name), icon.isValid {
            return icon
        }

        if let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            for file in files {
                if let icon = loadNamedImage(file, from: bundle) {
                    return icon
                }
            }
        }

        return loadFirstICNS(from: bundle)
    }

    private static func loadIconFile(from bundle: Bundle) -> NSImage? {
        guard let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String else {
            return nil
        }
        return loadNamedImage(name, from: bundle)
    }

    private static func loadNamedImage(_ name: String, from bundle: Bundle) -> NSImage? {
        var baseName = name
        if baseName.hasSuffix(".icns") {
            baseName = String(baseName.dropLast(5))
        }

        if let url = bundle.url(forResource: baseName, withExtension: "icns"),
           let image = NSImage(contentsOf: url),
           image.isValid {
            return image
        }

        if let image = bundle.image(forResource: baseName), image.isValid {
            return image
        }

        if let url = bundle.url(forResource: baseName, withExtension: "png"),
           let image = NSImage(contentsOf: url),
           image.isValid {
            return image
        }

        return nil
    }

    private static func loadFirstICNS(from bundle: Bundle) -> NSImage? {
        guard let resourcesURL = bundle.resourceURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: resourcesURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard url.pathExtension == "icns",
                  let image = NSImage(contentsOf: url),
                  image.isValid else {
                continue
            }
            return image
        }

        return nil
    }

    private static func rasterize(_ source: NSImage) -> NSImage {
        let icon = NSImage(size: menuPointSize, flipped: false) { bounds in
            source.draw(in: bounds)
            return true
        }
        icon.isTemplate = false
        return icon
    }
}

private extension NSImage {
    var isValid: Bool {
        !representations.isEmpty || size.width > 0
    }
}
