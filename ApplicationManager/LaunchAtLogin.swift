import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let preferenceKey = "launchAtLogin"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// User preference; defaults to on so the app registers itself on first launch.
    static var isPreferred: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    /// Re-registers on every launch while preferred, so the login item follows
    /// the bundle if the containing folder is moved or renamed.
    static func syncAtStartup() {
        guard isPreferred, SMAppService.mainApp.status != .enabled else { return }
        try? SMAppService.mainApp.register()
    }

    static func setEnabled(_ enabled: Bool) throws {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
