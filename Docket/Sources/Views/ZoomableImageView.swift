//  ZoomableImageView.swift
//  Docket

import AppKit
import SwiftUI

/// Keeps a document smaller than the window centred, at any magnification.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return constrained }

        // These bounds are in document coordinates, so they already account for magnification.
        if constrained.width > documentView.frame.width {
            constrained.origin.x = (documentView.frame.width - constrained.width) / 2
        }
        if constrained.height > documentView.frame.height {
            constrained.origin.y = (documentView.frame.height - constrained.height) / 2
        }
        return constrained
    }
}

/// An image the reader can pinch to zoom and drag to pan.
///
/// `NSScrollView` already does this — trackpad pinch, two-finger double tap to smart-zoom,
/// scroll to pan, and scrollers that appear only while scrolling — so it draws the image at
/// its pixel size and lets magnification do the scaling, which keeps a zoomed screenshot
/// sharp rather than interpolated.
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    var maximumMagnification: CGFloat = 8

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// Fitting again on every update would undo the reader's zoom, so it happens once per
        /// image — including when the full-size copy replaces the thumbnail.
        var fittedSize: NSSize?
    }

    func makeNSView(context: Context) -> NSScrollView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter

        let scrollView = NSScrollView()
        // AppKit's origin is the bottom left, and a clip view leaves a document smaller than
        // itself sitting there rather than in the middle.
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = imageView
        scrollView.allowsMagnification = true
        // Small enough to fit a tall screenshot into a short window.
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = maximumMagnification
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .underPageBackgroundColor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView else { return }

        if imageView.image !== image {
            imageView.image = image
            imageView.frame = NSRect(origin: .zero, size: image.size)
        }

        guard context.coordinator.fittedSize != image.size else { return }
        context.coordinator.fittedSize = image.size
        // The window has its size by the next turn of the loop; fitting before that would
        // measure an empty view.
        DispatchQueue.main.async {
            scrollView.magnify(toFit: imageView.bounds)
        }
    }
}
