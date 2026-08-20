//  MenuBarIcon.swift
//  Docket

import AppKit

/// Draws the menu bar item.
///
/// `MenuBarExtra` reduces its label to a single image or a single string — a `Label` loses
/// its title, and a `Text` with an interpolated symbol loses the symbol. Showing a symbol
/// and a count together means composing them into one image.
enum MenuBarIcon {
    private static let symbolName = "checklist"
    private static let pointSize: CGFloat = 15
    private static let spacing: CGFloat = 3

    static func image(count: Int) -> NSImage {
        let icon = symbol()
        guard count > 0 else { return icon }

        let label = "\(count)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            // Template rendering turns this into a mask, so the menu bar tints it for the
            // current appearance instead of it staying black in dark mode.
            .foregroundColor: NSColor.black,
        ]
        let labelSize = label.size(withAttributes: attributes)

        let size = NSSize(
            width: icon.size.width + Self.spacing + labelSize.width,
            height: max(icon.size.height, labelSize.height)
        )
        let composed = NSImage(size: size)
        composed.lockFocus()
        icon.draw(in: NSRect(
            x: 0,
            y: (size.height - icon.size.height) / 2,
            width: icon.size.width,
            height: icon.size.height
        ))
        label.draw(
            at: NSPoint(x: icon.size.width + Self.spacing, y: (size.height - labelSize.height) / 2),
            withAttributes: attributes
        )
        composed.unlockFocus()
        composed.isTemplate = true
        return composed
    }

    private static func symbol() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
            ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.isTemplate = true
        return image
    }
}
