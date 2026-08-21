//  AttachmentImageView.swift
//  Docket

import SwiftUI

import DocketKit

/// An image embedded in a description, fetched with the Jira credentials.
///
/// `AsyncImage` cannot carry an Authorization header, so the bytes come through the store,
/// which caches them in memory. Jira's scaled copy is what is drawn; the full-size one is
/// fetched only when the reader opens it.
struct AttachmentImageView: View {
    @Environment(DashboardStore.self) private var store
    @Environment(AppSettings.self) private var settings

    let media: JiraDescriptionMedia
    /// Wide enough to read a screenshot in the window, short enough that several in a row
    /// still scroll.
    var maxHeight: CGFloat = 320

    @State private var image: NSImage?
    @State private var didFail = false
    @State private var isPresentingFullSize = false

    var body: some View {
        Group {
            if let image {
                Button { isPresentingFullSize = true } label: {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
                        .clipShape(.rect(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary)
                        )
                }
                .buttonStyle(.plain)
                .help(settings.strings.openFullSize)
                .accessibilityIdentifier("ticket_detail_image_description")
            } else if didFail {
                Label(settings.strings.unsupportedContent("media"), systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 40)
            }
        }
        .task(id: media.attachmentID) {
            image = await store.attachmentImage(id: media.attachmentID, thumbnail: true)
            didFail = image == nil
        }
        .sheet(isPresented: $isPresentingFullSize) {
            FullSizeImageView(media: media)
        }
    }
}

/// The attachment at full size, which is often a screenshot too detailed for the thumbnail.
private struct FullSizeImageView: View {
    @Environment(DashboardStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let media: JiraDescriptionMedia

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                ZoomableImageView(image: image)
                    .accessibilityIdentifier("image_container_zoomable")
            } else {
                ProgressView().controlSize(.large)
            }

            Divider()

            HStack {
                Text(settings.strings.pinchToZoom)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(settings.strings.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("image_button_close")
            }
            .padding(10)
        }
        .frame(minWidth: 640, idealWidth: 900, minHeight: 480, idealHeight: 700)
        .task {
            // The thumbnail already on screen stands in until the original arrives.
            image = await store.attachmentImage(id: media.attachmentID, thumbnail: true)
            image = await store.attachmentImage(id: media.attachmentID, thumbnail: false) ?? image
        }
    }
}
