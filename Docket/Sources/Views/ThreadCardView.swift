//  ThreadCardView.swift
//  Docket

import SwiftUI

import DocketKit

/// Summary card for one Slack thread: root message, who is in it, how active it is.
/// Reading the conversation itself happens in Slack.
struct ThreadCardView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store
    @Environment(\.openURL) private var openURL

    let thread: SlackThread

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if thread.isLinkOnly {
                Text(settings.strings.linkOnlyThreadHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("thread_text_link_only_hint")
            } else {
                Text(thread.rootText.isEmpty ? "—" : thread.rootText)
                    .font(.callout)
                    .lineLimit(isExpanded ? nil : 3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("thread_text_root_message")

                footer
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(thread.unreadReplyCount > 0 ? Color.accentColor.opacity(0.5) : .clear)
        )
        .contentShape(.rect)
        .onTapGesture {
            isExpanded.toggle()
            store.markSeen(thread)
        }
        .contextMenu {
            Button(settings.strings.openInSlack) { open() }
            Button(
                thread.origin == .jira ? settings.strings.hideJiraThread : settings.strings.removeThread
            ) {
                store.removeThread(thread)
            }
        }
        .accessibilityIdentifier("thread_container_card")
    }

    /// A link-only card never learned its channel's name, so a raw id would be all there
    /// is to show; a plain label reads better.
    private var channelLabel: String {
        thread.isLinkOnly && thread.channelName == thread.channelID
            ? settings.strings.linkOnlyThreadTitle
            : "#\(thread.channelName)"
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(channelLabel)
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("thread_text_channel")

            if thread.origin == .jira {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(settings.strings.threadFromJira)
            }

            Spacer(minLength: 0)

            Text(settings.relativeTime.string(for: thread.lastActivityAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                open()
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help(settings.strings.openInSlack)
            .accessibilityIdentifier("thread_button_open_slack")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if thread.participantNames.isEmpty == false {
                Text(settings.strings.participantCount(thread.participantNames.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(thread.participantNames.joined(separator: ", "))
            }

            Text(settings.strings.replyCount(thread.replyCount))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let author = thread.lastReplyAuthorName ?? thread.rootAuthorName.nilWhenEmpty {
                Text(settings.strings.lastActivity(author, settings.relativeTime.string(for: thread.lastActivityAt)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if thread.unreadReplyCount > 0 {
                Text(settings.strings.newReplyCount(thread.unreadReplyCount))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("thread_badge_unread")
            }
        }
    }

    private func open() {
        store.markSeen(thread)
        guard let permalink = thread.permalink else { return }
        openURL(permalink)
    }
}

extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
