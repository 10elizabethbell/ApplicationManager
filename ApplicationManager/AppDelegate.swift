import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var config = LibraryConfig(apps: [])

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.syncAtStartup()
        reloadLibrary()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = menuBarImage
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.toolTip = "Application Manager"
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        reloadLibrary()
        showMenu()
    }

    private func reloadLibrary() {
        config = LibraryStore.load()
    }

    private func showMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        if config.apps.isEmpty {
            let emptyItem = NSMenuItem(title: "No apps in library", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for app in config.apps {
                menu.addItem(makeAppMenuItem(for: app))
            }
        }

        menu.addItem(.separator())

        let manageItem = NSMenuItem(title: "Manage Library", action: nil, keyEquivalent: "")
        let manageMenu = NSMenu()

        manageMenu.addItem(
            withTitle: "Add Application",
            action: #selector(addApplication),
            keyEquivalent: ""
        ).target = self

        manageMenu.addItem(
            withTitle: "Refresh Library",
            action: #selector(refreshLibrary),
            keyEquivalent: "r"
        ).target = self

        let loginItem = manageMenu.addItem(
            withTitle: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off

        if !config.apps.isEmpty {
            manageMenu.addItem(.separator())
            for app in config.apps {
                let removeItem = NSMenuItem(
                    title: "Remove \(app.name)",
                    action: #selector(removeApplication(_:)),
                    keyEquivalent: ""
                )
                removeItem.target = self
                removeItem.representedObject = app.id
                manageMenu.addItem(removeItem)
            }
        }

        manageItem.submenu = manageMenu
        menu.addItem(manageItem)

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit Application Manager",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ).target = self

        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.midX, y: button.bounds.height), in: button)
    }

    private func makeAppMenuItem(for app: LibraryApp) -> NSMenuItem {
        let running = isRunning(app)
        let exists = FileManager.default.fileExists(atPath: app.url.path)

        var title = app.name
        if running {
            title += "  ✓"
        } else if !exists {
            title += "  (missing)"
        }

        let item = NSMenuItem(title: title, action: #selector(toggleApp(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = app.id
        item.isEnabled = exists

        item.image = menuIcon(for: app)

        if running {
            item.toolTip = "Running — click to turn off"
        } else if exists {
            item.toolTip = "Off — click to turn on"
        } else {
            item.toolTip = "App not found at \(app.path)"
        }

        return item
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let appID = sender.representedObject as? String,
              let app = config.apps.first(where: { $0.id == appID }) else {
            return
        }

        if let runningApp = runningApplication(for: app) {
            runningApp.terminate()
            return
        }

        guard FileManager.default.fileExists(atPath: app.url.path) else {
            showAlert(
                title: "App Not Found",
                message: "\(app.name) was not found at:\n\(app.path)\n\nUse Refresh Library after building, or edit the config path."
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error {
                DispatchQueue.main.async {
                    self.showAlert(
                        title: "Launch Failed",
                        message: "Could not launch \(app.name):\n\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    @objc private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Add Application"
        panel.message = "Choose an app to add to your library."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let bundleID = bundle?.bundleIdentifier
        let baseID = bundleID ?? url.deletingPathExtension().lastPathComponent.lowercased()
        var uniqueID = baseID
        var suffix = 2
        while config.apps.contains(where: { $0.id == uniqueID }) {
            uniqueID = "\(baseID)-\(suffix)"
            suffix += 1
        }

        let entry = LibraryApp(
            id: uniqueID,
            name: name,
            path: url.path,
            bundleIdentifier: bundleID,
            symbolName: AppBundleIcon.resolvedSymbolName(for: url)
        )

        LibraryStore.includeApp(entry, in: &config)
        config.apps.append(entry)
        LibraryStore.save(config)
        reloadLibrary()
        showMenu()
    }

    @objc private func removeApplication(_ sender: NSMenuItem) {
        guard let appID = sender.representedObject as? String,
              let app = config.apps.first(where: { $0.id == appID }) else { return }
        LibraryStore.excludeApp(app, from: &config)
        LibraryStore.save(config)
        reloadLibrary()
        showMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            showAlert(
                title: "Launch at Login Failed",
                message: "Could not update the login item:\n\(error.localizedDescription)"
            )
        }
    }

    @objc private func refreshLibrary() {
        reloadLibrary()
        showMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func isRunning(_ app: LibraryApp) -> Bool {
        runningApplication(for: app) != nil
    }

    private func runningApplication(for app: LibraryApp) -> NSRunningApplication? {
        if let bundleID = app.resolvedBundleIdentifier {
            if let match = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                return match
            }
        }

        let appName = app.url.deletingPathExtension().lastPathComponent
        return NSWorkspace.shared.runningApplications.first { runningApp in
            runningApp.bundleURL?.path == app.url.path
                || runningApp.localizedName == app.name
                || runningApp.localizedName == appName
        }
    }

    private func menuIcon(for app: LibraryApp) -> NSImage? {
        if FileManager.default.fileExists(atPath: app.url.path),
           let icon = AppBundleIcon.menuIcon(for: app.url) {
            return icon
        }

        let symbolName = AppBundleIcon.resolvedSymbolName(for: app.url, storedSymbolName: app.symbolName)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: app.name) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private var menuBarImage: NSImage? {
        guard let image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Application Manager") else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
