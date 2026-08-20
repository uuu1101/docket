//  DescriptionLinksTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Links inside a Jira description")
struct DescriptionLinksTests {
    private func document(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    @Test("A link mark's href is found")
    func linkMark() throws {
        let urls = DescriptionLinks.urls(in: try document("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","text":"design","marks":[
            {"type":"link","attrs":{"href":"https://www.figma.com/design/abc/Booking"}}]}]}]}
        """))
        #expect(urls.map(\.absoluteString) == ["https://www.figma.com/design/abc/Booking"])
    }

    @Test("An inline card's url is found")
    func inlineCard() throws {
        let urls = DescriptionLinks.urls(in: try document("""
        {"type":"doc","content":[{"type":"inlineCard","attrs":{"url":"https://www.figma.com/file/xyz/Onboarding"}}]}
        """))
        #expect(urls.first?.absoluteString == "https://www.figma.com/file/xyz/Onboarding")
    }

    @Test("A URL typed straight into the text is found")
    func bareText() throws {
        let urls = DescriptionLinks.urls(in: try document("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","text":"see https://www.figma.com/design/abc/Booking for the flow"}]}]}
        """))
        #expect(urls.first?.absoluteString == "https://www.figma.com/design/abc/Booking")
    }

    @Test("Sentence punctuation is not swallowed into the link")
    func trailingPunctuation() throws {
        let urls = DescriptionLinks.urls(in: try document("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","text":"디자인은 https://www.figma.com/design/abc 입니다."}]}]}
        """))
        #expect(urls.first?.absoluteString == "https://www.figma.com/design/abc")
    }

    @Test("An unknown node type does not hide the links inside it")
    func unknownNodeType() throws {
        let urls = DescriptionLinks.urls(in: try document("""
        {"type":"doc","content":[{"type":"somethingAtlassianAddedLater","content":[
          {"type":"text","text":"https://www.figma.com/design/abc"}]}]}
        """))
        #expect(urls.isEmpty == false)
    }

    @Test("No description means no links and no crash")
    func missingDescription() {
        #expect(DescriptionLinks.urls(in: nil).isEmpty)
    }

    @Test("The same URL twice is reported once")
    func deduplicates() throws {
        let urls = DescriptionLinks.urls(in: try document("""
        {"type":"doc","content":[{"type":"paragraph","content":[
          {"type":"text","text":"https://www.figma.com/design/abc https://www.figma.com/design/abc"}]}]}
        """))
        #expect(urls.count == 1)
    }
}

@Suite("Classifying the links found")
struct LinkClassificationTests {
    private func links(_ strings: [String]) -> DescriptionLinks {
        DescriptionLinks(urls: strings.compactMap(URL.init(string:)))
    }

    @Test("A figma.com link is picked out", arguments: [
        "https://www.figma.com/design/abc/Booking",
        "https://figma.com/file/abc",
        "https://www.figma.com/proto/abc/Flow",
        "https://www.figma.com/board/abc/Notes",
    ])
    func figmaVariants(link: String) {
        #expect(links([link]).figmaURL?.absoluteString == link)
    }

    @Test("A lookalike host is not treated as Figma")
    func figmaLookalike() {
        #expect(links(["https://notfigma.com/design/abc"]).figmaURL == nil)
        #expect(links(["https://figma.com.evil.test/design/abc"]).figmaURL == nil)
    }

    @Test("The first Figma link wins when several are present")
    func firstFigmaWins() {
        let found = links(["https://www.figma.com/design/one", "https://www.figma.com/design/two"])
        #expect(found.figmaURL?.absoluteString == "https://www.figma.com/design/one")
    }

    @Test("Slack message links become thread references")
    func slackLinks() {
        let found = links([
            "https://example.slack.com/archives/C1/p1712345678100100",
            "https://www.figma.com/design/abc",
        ])
        #expect(found.slackPermalinks.count == 1)
        #expect(found.slackPermalinks.first?.channelID == "C1")
        #expect(found.figmaURL != nil)
    }

    @Test("A root link and a reply link to the same thread collapse into one")
    func slackDeduplication() {
        let found = links([
            "https://example.slack.com/archives/C1/p1712345678100100",
            "https://example.slack.com/archives/C1/p1712349999200200?thread_ts=1712345678.100100&cid=C1",
        ])
        #expect(found.slackPermalinks.count == 1)
    }

    @Test("Unrelated links are ignored entirely")
    func unrelatedLinks() {
        let found = links(["https://example.com/spec", "https://example.atlassian.net/browse/APP-1"])
        #expect(found.figmaURL == nil)
        #expect(found.slackPermalinks.isEmpty)
    }
}
