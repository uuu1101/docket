//  LoginItem.swift
//  Docket

import Observation
import ServiceManagement

/// Registers the app to start when the user logs in.
///
/// The state lives in macOS, not in the app's own settings: the user can turn it off in
/// System Settings, so it is read back rather than remembered.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status
    private(set) var failure: String?

    init() {
        status = SMAppService.mainApp.status
    }

    var isEnabled: Bool { status == .enabled }

    /// macOS asks the user to confirm in System Settings before it will run the app.
    var needsApproval: Bool { status == .requiresApproval }

    /// Registration records where the app is now. Launched from anywhere else, it keeps
    /// pointing at that copy — a stale Downloads folder, typically.
    var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ enabled: Bool) {
        failure = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }
}
