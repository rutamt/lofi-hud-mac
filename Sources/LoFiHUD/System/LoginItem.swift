import Foundation
import ServiceManagement

/// Start-at-login via `SMAppService` (shows up under System Settings → General → Login Items).
enum LoginItem {
    static func sync(enabled: Bool) {
        guard Paths.devHome == nil else { return }
        removeLegacyLaunchAgent()
        // SMAppService only works from a real .app bundle (not `swift run`).
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            NSLog("LoFi HUD: login item update failed: \(error.localizedDescription)")
        }
    }

    static func unregister() {
        guard Paths.devHome == nil else { return }
        removeLegacyLaunchAgent()
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        try? SMAppService.mainApp.unregister()
    }

    /// The Python build used a LaunchAgent; drop it so we never launch twice.
    private static func removeLegacyLaunchAgent() {
        try? FileManager.default.removeItem(at: Paths.legacyLaunchAgent)
    }
}
