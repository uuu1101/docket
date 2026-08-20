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

    @State private var isExpanded: Bool

    init(blocks: [ADFBlock], isCompact: Bool) {
        self.blocks = blocks
        // 400pt of popover cannot hold a few thousand characters; the window can.
        _isExpanded = State(initialValue: isCompact == false)
    }

    var body: some View {
        if blocks.isEmpty == false {
            CollapsibleSection(title: settings.strings.descriptionLabel, isExpanded: $isExpanded) {
                ADFBlocksView(blocks: blocks)
            }
            .accessibilityIdentifier("ticket_detail_disclosure_description")
        }
    }
}

/// Draws the lines of an Atlassian Document Format body — a description or a comment.
struct ADFBlocksView: View {
    @Environment(AppSettings.self) private var settings

    let blocks: [ADFBlock]

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
