import MacStartCore
import ServiceManagement
import os

/// Launch at login through `SMAppService.mainApp`.
@MainActor
struct LoginItem {
    enum Status {
        case enabled
        /// Registered, but the user has to allow it in System Settings.
        case requiresApproval
        case disabled
    }

    private let logger = LogArea.overlay.logger

    var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    /// Registers or unregisters the app as a login item. Registering again when already registered is skipped.
    /// Each ad hoc signed build has a new signature, which can make an older registration invalid, so this runs at
    /// every launch.
    func setEnabled(_ isEnabled: Bool) throws {
        let service = SMAppService.mainApp
        if isEnabled {
            guard service.status != .enabled else {
                return
            }
            try service.register()
            logger.info("Registered launch at login, status \(String(describing: service.status), privacy: .public)")
        } else {
            guard service.status == .enabled || service.status == .requiresApproval else {
                return
            }
            try service.unregister()
            logger.info("Unregistered launch at login")
        }
    }

    /// Opens System Settings at Login Items, where the user can allow the app.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
