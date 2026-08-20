//  TicketRowView.swift
//  Docket

import SwiftUI

import DocketKit

struct TicketRowView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Clock.self) private var clock

    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let attention = ticket.attention {
                    AttentionBadge(attention: attention)
                }
                StatusBadge(ticket: ticket)
            }

            Text(ticket.summary)
                .font(.callout)
                .lineLimit(2)
                .accessibilityIdentifier("ticket_text_summary")

            HStack(spacing: 6) {
                Text(ticket.key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ticket_text_key")

                PriorityBadge(name: ticket.priorityName, rank: ticket.priorityRank)

                if let targetEnd = ticket.targetEndDate {
                    TargetEndBadge(date: targetEnd)
                }

                Text(settings.relativeTime.string(for: ticket.updatedAt, relativeTo: clock.now))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                ThreadCountLabel(
                    total: ticket.visibleThreads.count,
                    unread: ticket.unreadReplyCount
                )
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("dashboard_list_item_ticket")
    }
}

private struct ThreadCountLabel: View {
    let total: Int
    let unread: Int

    var body: some View {
        HStack(spacing: 3) {
            if unread > 0 {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .accessibilityIdentifier("ticket_badge_unread")
            }
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.caption2)
            Text("\(total)")
                .font(.caption)
        }
        .foregroundStyle(total > 0 ? .secondary : .tertiary)
        .accessibilityIdentifier("ticket_badge_thread_count")
    }
}
