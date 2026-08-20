//  DescriptionLinks.swift
//  DocketKit

import Foundation

/// The links worth acting on inside a Jira issue description.
public struct DescriptionLinks: Sendable, Equatable {
    public let figmaURL: URL?
    public let slackPermalinks: [SlackPermalink]

    public init(urls: [URL]) {
        figmaURL = urls.first(where: Self.isFigma)
        // Two links can point at the same thread — one at the root, one at a reply.
        var seen = Set<String>()
        slackPermalinks = urls
            .compactMap(SlackPermalink.init(url:))
            .filter { seen.insert("\($0.channelID):\($0.threadTS)").inserted }
    }

    static func isFigma(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "figma.com" || host.hasSuffix(".figma.com")
    }
}

public extension DescriptionLinks {
    /// Every URL an ADF document carries, in the order they appear.
    ///
    /// Links live in three places: a `link` mark's `href`, a node attribute such as an
    /// inline card's `url`, and bare text someone typed. All three are collected.
    static func urls(in document: JSONValue?) -> [URL] {
        guard let document else { return [] }
        var found: [String] = []
        collect(from: document, into: &found)
        return found.reduced().compactMap(URL.init(string:))
    }

    private static func collect(from value: JSONValue, into found: inout [String]) {
        switch value {
        case let .string(text):
            found += urlsInText(text)
        case let .array(values):
            for value in values { collect(from: value, into: &found) }
        case let .object(fields):
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
                if key == "href" || key == "url", case let .string(text) = value {
                    found.append(text)
                } else {
                    collect(from: value, into: &found)
                }
            }
        case .number, .bool, .null:
            break
        }
    }

    private static let detector = try? NSRegularExpression(pattern: "https?://[^\\s<>\"')\\]]+")

    static func urlsInText(_ text: String) -> [String] {
        guard let detector else { return [] }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).trimmingTrailingPunctuation }
        }
    }
}

extension String {
    /// Trailing punctuation is almost always sentence punctuation, not part of the link.
    var trimmingTrailingPunctuation: String {
        var text = self
        while let last = text.last, ".,;:!?".contains(last) { text.removeLast() }
        return text
    }
}
