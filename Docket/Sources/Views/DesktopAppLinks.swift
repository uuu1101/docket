//  DesktopAppLinks.swift
//  Docket

import AppKit
import SwiftUI

import DocketKit

/// Sends Slack and Figma links to their desktop apps, and everything else where it was already
/// going.
///
/// Applied once around a subtree, this covers links inside a description or a comment as well
/// as the thread and Figma buttons, since all of them go through `openURL`. The open happens
/// here rather than being handed back as a `systemAction`, because that reports nothing: if the
/// app is missing, the deep link fails silently and the reader is left with a dead click.
private struct DesktopAppLinks: ViewModifier {
    let slackTeamID: String

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard let appURL = desktopURL(for: url) else { return .systemAction }
            return NSWorkspace.shared.open(appURL) ? .handled : .systemAction
        })
    }

    private func desktopURL(for url: URL) -> URL? {
        SlackDeepLink.appURL(for: url, teamID: slackTeamID) ?? FigmaDeepLink.appURL(for: url)
    }
}

extension View {
    /// An empty `slackTeamID` — an old connection, or none — leaves Slack links in the browser;
    /// Figma needs nothing stored.
    func desktopAppLinks(slackTeamID: String) -> some View {
        modifier(DesktopAppLinks(slackTeamID: slackTeamID))
    }
}
