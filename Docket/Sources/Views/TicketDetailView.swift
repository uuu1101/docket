//  TicketDetailView.swift
//  Docket

import SwiftUI

import DocketKit

struct TicketDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DashboardStore.self) private var store
    @Environment(\.openURL) private var openURL

    let ticket: Ticket

    @State private var isAddingThread = false
    @State private var isEditingFigmaLink = false
    @State private var figmaDraft = ""
    @State private var figmaFailure: String?
    @State private var linkDraft = ""
    @State private var addFailure: String?
    @State private var isSubmittingLink = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                slackSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("ticket_detail_container")
        .task(id: ticket.key) { store.markSeen(ticket) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusBadge(ticket: ticket)
                PriorityBadge(name: ticket.priorityName, rank: ticket.priorityRank)
                if let targetEnd = ticket.targetEndDate {
                    TargetEndBadge(date: targetEnd)
                }
                Text(ticket.issueType)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(ticket.summary)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .accessibilityIdentifier("ticket_detail_text_summary")

            HStack(spacing: 10) {
                Text(ticket.key)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(settings.strings.lastUpdated(settings.relativeTime.string(for: ticket.updatedAt)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }

            // The code sits next to the ticket it belongs to; the design gets its own row
            // because it carries a caption and a menu.
            linksRow

            figmaRow

            if isEditingFigmaLink {
                figmaField
            }
        }
    }

    @ViewBuilder private var linksRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            ForEach(ticket.pullRequests, id: \.urlString) { pullRequest in
                if let url = pullRequest.url {
                    Button {
                        openURL(url)
                    } label: {
                        Label(
                            settings.strings.openPullRequest(pullRequest.name),
                            systemImage: "arrow.trianglehead.pull"
                        )
                    }
                    .buttonStyle(.bordered)
                    .help(pullRequest.title.isEmpty ? url.absoluteString : pullRequest.title)
                    .accessibilityIdentifier("ticket_detail_button_open_pull_request")
                }
            }

            if let url = ticket.browseURL {
                Button {
                    openURL(url)
                } label: {
                    Label(settings.strings.openInJira, systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ticket_detail_button_open_jira")
            }
        }
    }

    @ViewBuilder private var figmaRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if let url = ticket.figmaURL {
                if ticket.hasChosenFigmaURL == false {
                    Text(settings.strings.figmaLinkFromJira)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    openURL(url)
                } label: {
                    Label(settings.strings.openInFigma, systemImage: "paintbrush.pointed")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ticket_detail_button_open_figma")

                Menu {
                    Button(settings.strings.changeFigmaLink) { beginEditingFigmaLink() }
                    if ticket.hasChosenFigmaURL {
                        Button(settings.strings.clearFigmaLink) {
                            store.clearChosenFigmaURL(for: ticket)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("ticket_detail_menu_figma")
            } else {
                Button {
                    beginEditingFigmaLink()
                } label: {
                    Label(settings.strings.addFigmaLink, systemImage: "paintbrush.pointed")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ticket_detail_button_add_figma")
            }
        }
    }

    private var slackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(settings.strings.slackThreadCount(ticket.visibleThreads.count))
                    .font(.headline)

                Spacer(minLength: 0)

                Button {
                    isAddingThread.toggle()
                    addFailure = nil
                } label: {
                    Label(settings.strings.addThread, systemImage: "link.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("ticket_detail_button_add_thread")

            }

            if isAddingThread {
                addThreadField
            }

            // Attached threads show even without a Slack connection: the cards fall back
            // to link-only and still open the conversation.
            if ticket.visibleThreads.isEmpty {
                if store.slackState == .notConfigured {
                    InlineNoticeView(
                        message: settings.strings.slackNotConfigured,
                        detail: settings.strings.slackNotConfiguredThreadsHint,
                        systemImage: "link.badge.plus"
                    )
                } else {
                    InlineNoticeView(
                        message: settings.strings.slackSectionEmpty,
                        detail: settings.strings.slackSectionEmptyHint,
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
            } else {
                ForEach(ticket.visibleThreads, id: \.id) { thread in
                    ThreadCardView(thread: thread)
                }
            }

        }
    }
}

private extension TicketDetailView {
    func beginEditingFigmaLink() {
        figmaDraft = ticket.figmaURL?.absoluteString ?? ""
        figmaFailure = nil
        isEditingFigmaLink = true
    }

    @ViewBuilder var figmaField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(settings.strings.figmaLinkPlaceholder, text: $figmaDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { submitFigmaLink() }
                    .accessibilityIdentifier("ticket_detail_input_figma_link")

                Button(settings.strings.add) { submitFigmaLink() }
                    .disabled(figmaDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("ticket_detail_button_submit_figma_link")

                Button(settings.strings.cancel) {
                    isEditingFigmaLink = false
                    figmaFailure = nil
                }
                .buttonStyle(.borderless)
            }

            if let figmaFailure {
                Label(figmaFailure, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("ticket_detail_status_figma_failure")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    func submitFigmaLink() {
        if store.setFigmaURL(figmaDraft, for: ticket) {
            isEditingFigmaLink = false
            figmaFailure = nil
        } else {
            figmaFailure = settings.strings.invalidFigmaLink
        }
    }

    @ViewBuilder var addThreadField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(settings.strings.addThreadPlaceholder, text: $linkDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit { submitLink() }
                    .accessibilityIdentifier("ticket_detail_input_thread_link")

                if isSubmittingLink {
                    ProgressView().controlSize(.small)
                } else {
                    Button(settings.strings.add) { submitLink() }
                        .disabled(linkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("ticket_detail_button_submit_thread_link")
                }

                Button(settings.strings.cancel) {
                    isAddingThread = false
                    linkDraft = ""
                    addFailure = nil
                }
                .buttonStyle(.borderless)
            }

            if let addFailure {
                Label(addFailure, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("ticket_detail_status_add_thread_failure")
            } else {
                Text(settings.strings.addThreadHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    func submitLink() {
        let link = linkDraft
        guard link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }

        isSubmittingLink = true
        addFailure = nil
        Task {
            let failure = await store.addThread(link: link, to: ticket)
            isSubmittingLink = false
            if let failure {
                addFailure = settings.strings.slackErrorMessage(failure)
            } else {
                linkDraft = ""
                isAddingThread = false
            }
        }
    }
}

struct InlineNoticeView: View {
    let message: String
    var detail: String?
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("detail_container_notice")
    }
}
