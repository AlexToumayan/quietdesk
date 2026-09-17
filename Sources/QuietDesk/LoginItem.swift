import Foundation
import ServiceManagement

/// Launch at login through the supported, helper-free API (SMAppService, macOS 13+).
/// Only works when running from an app bundle; ad-hoc signed builds may be refused by macOS.
enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var isEnabled: Bool { isAvailable && SMAppService.mainApp.status == .enabled }
    static var requiresApproval: Bool { isAvailable && SMAppService.mainApp.status == .requiresApproval }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func setEnabled(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
