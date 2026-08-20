//  TransitionTests.swift
//  DocketKitTests

import Foundation
import SwiftData
import Testing

@testable import DocketKit

@Suite("Reading the moves a workflow allows")
struct TransitionDecodingTests {
    private func transitions(_ json: String) throws -> [JiraTransition] {
        try JSONDecoder().decode(JiraTransitionsResponse.self, from: Data(json.utf8))
            .transitions?.compactMap(\.asEntity) ?? []
    }

    @Test("A move keeps its id and the status it lands on")
    func decodes() throws {
        let found = try transitions("""
        {"transitions":[{"id":"31","name":"Start Review",
          "to":{"name":"검토 중","statusCategory":{"key":"indeterminate"}}}]}
        """)
        #expect(found.count == 1)
        #expect(found.first?.id == "31")
        #expect(found.first?.name == "Start Review")
        #expect(found.first?.toStatusName == "검토 중")
        #expect(found.first?.toStatusCategory == .inProgress)
    }

    @Test("The status override applies to the destination too")
    func appliesStatusOverride() throws {
        let found = try transitions("""
        {"transitions":[{"id":"41","name":"Ready","to":{"name":"READY FOR QA","statusCategory":{"key":"done"}}}]}
        """)
        // Jira calls it done; the dashboard treats it as work still in flight.
        #expect(found.first?.toStatusCategory == .inProgress)
    }

    @Test("Required fields are reported so the move can be refused up front")
    func requiredFields() throws {
        let found = try transitions("""
        {"transitions":[{"id":"51","name":"Done","to":{"name":"완료","statusCategory":{"key":"done"}},
          "fields":{"resolution":{"required":true},"comment":{"required":false}}}]}
        """)
        #expect(found.first?.requiredFields == ["resolution"])
    }

    @Test("A move with no fields needs nothing")
    func noRequiredFields() throws {
        let found = try transitions("""
        {"transitions":[{"id":"11","name":"TO DO","to":{"name":"해야 할 일","statusCategory":{"key":"new"}}}]}
        """)
        #expect(found.first?.requiredFields.isEmpty == true)
    }

    @Test("An entry without a destination is dropped rather than shown as a blank option")
    func dropsIncomplete() throws {
        #expect(try transitions(#"{"transitions":[{"id":"1","name":"Nowhere"}]}"#).isEmpty)
    }

    @Test("No permission means no moves, not an error", arguments: [
        #"{"transitions":[]}"#, "{}",
    ])
    func emptyList(json: String) throws {
        #expect(try transitions(json).isEmpty)
    }

    @Test("An unknown category falls back to to-do rather than failing")
    func unknownCategory() throws {
        let found = try transitions("""
        {"transitions":[{"id":"61","name":"Odd","to":{"name":"뭔가","statusCategory":{"key":"whatever"}}}]}
        """)
        #expect(found.first?.toStatusCategory == .todo)
    }

    @Test("A required field is shown by its name, falling back to its id")
    func requiredFieldNames() throws {
        let found = try transitions("""
        {"transitions":[{"id":"51","name":"Done","to":{"name":"완료","statusCategory":{"key":"done"}},
          "fields":{"customfield_10104":{"required":true,"name":"Sprint"},"resolution":{"required":true}}}]}
        """)
        #expect(found.first?.requiredFields == ["Sprint", "resolution"])
    }
}

@MainActor
@Suite("Applying a move through the store")
struct TransitionStoreTests {
    /// A Jira double whose transition behavior the test scripts.
    private struct ScriptedJiraAPI: JiraAPI {
        var failure: JiraError?

        func account() async throws(JiraError) -> JiraAccount { JiraAccount(accountID: "a", displayName: "d") }
        func issues(jql: String, maxResults: Int, extraFieldID: String?) async throws(JiraError) -> [JiraIssue] { [] }
        func fieldID(named name: String) async throws(JiraError) -> String? { nil }
        func transitions(issueKey: String) async throws(JiraError) -> [JiraTransition] { [] }
        func performTransition(issueKey: String, transitionID: String) async throws(JiraError) {
            if let failure { throw failure }
        }
        func comments(issueKey: String, limit: Int) async throws(JiraError) -> JiraComments {
            JiraComments(comments: [], total: 0)
        }
    }

    private func makeStore(jira: ScriptedJiraAPI = ScriptedJiraAPI()) throws -> DashboardStore {
        let schema = Schema([Ticket.self, SlackThread.self])
        let url = URL.temporaryDirectory.appending(path: "docket-\(UUID().uuidString).store")
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "dev.taetae.docket.tests.\(UUID().uuidString)")!,
            keychain: KeychainStore(service: "dev.taetae.docket.tests.\(UUID().uuidString)")
        )
        settings.jiraSiteURL = "https://example.atlassian.net"
        settings.jiraEmail = "a@example.com"
        settings.jiraAPIToken = "token"
        let store = DashboardStore(
            settings: settings,
            container: try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
        )
        store.makeJiraAPI = { _ in jira }
        return store
    }

    private func issue(key: String, status: String = "To Do", category: StatusCategory = .todo) -> JiraIssue {
        JiraIssue(
            key: key,
            summary: "Recover an unsaved draft after reconnect",
            statusName: status,
            statusCategory: category,
            priorityName: "P2",
            issueType: "Bug",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            browseURL: URL(string: "https://example.atlassian.net/browse/\(key)")!
        )
    }

    private let startReview = JiraTransition(
        id: "21",
        name: "Start Review",
        toStatusName: "In Review",
        toStatusCategory: .inProgress
    )

    @Test("A successful move lands immediately and counts as seen")
    func moveAppliesOptimistically() async throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        let failure = await store.apply(startReview, to: ticket)

        #expect(failure == nil)
        #expect(ticket.statusName == "In Review")
        #expect(ticket.statusCategory == .inProgress)
        #expect(ticket.seenStatusName == "In Review")
        #expect(ticket.needsAttention == false)
    }

    @Test("A refresh fetched before the move cannot revert it")
    func staleRefreshDoesNotRevert() async throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)
        _ = await store.apply(startReview, to: ticket)

        // Fetched before the move: the old status must lose.
        store.apply([issue(key: "APP-1")], fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(store.tickets.first?.statusName == "In Review")
        #expect(store.tickets.first?.needsAttention == false)

        // Fetched after the move: the server is the truth again.
        store.apply([issue(key: "APP-1")], fetchedAt: Date().addingTimeInterval(60))
        #expect(store.tickets.first?.statusName == "To Do")
    }

    @Test("A stale refresh that omits the just-moved ticket does not delete it")
    func staleRefreshKeepsMovedTicket() async throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)
        _ = await store.apply(startReview, to: ticket)

        store.apply([], fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(store.tickets.count == 1)

        store.apply([], fetchedAt: Date().addingTimeInterval(60))
        #expect(store.tickets.isEmpty)
    }

    @Test("A refused move changes nothing and reports the error")
    func failureLeavesTicketAlone() async throws {
        let store = try makeStore(jira: ScriptedJiraAPI(failure: .unauthorized))
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        let failure = await store.apply(startReview, to: ticket)

        #expect(failure == .unauthorized)
        #expect(ticket.statusName == "To Do")
        #expect(ticket.seenStatusName == nil)
    }
}
