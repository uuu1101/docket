//  TicketQueryTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Ticket query presets")
struct TicketQueryTests {
    private var presets: [TicketQuery] { TicketQuery.allCases.filter { $0 != .custom } }

    @Test("Every preset resolves to JQL")
    func presetsResolve() {
        for preset in presets {
            #expect(preset.jql?.isEmpty == false, "\(preset.rawValue) has no JQL")
        }
    }

    @Test("Custom carries no preset JQL of its own")
    func customHasNoJQL() {
        #expect(TicketQuery.custom.jql == nil)
    }

    @Test("Every preset scopes to the current user")
    func presetsScopeToCurrentUser() {
        for preset in presets {
            #expect(preset.jql?.contains("currentUser()") == true, "\(preset.rawValue) is not user-scoped")
        }
    }

    @Test("Every preset sorts by most recently updated")
    func presetsSortByUpdated() {
        for preset in presets {
            #expect(preset.jql?.hasSuffix("ORDER BY updated DESC") == true, "\(preset.rawValue) is unsorted")
        }
    }

    @Test("The default preset is the open assigned work")
    func defaultPreset() {
        #expect(TicketQuery.default == .assignedOpen)
        #expect(TicketQuery.assignedOpen.jql == TicketQuery.fallbackJQL)
    }

    @Test("Only the recently-done preset reaches past Done")
    func recentlyDoneIsTheOnlyPresetIncludingDone() {
        for preset in presets where preset != .assignedOpenOrRecentlyDone {
            #expect(preset.jql?.contains("resolutiondate") == false)
        }
        #expect(TicketQuery.assignedOpenOrRecentlyDone.jql?.contains("resolutiondate >= -7d") == true)
    }

    @Test("Presets pick distinct user fields")
    func presetsUseDistinctFields() {
        #expect(TicketQuery.assignedOpen.jql?.hasPrefix("assignee =") == true)
        #expect(TicketQuery.reportedOpen.jql?.hasPrefix("reporter =") == true)
        #expect(TicketQuery.watching.jql?.hasPrefix("watcher =") == true)
    }
}

@MainActor
@Suite("Resolving the query to send")
struct QueryResolutionTests {
    private func makeSettings() -> AppSettings {
        AppSettings(
            defaults: UserDefaults(suiteName: "dev.taetae.docket.tests.\(UUID().uuidString)")!,
            keychain: KeychainStore(service: "dev.taetae.docket.tests")
        )
    }

    @Test("A fresh install starts on the default preset")
    func freshInstall() {
        let settings = makeSettings()
        #expect(settings.query == .default)
        #expect(settings.jql == TicketQuery.fallbackJQL)
    }

    @Test("A preset ignores whatever custom text is left behind")
    func presetIgnoresCustomText() {
        let settings = makeSettings()
        settings.customJQL = "project = NOPE"
        settings.query = .watching
        #expect(settings.jql == TicketQuery.watching.jql)
    }

    @Test("Custom text is sent verbatim once trimmed")
    func customIsVerbatim() {
        let settings = makeSettings()
        settings.query = .custom
        settings.customJQL = "  project = APP AND labels = ios  "
        #expect(settings.jql == "project = APP AND labels = ios")
    }

    @Test("A blank custom query falls back instead of asking for everything", arguments: ["", "   ", "\n\t "])
    func blankCustomFallsBack(text: String) {
        let settings = makeSettings()
        settings.query = .custom
        settings.customJQL = text
        #expect(settings.jql == TicketQuery.fallbackJQL)
    }

    @Test("The choice survives a relaunch")
    func choicePersists() {
        let defaults = UserDefaults(suiteName: "dev.taetae.docket.tests.\(UUID().uuidString)")!
        let keychain = KeychainStore(service: "dev.taetae.docket.tests")

        let first = AppSettings(defaults: defaults, keychain: keychain)
        first.query = .custom
        first.customJQL = "project = APP"

        let second = AppSettings(defaults: defaults, keychain: keychain)
        #expect(second.query == .custom)
        #expect(second.jql == "project = APP")
    }
}
