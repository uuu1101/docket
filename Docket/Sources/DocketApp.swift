//  DocketApp.swift
//  Docket

import SwiftData
import SwiftUI

import DocketKit

@main
struct DocketApp: App {
    @State private var settings: AppSettings
    @State private var store: DashboardStore
    @State private var slackAuth: SlackAuthCoordinator
    @State private var loginItem = LoginItem()
    @State private var clock = Clock()

    init() {
        let settings = AppSettings()
        let store = DashboardStore(settings: settings, container: Self.makeContainer())
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        _slackAuth = State(initialValue: SlackAuthCoordinator(settings: settings))
        // The menu bar badge has to be current before the popover is ever opened, so
        // polling starts at launch rather than when a view appears.
        store.startAutoRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(settings)
                .environment(store)
                .environment(clock)
        } label: {
            Image(nsImage: MenuBarIcon.image(count: store.ticketsNeedingAttention))
        }
        .menuBarExtraStyle(.window)

        Window(settings.strings.appName, id: Self.dashboardWindowID) {
            DashboardWindowView()
                .environment(settings)
                .environment(store)
                .environment(clock)
        }
        .defaultSize(width: 1_040, height: 660)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(store)
                .environment(slackAuth)
                .environment(loginItem)
        }
    }

    static let dashboardWindowID = "dashboard"

    /// Falls back to an in-memory store rather than crashing: a corrupt cache is an
    /// inconvenience, not a reason to lose the app.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Ticket.self, SlackThread.self])
        if let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: storeURL())
        ) {
            return container
        }
        return try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// An app-scoped store path. SwiftData's default for a non-sandboxed app is the shared
    /// `~/Library/Application Support/default.store`, which any other such app can claim
    /// first with an incompatible schema.
    private static func storeURL() -> URL {
        let directory = URL.applicationSupportDirectory
            .appending(path: "Docket", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Docket.store")
    }
}
