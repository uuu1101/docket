//  SlackDeepLinkTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Opening a Slack link in the app")
struct SlackDeepLinkTests {
    private let team = "T02ABCDEFG"

    private func appURL(_ permalink: String, teamID: String? = nil) -> URL? {
        SlackDeepLink.appURL(for: URL(string: permalink)!, teamID: teamID ?? team)
    }

    @Test("A message permalink names the workspace, channel and timestamp")
    func buildsMessageLink() throws {
        let url = try #require(appURL("https://mvllabs.slack.com/archives/C06NAUH75S6/p1756705694723339"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(url.scheme == "slack")
        #expect(url.host == "channel")
        #expect(items.first { $0.name == "team" }?.value == team)
        #expect(items.first { $0.name == "id" }?.value == "C06NAUH75S6")
        // The dot Slack's own API uses, restored from the permalink's run of digits.
        #expect(items.first { $0.name == "message" }?.value == "1756705694.723339")
        #expect(items.contains { $0.name == "thread_ts" } == false)
    }

    @Test("A reply carries its parent, so the app opens the thread rather than the channel")
    func keepsThreadParent() throws {
        let url = try #require(appURL(
            "https://mvllabs.slack.com/archives/C06NAUH75S6/p1756705694723339?thread_ts=1756700000.111111&cid=C06NAUH75S6"
        ))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.first { $0.name == "thread_ts" }?.value == "1756700000.111111")
        #expect(items.first { $0.name == "message" }?.value == "1756705694.723339")
    }

    @Test("Without the workspace id there is no deep link to build")
    func needsTeamID() {
        #expect(appURL("https://mvllabs.slack.com/archives/C1/p1756705694723339", teamID: "") == nil)
    }

    @Test("Anything that is not a Slack message is left to the browser")
    func ignoresOtherAddresses() {
        let others = [
            "https://www.figma.com/design/2rKx6XGOJDlEXRO7SqFoJn/Driver-App_Master",
            "https://example.atlassian.net/browse/APP-22628",
            "https://mvllabs.slack.com/team/U123456",
            "https://notslack.com/archives/C1/p1756705694723339",
            "https://mvllabs.slack.com/archives/C1",
        ]

        for address in others {
            #expect(appURL(address) == nil, "\(address) should stay in the browser")
        }
    }

    @Test("A permalink whose timestamp is malformed is left alone")
    func ignoresMalformedTimestamp() {
        #expect(appURL("https://mvllabs.slack.com/archives/C1/1756705694723339") == nil)
        #expect(appURL("https://mvllabs.slack.com/archives/C1/p12345") == nil)
        #expect(appURL("https://mvllabs.slack.com/archives/C1/pabcdefghij123456") == nil)
    }
}

@Suite("Which addresses in a description become links")
struct DescriptionLinkSchemeTests {
    @Test("A Jira attachment's blob address is text, not a link")
    func blobIsNotALink() {
        #expect(ADFDocument.openableURL("blob:https://media.staging.atl-paas.net/?type=file&id=649a2f29") == nil)
    }

    @Test("Addresses a browser can open stay links", arguments: [
        "https://example.atlassian.net/browse/APP-22628",
        "http://admin.example.com/records/29d5f8ac",
        "mailto:someone@example.com",
    ])
    func openableStaysALink(address: String) {
        #expect(ADFDocument.openableURL(address) != nil)
    }

    @Test("Other schemes are dropped rather than drawn as dead links", arguments: [
        "file:///Users/theo/secret.txt",
        "javascript:alert(1)",
        "data:text/html,<h1>hi</h1>",
    ])
    func otherSchemesAreDropped(address: String) {
        #expect(ADFDocument.openableURL(address) == nil)
    }
}
