//  CollapsibleSection.swift
//  Docket

import SwiftUI

/// A section the reader opens by clicking its title or its chevron.
///
/// `DisclosureGroup` on macOS reacts only to its triangle — a target a few points wide, beside
/// a title that looks clickable and is not. The header is a button here instead, so the whole
/// row is the target. Anything in `accessory` stays outside that button, which is what keeps a
/// link in the header reachable.
struct CollapsibleSection<Content: View, Accessory: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(title)
                            .font(.headline)
                    }
                    // Without this the gap between chevron and title is not part of the target.
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                accessory()
            }

            if isExpanded {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension CollapsibleSection where Accessory == EmptyView {
    init(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, isExpanded: isExpanded, accessory: { EmptyView() }, content: content)
    }
}
