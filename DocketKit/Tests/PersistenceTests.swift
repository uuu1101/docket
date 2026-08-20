//  PersistenceTests.swift
//  DocketKitTests

import Foundation
import SwiftData
import Testing

@testable import DocketKit

@MainActor
@Suite("SwiftData persistence")
struct PersistenceTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Ticket.self, SlackThread.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeTicket(key: String = "APP-29532") -> Ticket {
        Ticket(
            key: key,
            summary: "Recover an unsaved draft after reconnect",
            statusName: "In Progress",
            statusCategory: .inProgress,
            priorityName: "P2",
            issueType: "Bug",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            browseURLString: "https://team.atlassian.net/browse/APP-29532"
        )
    }

    @Test("A ticket survives insert, save and fetch")
    func insertTicket() throws {
        let context = try makeContext()
        context.insert(makeTicket())
        try context.save()

        let stored = try context.fetch(FetchDescriptor<Ticket>())
        #expect(stored.count == 1)
        #expect(stored.first?.statusCategory == .inProgress)
    }

    @Test("A thread attaches to its ticket and comes back through the relationship")
    func insertThread() throws {
        let context = try makeContext()
        let ticket = makeTicket()
        context.insert(ticket)

        let thread = SlackThread(
            id: "APP-29532|C1:1712345678.100100",
            channelID: "C1",
            channelName: "ios-dev",
            threadTS: "1712345678.100100",
            permalinkString: "https://team.slack.com/archives/C1/p1712345678100100",
            rootAuthorName: "jihoon",
            rootText: "Can anyone reproduce APP-29532?",
            replyCount: 4,
            participantNames: ["jihoon", "theo"],
            lastActivityAt: Date(timeIntervalSince1970: 1_700_000_500),
            lastReplyAuthorName: "theo"
        )
        context.insert(thread)
        thread.ticket = ticket
        try context.save()

        let stored = try context.fetch(FetchDescriptor<Ticket>())
        #expect(stored.first?.threads.count == 1)
        #expect(stored.first?.visibleThreads.count == 1)
    }

    @Test("Deleting a ticket takes its threads with it")
    func cascadeDelete() throws {
        let context = try makeContext()
        let ticket = makeTicket()
        context.insert(ticket)
        let thread = SlackThread(
            id: "APP-29532|C1:1.1",
            channelID: "C1",
            channelName: "ios-dev",
            threadTS: "1.1",
            permalinkString: "https://team.slack.com/archives/C1/p11",
            rootAuthorName: "jihoon",
            rootText: "…",
            replyCount: 0,
            participantNames: [],
            lastActivityAt: Date(),
            lastReplyAuthorName: nil
        )
        context.insert(thread)
        thread.ticket = ticket
        try context.save()

        context.delete(ticket)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<SlackThread>()).isEmpty)
    }
}

@MainActor
@Suite("SwiftData persistence on disk")
struct DiskPersistenceTests {
    /// The app's real configuration: a file-backed store reached through `mainContext`.
    private func makeDiskContainer() throws -> ModelContainer {
        let schema = Schema([Ticket.self, SlackThread.self])
        let url = URL.temporaryDirectory.appending(path: "docket-\(UUID().uuidString).store")
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    private func makeTicket(key: String) -> Ticket {
        Ticket(
            key: key,
            summary: "Recover an unsaved draft after reconnect",
            statusName: "In Progress",
            statusCategory: .inProgress,
            priorityName: "P2",
            issueType: "Bug",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            browseURLString: "https://team.atlassian.net/browse/\(key)"
        )
    }

    @Test("Inserting into a file-backed mainContext works")
    func insertIntoDiskStore() throws {
        let container = try makeDiskContainer()
        let context = container.mainContext
        context.insert(makeTicket(key: "APP-1"))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Ticket>()).count == 1)
    }

    @Test("Inserting several tickets in one pass works")
    func insertManyIntoDiskStore() throws {
        let container = try makeDiskContainer()
        let context = container.mainContext
        for index in 1 ... 6 {
            context.insert(makeTicket(key: "APP-\(index)"))
        }
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Ticket>()).count == 6)
    }
}

@MainActor
@Suite("Dashboard store persistence")
struct DashboardStoreTests {
    /// Hands the container straight into the store and keeps no reference of its own.
    /// If the store ever goes back to holding only a `ModelContext`, the container dies
    /// here and the first write traps inside SwiftData.
    private func makeStore() throws -> DashboardStore {
        let schema = Schema([Ticket.self, SlackThread.self])
        let url = URL.temporaryDirectory.appending(path: "docket-\(UUID().uuidString).store")
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "dev.taetae.docket.tests.\(UUID().uuidString)")!,
            keychain: KeychainStore(service: "dev.taetae.docket.tests")
        )
        return DashboardStore(
            settings: settings,
            container: try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
        )
    }

    private func issue(
        key: String,
        summary: String = "Recover an unsaved draft after reconnect",
        statusName: String = "해야 할 일",
        category: StatusCategory = .todo,
        priority: String? = "Medium",
        updated: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> JiraIssue {
        JiraIssue(
            key: key,
            summary: summary,
            statusName: statusName,
            statusCategory: category,
            priorityName: priority,
            issueType: "버그",
            updatedAt: updated,
            browseURL: URL(string: "https://example.atlassian.net/browse/\(key)")!
        )
    }

    @Test("Applying issues persists them")
    func applyInsertsTickets() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-27098"), issue(key: "APP-29532")])

        #expect(store.tickets.count == 2)
        #expect(store.tickets.map(\.key).sorted() == ["APP-27098", "APP-29532"])
    }

    @Test("Applying again updates a ticket in place instead of duplicating it")
    func applyUpdatesInPlace() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-27098", statusName: "해야 할 일", category: .todo)])
        store.apply([issue(key: "APP-27098", statusName: "진행 중", category: .inProgress)])

        #expect(store.tickets.count == 1)
        #expect(store.tickets.first?.statusName == "진행 중")
        #expect(store.tickets.first?.statusCategory == .inProgress)
    }

    @Test("A ticket the query stops returning is dropped")
    func applyRemovesOrphans() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-27098"), issue(key: "APP-29532")])
        store.apply([issue(key: "APP-27098")])

        #expect(store.tickets.map(\.key) == ["APP-27098"])
    }

    @Test("The stored list comes back in dashboard order")
    func applySortsTickets() throws {
        let store = try makeStore()
        store.apply([
            issue(key: "APP-1", category: .todo, priority: "Low"),
            issue(key: "APP-2", category: .inProgress, priority: "Highest"),
            issue(key: "APP-3", category: .done, priority: "Highest"),
        ])

        // Neither open ticket has a target end, so priority decides; the finished one sinks.
        #expect(store.tickets.map(\.key) == ["APP-2", "APP-1", "APP-3"])
    }
}

@MainActor
@Suite("Attached threads")
struct AttachedThreadTests {
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

    private func issue(key: String) -> JiraIssue {
        JiraIssue(
            key: key,
            summary: "Recover an unsaved draft after reconnect",
            statusName: "In Progress",
            statusCategory: .inProgress,
            priorityName: "P2",
            issueType: "Bug",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            browseURL: URL(string: "https://example.atlassian.net/browse/\(key)")!
        )
    }

    private func snapshot(id: String, replies: Int = 2) -> ThreadSnapshot {
        ThreadSnapshot(
            id: id,
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

    @Test("An attached thread is stored against its ticket")
    func attachThread() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        store.upsert(snapshot(id: "APP-1|C1:1.000001"), into: ticket)
        #expect(ticket.threads.count == 1)
        #expect(ticket.threads.first?.isManual == true)
    }

    @Test("Refreshing updates the reply count without adding a second row")
    func refreshUpdatesInPlace() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        store.upsert(snapshot(id: "APP-1|C1:1.000001", replies: 2), into: ticket)
        store.upsert(snapshot(id: "APP-1|C1:1.000001", replies: 7), into: ticket)

        #expect(ticket.threads.count == 1)
        #expect(ticket.threads.first?.replyCount == 7)
    }

    @Test("A refresh leaves the user's read position alone")
    func refreshKeepsSeenCount() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        store.upsert(snapshot(id: "APP-1|C1:1.000001", replies: 2), into: ticket)
        let thread = try #require(ticket.threads.first)
        store.markSeen(thread)

        store.upsert(snapshot(id: "APP-1|C1:1.000001", replies: 5), into: ticket)
        #expect(thread.seenReplyCount == 2)
        #expect(thread.unreadReplyCount == 3)
    }

    @Test("Removing a thread deletes it outright")
    func removeThread() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        store.upsert(snapshot(id: "APP-1|C1:1.000001"), into: ticket)
        let thread = try #require(ticket.threads.first)

        store.removeThread(thread)
        #expect(ticket.threads.isEmpty)
    }

    @Test("A ticket that leaves the query takes its threads with it")
    func cascadeOnTicketRemoval() throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)
        store.upsert(snapshot(id: "APP-1|C1:1.000001"), into: ticket)

        store.apply([])
        #expect(store.tickets.isEmpty)
    }

    @Test("A link pasted without Slack still attaches, knowing only the link")
    func pasteWithoutSlackAttachesLinkOnly() async throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        let failure = await store.addThread(
            link: "https://example.slack.com/archives/C1/p1712345678100100",
            to: ticket
        )

        #expect(failure == nil)
        let thread = try #require(ticket.threads.first)
        #expect(thread.isLinkOnly)
        #expect(thread.isManual)
        #expect(thread.id == "APP-1|C1:1712345678.100100")
        #expect(thread.channelName == thread.channelID)
        #expect(thread.unreadReplyCount == 0)
        // The permalink's own timestamp, so the card sorts where the message happened.
        #expect(thread.lastActivityAt == Date(timeIntervalSince1970: 1_712_345_678.1001))
    }

    @Test("Pasting the same link again without Slack keeps one card")
    func pasteWithoutSlackDeduplicates() async throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        let link = "https://example.slack.com/archives/C1/p1712345678100100"
        _ = await store.addThread(link: link, to: ticket)
        _ = await store.addThread(link: link, to: ticket)

        #expect(ticket.threads.count == 1)
    }

    @Test("Connecting Slack later hydrates a link-only card through the refresh")
    func refreshHydratesLinkOnlyThread() async throws {
        let store = try makeStore()
        store.apply([issue(key: "APP-1")])
        let ticket = try #require(store.tickets.first)

        _ = await store.addThread(
            link: "https://example.slack.com/archives/C1/p1000001",
            to: ticket
        )
        store.upsert(snapshot(id: "APP-1|C1:1.000001", replies: 7), into: ticket)

        // Same id, so the fetched snapshot lands on the pasted card instead of beside it.
        #expect(ticket.threads.count == 1)
        let thread = try #require(ticket.threads.first)
        #expect(thread.isLinkOnly == false)
        #expect(thread.channelName == "ios-dev")
        #expect(thread.replyCount == 7)
    }
}
