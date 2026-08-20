//  SlackPermalink.swift
//  DocketKit

import Foundation

/// A Slack message link, as produced by "Copy link" on any message.
///
/// `https://team.slack.com/archives/C0123ABC/p1712345678100100?thread_ts=…&cid=…`
///
/// Pasting a reply's link is expected and handled: `thread_ts` names the root, so the link
/// resolves to the conversation rather than to the message inside it.
public struct SlackPermalink: Sendable, Equatable {
    public let channelID: String
    public let threadTS: String
    public let url: URL

    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty.not,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        self.init(url: url)
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              host == "slack.com" || host.hasSuffix(".slack.com")
        else { return nil }

        let segments = components.path.split(separator: "/").map(String.init)
        guard let archivesIndex = segments.firstIndex(of: "archives"),
              segments.count > archivesIndex + 2
        else { return nil }

        let channelFromPath = segments[archivesIndex + 1]
        let messageSegment = segments[archivesIndex + 2]
        guard let messageTS = Self.timestamp(fromMessageSegment: messageSegment) else { return nil }

        let query = components.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value?.nilIfEmpty
        }

        channelID = value("cid") ?? channelFromPath
        // A reply link carries the root's timestamp; a root link carries only its own.
        threadTS = value("thread_ts") ?? messageTS
        self.url = url
    }

    /// `p1712345678100100` holds the timestamp with its decimal point removed: the last six
    /// digits are the microseconds.
    static func timestamp(fromMessageSegment segment: String) -> String? {
        guard segment.hasPrefix("p") else { return nil }
        let digits = segment.dropFirst()
        guard digits.count > 6, digits.allSatisfy(\.isNumber) else { return nil }

        let split = digits.index(digits.endIndex, offsetBy: -6)
        return "\(digits[digits.startIndex ..< split]).\(digits[split...])"
    }

    /// The link that opens the thread at its root.
    public var threadURL: URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var segments = components?.path.split(separator: "/").map(String.init) ?? []
        if let last = segments.indices.last, segments[last].hasPrefix("p") {
            segments[last] = "p" + threadTS.replacingOccurrences(of: ".", with: "")
        }
        components?.path = "/" + segments.joined(separator: "/")
        components?.queryItems = nil
        return components?.url ?? url
    }
}
