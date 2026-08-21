//  SyncEngineTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

/// Stand-in for Slack: hands back fixed thread details, and fails the specific
/// conversations a test asks it to fail.
struct StubSlackAPI: SlackAPI {
    var details: [String: SlackThreadDetail] = [:]
    var failures: [String: SlackError] = [:]
    var names: [String: String] = [:]
    var channels: [String: SlackChannelInfo] = [:]

    func identity() async throws(SlackError) -> SlackIdentity {
        SlackIdentity(userID: "U1", userName: "theo", teamName: "MVL")
    }

    func threadDetail(channelID: String, threadTS: String) async throws(SlackError) -> SlackThreadDetail? {
        let key = "\(channelID):\(threadTS)"
        if let failure = failures[key] { throw failure }
        return details[key]
    }

    func displayNames(for userIDs: [String]) async -> [String: String] { names }

    func channelInfo(id: String) async -> SlackChannelInfo? { channels[id] }
}

struct UnusedJiraAPI: JiraAPI {
    func account() async throws(JiraError) -> JiraAccount { JiraAccount(accountID: "a", displayName: "d") }
    func issues(jql: String, maxResults: Int, extraFieldID: String?) async throws(JiraError) -> [JiraIssue] { [] }
    func fieldID(named name: String) async throws(JiraError) -> String? { nil }
    func transitions(issueKey: String) async throws(JiraError) -> [JiraTransition] { [] }
    func performTransition(issueKey: String, transitionID: String) async throws(JiraError) {}
    func descriptionMedia(issueKey: String) async throws(JiraError) -> [JiraDescriptionMedia] { [] }
    func attachment(id: String, thumbnail: Bool) async throws(JiraError) -> Data { Data() }
    func comments(issueKey: String, limit: Int) async throws(JiraError) -> JiraComments {
        JiraComments(comments: [], total: 0)
    }
}

@Suite("Fetching an attached thread")
struct SyncEngineThreadTests {
    private let permalink = URL(string: "https://example.slack.com/archives/C1/p1712345678100100")!

    private func detail(replies: Int = 4) -> SlackThreadDetail {
        SlackThreadDetail(
            rootText: "Can anyone reproduce this?",
            rootUserID: "U1",
            replyCount: replies,
            participantIDs: ["U1", "U2"],
            lastActivityAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastReplyUserID: "U2"
        )
    }

    private func engine(_ slack: StubSlackAPI) -> SyncEngine {
        SyncEngine(jira: UnusedJiraAPI(), slack: slack)
    }

    private func fetch(_ slack: StubSlackAPI, knownChannelName: String? = nil) async throws -> ThreadSnapshot? {
        try await engine(slack).thread(
            issueKey: "APP-1",
            channelID: "C1",
            threadTS: "1712345678.100100",
            permalink: permalink,
            knownChannelName: knownChannelName,
            origin: .manual
        )
    }

    @Test("A channel thread comes back with its name and participants resolved")
    func channelThread() async throws {
        var slack = StubSlackAPI()
        slack.details = ["C1:1712345678.100100": detail()]
        slack.channels = ["C1": SlackChannelInfo(id: "C1", name: "ios-dev", isDirectMessage: false, userID: nil)]
        slack.names = ["U1": "jihoon", "U2": "theo"]

        let snapshot = try #require(await fetch(slack))
        #expect(snapshot.channelName == "ios-dev")
        #expect(snapshot.rootAuthorName == "jihoon")
        #expect(snapshot.lastReplyAuthorName == "theo")
        #expect(snapshot.replyCount == 4)
        #expect(snapshot.participantNames == ["jihoon", "theo"])
    }

    @Test("A known channel name skips the lookup entirely")
    func knownChannelNameSkipsLookup() async throws {
        var slack = StubSlackAPI()
        slack.details = ["C1:1712345678.100100": detail()]
        // No channel stubbed: if the lookup ran, the name would fall back to the id.
        let snapshot = try #require(await fetch(slack, knownChannelName: "ios-dev"))
        #expect(snapshot.channelName == "ios-dev")
    }

    @Test("A DM is labelled with the person on the other side")
    func directMessageLabel() async throws {
        var slack = StubSlackAPI()
        slack.details = ["C1:1712345678.100100": detail()]
        slack.channels = ["C1": SlackChannelInfo(id: "C1", name: nil, isDirectMessage: true, userID: "U9")]
        slack.names = ["U1": "jihoon", "U2": "theo", "U9": "jinho"]

        let snapshot = try #require(await fetch(slack))
        #expect(snapshot.channelName == "jinho")
    }

    @Test("An unreadable channel falls back to its id rather than showing nothing")
    func unnamedChannelFallsBackToID() async throws {
        var slack = StubSlackAPI()
        slack.details = ["C1:1712345678.100100": detail()]
        let snapshot = try #require(await fetch(slack))
        #expect(snapshot.channelName == "C1")
    }

    @Test("A thread that no longer exists yields nil, not an empty card")
    func missingThread() async throws {
        #expect(try await fetch(StubSlackAPI()) == nil)
    }

    @Test("A conversation the token cannot read reports the missing scope")
    func missingScopePropagates() async {
        var slack = StubSlackAPI()
        slack.failures = ["C1:1712345678.100100": .missingScope("im:history")]
        await #expect(throws: SlackError.missingScope("im:history")) { try await fetch(slack) }
    }

    @Test("Without Slack configured the engine refuses rather than pretending")
    func slackNotConfigured() async {
        let engine = SyncEngine(jira: UnusedJiraAPI(), slack: nil)
        await #expect(throws: SlackError.notConfigured) {
            try await engine.thread(
                issueKey: "APP-1",
                channelID: "C1",
                threadTS: "1.1",
                permalink: permalink,
                knownChannelName: nil,
                origin: .manual
            )
        }
    }
}

@Suite("Thread identity")
struct SnapshotIdentityTests {
    @Test("The same thread attached to two tickets gets a row for each")
    func scopedPerTicket() {
        let first = SyncEngine.snapshotID(issueKey: "APP-1", channelID: "C1", threadTS: "1.1")
        let second = SyncEngine.snapshotID(issueKey: "APP-2", channelID: "C1", threadTS: "1.1")
        #expect(first != second)
    }

    @Test("The same thread on the same ticket keeps one stable identity")
    func stableWithinTicket() {
        #expect(
            SyncEngine.snapshotID(issueKey: "APP-1", channelID: "C1", threadTS: "1.1")
                == SyncEngine.snapshotID(issueKey: "APP-1", channelID: "C1", threadTS: "1.1")
        )
    }
}

@Suite("Recovering an unresolved channel name")
struct ChannelNameRecoveryTests {
    private let permalink = URL(string: "https://example.slack.com/archives/C1/p1712345678100100")!

    private func slack(named name: String?) -> StubSlackAPI {
        var slack = StubSlackAPI()
        slack.details = ["C1:1712345678.100100": SlackThreadDetail(
            rootText: "…",
            rootUserID: "U1",
            replyCount: 1,
            participantIDs: ["U1"],
            lastActivityAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastReplyUserID: nil
        )]
        if let name {
            slack.channels = ["C1": SlackChannelInfo(id: "C1", name: name, isDirectMessage: false, userID: nil)]
        }
        return slack
    }

    private func fetch(_ api: StubSlackAPI, knownChannelName: String?) async throws -> ThreadSnapshot? {
        try await SyncEngine(jira: UnusedJiraAPI(), slack: api).thread(
            issueKey: "APP-1",
            channelID: "C1",
            threadTS: "1712345678.100100",
            permalink: permalink,
            knownChannelName: knownChannelName,
            origin: .manual
        )
    }

    @Test("A stored name that is really the channel id gets looked up again")
    func idFallbackIsRetried() async throws {
        let snapshot = try #require(await fetch(slack(named: "ios-dev"), knownChannelName: "C1"))
        #expect(snapshot.channelName == "ios-dev")
    }

    @Test("A real stored name is trusted and not looked up")
    func realNameIsKept() async throws {
        // No channel stubbed: a lookup would fall back to the id.
        let snapshot = try #require(await fetch(slack(named: nil), knownChannelName: "ios-dev"))
        #expect(snapshot.channelName == "ios-dev")
    }

    @Test("Still unresolvable means the id again, not an empty label")
    func stillUnresolved() async throws {
        let snapshot = try #require(await fetch(slack(named: nil), knownChannelName: "C1"))
        #expect(snapshot.channelName == "C1")
    }
}
