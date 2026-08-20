//  AttentionTests.swift
//  DocketKitTests

import Foundation
import SwiftData
import Testing

@testable import DocketKit

@MainActor
@Suite("What counts as needing attention")
struct AttentionTests {
    private func makeStore() throws -> DashboardStore {
        let schema = Schema([Ticket.self, SlackThread.self])
        let url = URL.temporaryDirectory.appending(path: "docket-\(UUID().uuidString).store")
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "dev.taetae.docket.tests.\(UUID().uuidString)")!,
            keychain: KeychainStore(service: "dev.taetae.docket.tests.\(UUID().uuidString)")
        )
        return DashboardStore(
            settings: settings,
            container: try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
        )
    }

    private func issue(key: String, status: String = "진행 중") -> JiraIssue {
        JiraIssue(
            key: key,
            summary: "…",
            statusName: status,
            statusCategory: .inProgress,
            priorityName: "Medium",
            issueType: "Bug",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            browseURL: URL(string: "https://example.atlassian.net/browse/\(key)")!
        )
    }

    private func snapshot(replies: Int) -> ThreadSnapshot {
        ThreadSnapshot(
            id: "APP-1|C1:1.000001",
            channelID: "C1",
            channelName: "ios-dev",
            threadTS: "1.000001",
            permalinkString: "https://example.slack.com/archives/C1/p1000001",
            rootAuthorName: "jihoon",
            rootText: "…",
            replyCount: replies,
            participantNames: ["jihoon"],
            lastActivityAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastReplyAuthorName: "theo",
            origin: .manual
        )
    }

    @Test("A ticket the user has never opened is marked")
    func newTicketIsMarked() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        #expect(ticket.isUnseen)
        #expect(ticket.needsAttention)
        #expect(store.ticketsNeedingAttention == 1)
    }

    @Test("Opening it clears the mark")
    func openingClearsTheMark() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        store.markSeen(ticket)
        #expect(ticket.needsAttention == false)
        #expect(store.ticketsNeedingAttention == 0)
    }

    @Test("A status change since the user last looked marks it again")
    func statusChangeMarksItAgain() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1", status: "진행 중")])
        let ticket = try #require(store.tickets.first)
        store.markSeen(ticket)

        store.apply([issue(key: "APP-1", status: "검토 중")])
        #expect(ticket.hasUnseenStatusChange)
        #expect(ticket.needsAttention)
    }

    @Test("A refresh that changes nothing leaves it clear")
    func unchangedRefreshStaysClear() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)
        store.markSeen(ticket)

        store.apply([issue(key: "APP-1")])
        #expect(ticket.needsAttention == false)
    }

    @Test("An unread reply marks the ticket even after it was opened")
    func unreadReplyMarksTicket() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)
        store.markSeen(ticket)

        store.upsert(snapshot(replies: 3), into: ticket)
        #expect(ticket.unreadReplyCount == 3)
        #expect(ticket.needsAttention)
    }

    @Test("Reading the thread clears it, without reopening the ticket")
    func readingThreadClearsIt() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)
        store.markSeen(ticket)
        store.upsert(snapshot(replies: 3), into: ticket)

        store.markSeen(try #require(ticket.threads.first))
        #expect(ticket.needsAttention == false)
    }

    @Test("The count covers every ticket, not just the first")
    func countsEveryTicket() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1"), issue(key: "APP-2"), issue(key: "APP-3")])
        #expect(store.ticketsNeedingAttention == 3)

        store.markSeen(try #require(store.ticket(withKey: "APP-2")))
        #expect(store.ticketsNeedingAttention == 2)
    }
}
