//  CommentsView.swift
//  Docket

import SwiftUI

import DocketKit

/// Draws the tail of a ticket's comment thread, oldest first, automation excluded.
///
/// Collapsible for the same reason as the description, and collapsed to begin with in the
/// popover. `hasMore` sends the reader to Jira rather than paging here — the dashboard shows
/// the recent exchange, not the archive.
struct CommentsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Clock.self) private var clock

    let comments: JiraComments
    let issueURL: URL?

    @State private var isExpanded: Bool

    init(comments: JiraComments, issueURL: URL?, isCompact: Bool) {
        self.comments = comments
        self.issueURL = issueURL
        _isExpanded = State(initialValue: isCompact == false)
    }

    var body: some View {
        if comments.comments.isEmpty == false {
            CollapsibleSection(
                title: settings.strings.commentCount(shown: comments.comments.count, total: comments.total),
                isExpanded: $isExpanded,
                accessory: { allCommentsLink }
            ) {
                thread
            }
            .accessibilityIdentifier("ticket_detail_disclosure_comments")
        }
    }

    /// Shown when the list holds less than the issue does — automation was filtered out, or the
    /// thread is longer than the window.
    @ViewBuilder
    private var allCommentsLink: some View {
        if comments.hasMore, let issueURL {
            Link(settings.strings.seeAllComments, destination: issueURL)
                .font(.caption)
                .accessibilityIdentifier("ticket_detail_button_all_comments")
        }
    }

    private var thread: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(comments.comments) { comment in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(comment.authorName)
                            .font(.caption.weight(.medium))
                        Text(settings.relativeTime.string(for: comment.createdAt, relativeTo: clock.now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ADFBlocksView(blocks: comment.blocks)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ticket_detail_container_comment")
            }
        }
    }
}
