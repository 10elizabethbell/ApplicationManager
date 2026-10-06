import AppKit
import Carbon

/// Third-party apps that live outside the projects folder but belong in the library,
/// launched so they only appear in the menu bar: no dock icon, no main window.
enum MenuBarOnlyApps {
    private struct Entry {
        let name: String
        let bundleIdentifier: String
        let defaultPath: String
        /// Runs before launch, only when the app is not already running.
        let prepare: () -> Void
    }

    private static let entries: [Entry] = [
        Entry(
            name: "Wispr Flow",
            bundleIdentifier: "com.electron.wispr-flow",
            defaultPath: "/Applications/Wispr Flow.app",
            prepare: { enableWisprFlowHideInDock() }
        )
    ]

    /// Library entries for the apps that are installed.
    static func installedApps() -> [LibraryApp] {
        entries.compactMap { entry in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier)
                ?? URL(fileURLWithPath: entry.defaultPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return LibraryApp(
                id: entry.bundleIdentifier,
                name: entry.name,
                path: url.path,
                bundleIdentifier: entry.bundleIdentifier,
                symbolName: AppBundleIcon.resolvedSymbolName(for: url)
            )
        }
    }

    static func handles(_ app: LibraryApp) -> Bool {
        entry(for: app) != nil
    }

    /// Prepares the app and returns a launch configuration that keeps it in the menu bar.
    static func launchConfiguration(for app: LibraryApp) -> NSWorkspace.OpenConfiguration {
        entry(for: app)?.prepare()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.appleEvent = loginItemOpenEvent()
        return configuration
    }

    private static func entry(for app: LibraryApp) -> Entry? {
        guard let bundleID = app.resolvedBundleIdentifier else { return nil }
        return entries.first { $0.bundleIdentifier == bundleID }
    }

    /// An "open application" event marked as a login-item launch. Electron reports this as
    /// `wasOpenedAtLogin`, which apps like Wispr Flow use to skip opening their main window.
    private static func loginItemOpenEvent() -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(
            NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
            forKeyword: AEKeyword(keyAEPropData)
        )
        return event
    }

    /// Wispr Flow re-shows its dock icon on launch unless its "Hide app in dock" pref is on.
    /// It rewrites config.json from memory, so this only sticks while the app is not running.
    private static func enableWisprFlowHideInDock() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configURL = appSupport.appendingPathComponent("Wispr Flow/config.json")

        guard let data = try? Data(contentsOf: configURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var prefs = root["prefs"] as? [String: Any],
              var user = prefs["user"] as? [String: Any],
              user["hideAppInDock"] as? Bool != true else {
            return
        }

        user["hideAppInDock"] = true
        prefs["user"] = user
        root["prefs"] = prefs

        guard let updated = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else { return }
        try? updated.write(to: configURL, options: .atomic)
    }
}
