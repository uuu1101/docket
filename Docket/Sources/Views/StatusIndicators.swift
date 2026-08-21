//  StatusIndicators.swift
//  Docket

import SwiftUI

import DocketKit

extension StatusCategory {
    /// A concrete colour, not `.secondary`: the chip derives both its text and its
    /// background from this, and a hierarchy style cannot be tinted.
    var tint: Color {
        switch self {
        case .todo: .gray
        case .inProgress: .blue
        case .done: .green
        }
    }
}

extension Color {
    /// Sampled from the design's swatch, which is a Display P3 asset; naming the space keeps
    /// the chip the colour that was chosen rather than its sRGB approximation.
    static let attention = Color(.displayP3, red: 248 / 255, green: 215 / 255, blue: 85 / 255)
}

/// Says why a row stands out: never opened, or moved since it was.
///
/// `new` is the one filled chip in the app — every other badge is a tint on 12% of itself —
/// which is what makes a ticket the user has not touched read differently from one that
/// merely changed.
struct AttentionBadge: View {
    @Environment(AppSettings.self) private var settings

    let attention: TicketAttention

    var body: some View {
        switch attention {
        case .new:
            Text(settings.strings.newBadge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.attention, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityIdentifier("ticket_badge_new")

        case .updated:
            Text(settings.strings.updatedBadge)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                .accessibilityIdentifier("ticket_badge_updated")
        }
    }
}

/// The project's own status name in a tinted chip. Names vary per project, so the colour
/// comes from the category — and the chip shape matches the priority and deadline badges,
/// which a bare dot did not.
struct StatusBadge: View {
    /// Drawn inside the chip, so the status and its control read as one thing rather than a
    /// label with something floating beside it.
    enum Accessory {
        case none
        /// The chevron, faded while the workflow's moves are still being fetched. An indicator
        /// that dims and sharpens reads as one control settling; one that appears from nothing
        /// reads as the layout shifting.
        case menu(isReady: Bool)
        case busy
    }

    let ticket: Ticket
    var accessory: Accessory = .none

    var body: some View {
        HStack(spacing: 4) {
            Text(ticket.statusName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            switch accessory {
            case .none:
                EmptyView()
            case let .menu(isReady):
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .opacity(isReady ? 1 : 0.35)
            case .busy:
                ProgressView().controlSize(.small).scaleEffect(0.5)
            }
        }
        .foregroundStyle(ticket.statusCategory.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            ticket.statusCategory.tint.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 4)
        )
        .accessibilityIdentifier("ticket_status_badge")
    }
}

/// The status, and the workflow moves available from it, as one control.
///
/// Destinations are listed by the status they land on rather than by the transition's own
/// name: "검토 중" says more than "Start Review".
struct StatusControl: View {
    @Environment(AppSettings.self) private var settings

    let ticket: Ticket
    /// `nil` until the moves have been fetched — the workflow is per issue, so the list cannot
    /// come from the ticket list and only arrives after the detail opens.
    let transitions: [JiraTransition]?
    let isBusy: Bool
    let onSelect: (JiraTransition) -> Void

    var body: some View {
        if isBusy {
            StatusBadge(ticket: ticket, accessory: .busy)
        } else if let transitions {
            if transitions.isEmpty {
                // No permission, or nowhere to go: a plain label, with nothing to press.
                StatusBadge(ticket: ticket)
            } else {
                menu(for: transitions)
            }
        } else {
            StatusBadge(ticket: ticket, accessory: .menu(isReady: false))
                .accessibilityIdentifier("ticket_detail_status_pending")
        }
    }

    private func menu(for transitions: [JiraTransition]) -> some View {
        Menu {
            ForEach(transitions) { transition in
                Button(transition.toStatusName) { onSelect(transition) }
            }
        } label: {
            StatusBadge(ticket: ticket, accessory: .menu(isReady: true))
        }
        // `.borderlessButton` restyles the label — it drops the chip's colour and draws
        // its own indicator beside it. A plain button style leaves the label alone.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(settings.strings.changeStatus)
        .accessibilityIdentifier("ticket_detail_menu_status")
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
    @Environment(Clock.self) private var clock

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
            from: Calendar.current.startOfDay(for: clock.now),
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
