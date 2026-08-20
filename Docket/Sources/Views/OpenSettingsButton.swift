//  OpenSettingsButton.swift
//  Docket

import AppKit
import SwiftUI

/// Opens the Settings scene and brings it to the front.
///
/// The app runs as an accessory (`LSUIElement`) app, so it never becomes the active
/// application on its own. Opening Settings without activating leaves the window behind
/// whatever the user was looking at, which reads as the button doing nothing.
struct OpenSettingsButton<Label: View>: View {
    @Environment(\.openSettings) private var openSettings

    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            label()
        }
    }
}
