//  DescriptionView.swift
//  Docket

import SwiftUI

import DocketKit

/// Draws a Jira description.
///
/// Collapsible either way, since a long description buries the links and threads below it.
/// Tables and images are named rather than drawn — a gap where content should be reads as a
/// bug, whereas "open in Jira to see the table" reads as a boundary.
struct DescriptionView: View {
    @Environment(AppSettings.self) private var settings

    let blocks: [ADFBlock]
    /// Empty in the popover, where 400pt is no place for a screenshot, and empty until Jira's
    /// rendering of the description has been read.
    let media: [JiraDescriptionMedia]
    let issueURL: URL?

    @State private var isExpanded: Bool

    init(blocks: [ADFBlock], media: [JiraDescriptionMedia] = [], issueURL: URL? = nil, isCompact: Bool) {
        self.blocks = blocks
        self.media = media
        self.issueURL = issueURL
        // 400pt of popover cannot hold a few thousand characters; the window can.
        _isExpanded = State(initialValue: isCompact == false)
    }

    /// Paired only when the counts agree. A description with media inside a table has more
    /// references than places to put them, and guessing would draw the wrong picture beside
    /// the wrong sentence.
    private var placedMedia: [JiraDescriptionMedia] {
        let places = blocks.count { if case .media = $0 { true } else { false } }
        return places == media.count ? media : []
    }

    private var strandedMedia: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.strings.descriptionMediaLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(media) { item in
                MediaView(media: item, issueURL: issueURL)
            }
        }
    }

    var body: some View {
        if blocks.isEmpty == false {
            CollapsibleSection(title: settings.strings.descriptionLabel, isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ADFBlocksView(blocks: blocks, media: placedMedia, issueURL: issueURL)

                    // Media the text cannot place — inside a table, say — is still worth
                    // showing, just not pretending to know where it belongs.
                    if placedMedia.isEmpty, media.isEmpty == false {
                        strandedMedia
                    }
                }
            }
            .accessibilityIdentifier("ticket_detail_disclosure_description")
        }
    }
}

/// Draws the lines of an Atlassian Document Format body — a description or a comment.
struct ADFBlocksView: View {
    @Environment(AppSettings.self) private var settings

    let blocks: [ADFBlock]
    /// Indexed by a media block's number. Empty leaves every media block as a placeholder,
    /// which is what the popover and an unpaired description get.
    var media: [JiraDescriptionMedia] = []
    var issueURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                line(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func line(for block: ADFBlock) -> some View {
        switch block {
        case let .paragraph(spans):
            text(spans)
                .font(.callout)

        case let .heading(level, spans):
            text(spans)
                .font(level <= 2 ? .headline : .subheadline)
                .padding(.top, 2)

        case let .listItem(marker, depth, spans):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(marker)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                text(spans)
                    .font(.callout)
            }
            .padding(.leading, CGFloat(depth) * 12)

        case let .codeBlock(code):
            Text(code)
                .font(.caption.monospaced())
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 4))

        case .rule:
            Divider()

        case let .media(index):
            if index < media.count {
                MediaView(media: media[index], issueURL: issueURL)
            } else {
                Label(settings.strings.unsupportedContent("media"), systemImage: "square.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case let .unsupported(kind):
            Label(settings.strings.unsupportedContent(kind), systemImage: "square.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// One `Text` per line, so marks and links stay inline rather than wrapping as separate
    /// views.
    private func text(_ spans: [ADFSpan]) -> Text {
        spans.reduce(Text("")) { partial, span in
            var attributed = AttributedString(span.text)
            // An OptionSet: assigning twice would keep only the second mark.
            var intent: InlinePresentationIntent = []
            if span.isBold { intent.insert(.stronglyEmphasized) }
            if span.isItalic { intent.insert(.emphasized) }
            if intent.isEmpty == false { attributed.inlinePresentationIntent = intent }
            if span.isCode {
                attributed.font = .caption.monospaced()
            }
            if span.isUnderlined { attributed.underlineStyle = .single }
            if let link = span.link {
                attributed.link = link
                attributed.foregroundColor = .accentColor
            }
            return partial + Text(attributed)
        }
    }
}

/// One embedded file: an image is drawn, a video is left to Jira — a screen recording is tens
/// of megabytes and needs a player this window has no reason to become.
struct MediaView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    let media: JiraDescriptionMedia
    let issueURL: URL?

    var body: some View {
        switch media.kind {
        case .image:
            AttachmentImageView(media: media)

        case .video, .other:
            Button {
                if let issueURL { openURL(issueURL) }
            } label: {
                Label(settings.strings.openVideoInJira, systemImage: "play.rectangle")
                    .font(.caption)
            }
            .disabled(issueURL == nil)
            .accessibilityIdentifier("ticket_detail_button_description_video")
        }
    }
}
