//  StatusIndicators.swift
//  Docket

import SwiftUI

import DocketKit

extension StatusCategory {
    var tint: Color {
        switch self {
        case .todo: .secondary
        case .inProgress: .purple
        case .done: .green
        }
    }
}

/// Colored dot plus the project's own status name — the name varies per project, the
/// category does not, so the color comes from the category.
struct StatusBadge: View {
    let ticket: Ticket

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ticket.statusCategory.tint)
                .frame(width: 7, height: 7)
            Text(ticket.statusName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityIdentifier("ticket_status_badge")
    }
}

struct PriorityBadge: View {
    let name: String?
    let rank: Int

    var body: some View {
        if let name {
            Text(name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                .accessibilityIdentifier("ticket_badge_priority")
        }
    }

    private var tint: Color {
        switch rank {
        case 0, 1: .red
        case 2: .orange
        case 3: .blue
        default: .secondary
        }
    }
}

/// How close a ticket is to its target end date — the dashboard's primary sort key, so it
/// has to be visible or the ordering looks arbitrary.
struct TargetEndBadge: View {
    @Environment(AppSettings.self) private var settings

    let date: Date

    var body: some View {
        Text(settings.strings.targetEnd(daysRemaining: days))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .help("\(settings.strings.targetEndLabel): \(date.formatted(date: .abbreviated, time: .omitted))")
            .accessibilityIdentifier("ticket_badge_target_end")
    }

    private var days: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }

    private var tint: Color {
        switch days {
        case ..<0: .red
        case 0 ... 2: .orange
        default: .secondary
        }
    }
}
