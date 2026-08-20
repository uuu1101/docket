//  SlackPermalinkTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Parsing a pasted Slack link")
struct SlackPermalinkTests {
    @Test("A root message link yields its channel and timestamp")
    func rootLink() throws {
        let link = try #require(SlackPermalink(text: "https://example.slack.com/archives/C0123ABC/p1712345678100100"))
        #expect(link.channelID == "C0123ABC")
        #expect(link.threadTS == "1712345678.100100")
    }

    @Test("A reply link resolves to the thread root, not the reply")
    func replyLink() throws {
        let link = try #require(SlackPermalink(
            text: "https://example.slack.com/archives/C0123ABC/p1712349999200200?thread_ts=1712345678.100100&cid=C0123ABC"
        ))
        #expect(link.threadTS == "1712345678.100100")
        #expect(link.threadURL.absoluteString == "https://example.slack.com/archives/C0123ABC/p1712345678100100")
    }

    @Test("The cid parameter wins over the path when both are present")
    func cidPreferred() throws {
        let link = try #require(SlackPermalink(
            text: "https://example.slack.com/archives/C0000000/p1712345678100100?cid=C0123ABC"
        ))
        #expect(link.channelID == "C0123ABC")
    }

    @Test("Surrounding whitespace from a paste is tolerated")
    func trimsWhitespace() throws {
        let link = try #require(SlackPermalink(text: "\n  https://example.slack.com/archives/C1/p1712345678100100  \n"))
        #expect(link.channelID == "C1")
    }

    @Test("A DM link parses just like a channel link")
    func directMessageLink() throws {
        let link = try #require(SlackPermalink(text: "https://example.slack.com/archives/D0123ABC/p1712345678100100"))
        #expect(link.channelID == "D0123ABC")
    }

    @Test("Anything that is not a Slack message link is refused", arguments: [
        "",
        "   ",
        "not a url",
        "https://example.slack.com/",
        "https://example.slack.com/archives/C0123ABC",
        "https://example.slack.com/archives/C0123ABC/1712345678100100",
        "https://example.slack.com/archives/C0123ABC/pabcdef1234567",
        "https://example.slack.com/archives/C0123ABC/p12345",
        "https://example.com/archives/C1/p1712345678100100/../..",
    ])
    func rejectsNonLinks(text: String) {
        #expect(SlackPermalink(text: text) == nil)
    }

    @Test("The timestamp keeps its microseconds intact")
    func timestampPrecision() {
        #expect(SlackPermalink.timestamp(fromMessageSegment: "p1712345678100100") == "1712345678.100100")
        #expect(SlackPermalink.timestamp(fromMessageSegment: "p1712345678000001") == "1712345678.000001")
    }

    @Test("A segment that is not a message id yields nil", arguments: ["1712345678100100", "p", "p123456", "pxxxxxxx"])
    func rejectsBadSegments(segment: String) {
        #expect(SlackPermalink.timestamp(fromMessageSegment: segment) == nil)
    }
}
