import AppKit
import MacStartCore

/// Launches apps through `NSWorkspace`.
struct AppLauncher {
    /// Launches the app, or brings it to the front when it is already running.
    @MainActor
    func launch(_ app: InstalledApp) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: configuration)
    }
}
