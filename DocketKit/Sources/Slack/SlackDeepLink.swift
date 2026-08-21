//  SlackDeepLink.swift
//  DocketKit

import Foundation

/// Turns a Slack web permalink into the address that opens the desktop app.
///
/// A permalink pasted into a ticket or returned by the API points at the web client; the same
/// message in the app is `slack://channel?team=…&id=…&message=…`. Every `slack://` form
/// requires the workspace id, which no permalink carries — hence the separate `teamID`.
public enum SlackDeepLink {
    /// `nil` when the address is not a Slack message, or the workspace is unknown, in which
    /// case the caller keeps the original link.
    public static func appURL(for permalink: URL, teamID: String) -> URL? {
        guard teamID.isEmpty == false,
              let components = URLComponents(url: permalink, resolvingAgainstBaseURL: false),
              isSlackHost(components.host)
        else { return nil }

        // /archives/<channel>/p<ts without its dot>
        let path = components.path.split(separator: "/").map(String.init)
        guard path.count >= 3, path[0] == "archives" else { return nil }

        let channelID = path[1]
        guard channelID.isEmpty == false, let messageTS = timestamp(fromPathComponent: path[2]) else { return nil }

        var deepLink = URLComponents()
        deepLink.scheme = "slack"
        deepLink.host = "channel"
        var query = [
            URLQueryItem(name: "team", value: teamID),
            URLQueryItem(name: "id", value: channelID),
            URLQueryItem(name: "message", value: messageTS),
        ]
        // A permalink to a reply names its parent, and without it the app opens the channel at
        // the reply's position rather than opening the thread.
        if let threadTS = components.queryItems?.first(where: { $0.name == "thread_ts" })?.value {
            query.append(URLQueryItem(name: "thread_ts", value: threadTS))
        }
        deepLink.queryItems = query
        return deepLink.url
    }

    /// A suffix match alone would accept `notslack.com`, so the boundary has to be a dot.
    private static func isSlackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "slack.com" || host.hasSuffix(".slack.com")
    }

    /// `p1756705694723339` → `1756705694.723339`, the form every Slack API uses.
    private static func timestamp(fromPathComponent component: String) -> String? {
        guard component.hasPrefix("p") else { return nil }
        let digits = component.dropFirst()
        guard digits.count > 6, digits.allSatisfy(\.isNumber) else { return nil }
        let split = digits.index(digits.endIndex, offsetBy: -6)
        return "\(digits[digits.startIndex ..< split]).\(digits[split...])"
    }
}
