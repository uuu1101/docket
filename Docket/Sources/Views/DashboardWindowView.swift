//  DashboardWindowView.swift
//  Docket

import SwiftUI

import DocketKit

struct DashboardWindowView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store

    @State private var filter = TicketFilter()
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ConnectionBanner()
                TicketListView(filter: $filter, selection: $selection)
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            if let ticket = store.ticket(withKey: selection) {
                TicketDetailView(ticket: ticket)
            } else {
                ContentUnavailableView(
                    settings.strings.selectTicketPrompt,
                    systemImage: "sidebar.left"
                )
                .accessibilityIdentifier("dashboard_container_no_selection")
            }
        }
        .frame(minWidth: 820, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.refresh(force: true)
                } label: {
                    Label(settings.strings.refresh, systemImage: "arrow.clockwise")
                }
                .disabled(store.isSyncing)
                .accessibilityIdentifier("dashboard_button_refresh_window")
            }
        }
    }
}
