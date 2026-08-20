//  GitHubClientTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("GitHub configuration")
struct GitHubConfigurationTests {
    @Test("A configuration needs a token and at least one repository", arguments: [
        ("", "acme/demo-ios"), ("token", ""), ("", ""), ("token", "not-a-repo"),
    ])
    func requiresBoth(token: String, repositories: String) {
        #expect(GitHubConfiguration(token: token, repositories: repositories) == nil)
    }

    @Test("Repositories are accepted however they were typed", arguments: [
        "acme/demo-ios",
        "  acme/demo-ios  ",
        "https://github.com/acme/demo-ios",
        "git@github.com/acme/demo-ios.git",
        "acme/demo-ios/",
    ])
    func parsesEntries(raw: String) {
        #expect(GitHubConfiguration.parse(raw) == ["acme/demo-ios"])
    }

    @Test("Several repositories split on commas, spaces and newlines")
    func parsesSeveral() {
        let parsed = GitHubConfiguration.parse("acme/demo-ios, acme/demo-server\nacme/demo-web")
        #expect(parsed == ["acme/demo-ios", "acme/demo-server", "acme/demo-web"])
    }

    @Test("A repository listed twice is only fetched once")
    func deduplicates() {
        #expect(GitHubConfiguration.parse("acme/demo-ios, ACME/DEMO-IOS").count == 1)
    }

    @Test("Entries that are not owner/repo are dropped")
    func dropsMalformed() {
        #expect(GitHubConfiguration.parse("demo-ios, acme, acme/demo-ios/extra") == [])
    }
}

@Suite("Matching pull requests to a ticket")
struct PullRequestMatcherTests {
    private func pullRequest(_ number: Int, title: String = "", branch: String = "") -> GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: title,
            urlString: "https://github.com/acme/demo-ios/pull/\(number)",
            headRef: branch
        )
    }

    @Test("A key in the title matches")
    func matchesTitle() {
        #expect(PullRequestMatcher.mentions(issueKey: "APP-29133", in: "[P2] APP-29133 Drop the return address"))
    }

    @Test("A key in the branch name matches — the reason this replaced search")
    func matchesBranch() {
        #expect(PullRequestMatcher.mentions(issueKey: "APP-29858", in: "fix/APP-29858-sbp-link-expiry-toast"))
    }

    @Test("Case does not matter, because branches are often lowercased")
    func caseInsensitive() {
        #expect(PullRequestMatcher.mentions(issueKey: "APP-29858", in: "fix/app-29858-toast"))
    }

    @Test("A shorter key does not claim a longer one")
    func respectsDigitBoundary() {
        #expect(PullRequestMatcher.mentions(issueKey: "APP-2913", in: "APP-29133 something") == false)
    }

    @Test("A key embedded in another word does not match")
    func respectsLeadingBoundary() {
        #expect(PullRequestMatcher.mentions(issueKey: "APP-1", in: "XAPP-1 something") == false)
    }

    @Test("An unrelated ticket does not match")
    func unrelated() {
        #expect(PullRequestMatcher.mentions(issueKey: "APP-1", in: "fix/APP-2-other") == false)
    }

    @Test("Empty input never matches", arguments: [("", "text"), ("APP-1", "")])
    func emptyInput(key: String, text: String) {
        #expect(PullRequestMatcher.mentions(issueKey: key, in: text) == false)
    }

    @Test("Only the matching pull requests are linked")
    func linksMatchesOnly() {
        let links = PullRequestMatcher.links(for: "APP-29133", in: [
            pullRequest(1388, title: "[P2] APP-29133 Drop the return address"),
            pullRequest(1390, branch: "fix/APP-29133-follow-up"),
            pullRequest(1400, title: "chore: unrelated", branch: "chore/bump"),
        ])
        #expect(links.map(\.name) == ["#1388", "#1390"])
    }

    @Test("A ticket with no pull requests gets none")
    func noMatches() {
        #expect(PullRequestMatcher.links(for: "APP-1", in: [pullRequest(1, title: "chore")]).isEmpty)
    }
}

@Suite("Reading the pull request list")
struct GitHubDecodingTests {
    private func pullRequests(_ json: String) throws -> [GitHubPullRequest] {
        try JSONDecoder().decode([PullRequestRemoteModel].self, from: Data(json.utf8)).compactMap(\.asEntity)
    }

    @Test("A listed pull request keeps its number, title, URL and branch")
    func decodes() throws {
        let found = try pullRequests("""
        [{"number":1388,"title":"[P2] APP-29133 Drop the return address",
          "html_url":"https://github.com/acme/demo-ios/pull/1388",
          "head":{"ref":"fix/APP-29133-return-address"}}]
        """)
        #expect(found.first?.number == 1388)
        #expect(found.first?.headRef == "fix/APP-29133-return-address")
        #expect(found.first?.asLink.name == "#1388")
    }

    @Test("A missing branch does not lose the pull request")
    func toleratesMissingHead() throws {
        let found = try pullRequests(#"[{"number":1,"html_url":"https://github.com/o/r/pull/1"}]"#)
        #expect(found.count == 1)
        #expect(found.first?.headRef == "")
    }

    @Test("An entry without a URL is dropped rather than shown as a dead button")
    func dropsEntriesWithoutURL() throws {
        #expect(try pullRequests(#"[{"number":1}]"#).isEmpty)
    }

    @Test("An empty page decodes to nothing")
    func emptyPage() throws {
        #expect(try pullRequests("[]").isEmpty)
    }
}
