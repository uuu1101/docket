//  PopoverView.swift
//  Docket

import AppKit
import SwiftUI

import DocketKit

struct PopoverView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store
    @Environment(Clock.self) private var clock
    @Environment(\.openWindow) private var openWindow

    @State private var filter = TicketFilter()
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ConnectionBanner()

            if settings.jiraConfiguration == nil {
                SetupPromptView()
                    .frame(maxHeight: .infinity)
            } else {
                NavigationStack {
                    TicketListView(filter: $filter, selection: $selection)
                        .navigationDestination(item: $selection) { key in
                            if let ticket = store.ticket(withKey: key) {
                                TicketDetailView(ticket: ticket, isCompact: true)
                                    .navigationTitle(ticket.key)
                            }
                        }
                }
            }
        }
        .frame(width: 400, height: 540)
        .task { store.refresh(force: false) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(settings.strings.appName)
                .font(.headline)
                .accessibilityIdentifier("dashboard_text_title")

            if store.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Spacer(minLength: 0)

            Text(syncLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Button {
                store.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(settings.strings.refresh)
            .disabled(store.isSyncing)
            .accessibilityIdentifier("dashboard_button_refresh")

            Button {
                openWindow(id: DocketApp.dashboardWindowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help(settings.strings.openInWindow)
            .accessibilityIdentifier("dashboard_button_open_window")

            OpenSettingsButton {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(settings.strings.settings)
            .accessibilityIdentifier("dashboard_button_settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(settings.strings.quit)
            .accessibilityIdentifier("dashboard_button_quit")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var syncLabel: String {
        if store.isSyncing { return settings.strings.syncing }
        guard let lastSyncedAt = store.lastSyncedAt else { return settings.strings.neverSynced }
        return settings.strings.lastUpdated(
            settings.relativeTime.string(for: lastSyncedAt, relativeTo: clock.now)
        )
    }
}

struct SetupPromptView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(settings.strings.setupTitle)
                .font(.callout.weight(.semibold))
            Text(settings.strings.setupSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            OpenSettingsButton {
                Text(settings.strings.openSettings)
            }
            .padding(.top, 4)
            .accessibilityIdentifier("setup_button_open_settings")
        }
        .padding(28)
        .accessibilityIdentifier("setup_container_prompt")
    }
}
