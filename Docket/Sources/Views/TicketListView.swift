//  TicketListView.swift
//  Docket

import SwiftUI

import DocketKit

/// The one ticket list, shared by the menu bar popover and the dashboard window.
struct TicketListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store

    @Binding var filter: TicketFilter
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(filter: $filter, tickets: store.tickets)
            Divider()

            if filtered.isEmpty {
                EmptyStateView(isFiltered: filter.isActive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, id: \.key, selection: $selection) { ticket in
                    TicketRowView(ticket: ticket)
                        .tag(ticket.key)
                }
                .listStyle(.inset)
                .accessibilityIdentifier("dashboard_list_tickets")
            }
        }
    }

    private var filtered: [Ticket] {
        filter.apply(to: store.tickets)
    }
}

private struct FilterBar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store

    @Binding var filter: TicketFilter
    let tickets: [Ticket]

    var body: some View {
        @Bindable var settings = settings

        HStack(spacing: 8) {
            Menu {
                Button(settings.strings.filterAll) { filter.statusCategory = nil }
                Divider()
                ForEach(StatusCategory.allCases, id: \.self) { category in
                    Button(label(for: category)) { filter.statusCategory = category }
                }
            } label: {
                Text(filter.statusCategory.map(label(for:)) ?? settings.strings.filterStatus)
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("dashboard_dropdown_status")

            Menu {
                Button(settings.strings.filterAll) { filter.priorityName = nil }
                Divider()
                ForEach(priorityNames, id: \.self) { name in
                    Button(name) { filter.priorityName = name }
                }
            } label: {
                Text(filter.priorityName ?? settings.strings.filterPriority)
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(priorityNames.isEmpty)
            .accessibilityIdentifier("dashboard_dropdown_priority")

            // Last of the three: the local filters narrow what arrived, this one decides
            // what arrives at all, so it reads as the outermost of the set.
            Menu {
                ForEach(TicketQuery.allCases) { query in
                    Button(settings.strings.ticketQueryName(query)) { settings.query = query }
                }
            } label: {
                Text(settings.strings.ticketQueryShortName(settings.query))
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .onChange(of: settings.query) { store.refresh(force: true) }
            .help(settings.strings.ticketQueryLabel)
            .accessibilityIdentifier("dashboard_dropdown_ticket_query")

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(settings.strings.searchPlaceholder, text: $filter.searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .accessibilityIdentifier("dashboard_input_search")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            .frame(maxWidth: 120)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var priorityNames: [String] {
        let names = tickets.compactMap(\.priorityName)
        let ranked = Dictionary(names.map { ($0, PriorityRank.value(for: $0)) }, uniquingKeysWith: { first, _ in first })
        return ranked.keys.sorted { (ranked[$0] ?? 99, $0) < (ranked[$1] ?? 99, $1) }
    }

    private func label(for category: StatusCategory) -> String {
        switch category {
        case .todo: settings.language.resolved == .korean ? "할 일" : "To Do"
        case .inProgress: settings.language.resolved == .korean ? "진행 중" : "In Progress"
        case .done: settings.language.resolved == .korean ? "완료" : "Done"
        }
    }
}

private struct EmptyStateView: View {
    @Environment(AppSettings.self) private var settings

    let isFiltered: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle" : "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(isFiltered ? settings.strings.emptyFilteredTitle : settings.strings.emptyTitle)
                .font(.callout.weight(.medium))
            Text(isFiltered ? settings.strings.emptyFilteredSubtitle : settings.strings.emptySubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .accessibilityIdentifier("dashboard_container_empty_state")
    }
}
