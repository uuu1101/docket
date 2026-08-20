//  SortingTests.swift
//  DocketKitTests

import Foundation
import SwiftData
import Testing

@testable import DocketKit

@Suite("Status category overrides")
struct StatusOverrideTests {
    @Test("Ready for QA counts as in progress even though Jira files it under Done")
    func readyForQAIsInProgress() {
        #expect(StatusCategory.resolved(jiraKey: "done", statusName: "READY FOR QA") == .inProgress)
    }

    @Test("The override ignores case and stray spacing", arguments: [
        "ready for qa", "Ready For QA", "  READY FOR QA  ",
    ])
    func overrideNormalizesNames(name: String) {
        #expect(StatusCategory.resolved(jiraKey: "done", statusName: name) == .inProgress)
    }

    @Test("Other done statuses are left where Jira put them")
    func otherDoneStatusesUnchanged() {
        #expect(StatusCategory.resolved(jiraKey: "done", statusName: "Pre Released") == .done)
        #expect(StatusCategory.resolved(jiraKey: "done", statusName: "완료") == .done)
    }

    @Test("Statuses Jira already classifies keep their category")
    func nonDoneCategoriesUnchanged() {
        #expect(StatusCategory.resolved(jiraKey: "indeterminate", statusName: "진행 중") == .inProgress)
        #expect(StatusCategory.resolved(jiraKey: "new", statusName: "해야 할 일") == .todo)
    }
}

@MainActor
@Suite("Ticket ordering")
struct TicketOrderingTests {
    private func ticket(
        _ key: String,
        category: StatusCategory = .todo,
        priority: String? = "Medium",
        targetEnd: Date? = nil,
        updated: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Ticket {
        Ticket(
            key: key,
            summary: "…",
            statusName: "…",
            statusCategory: category,
            priorityName: priority,
            issueType: "Bug",
            updatedAt: updated,
            browseURLString: "https://example.atlassian.net/browse/\(key)",
            targetEndDate: targetEnd
        )
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(Double(offset) * 86_400)
    }

    private func order(_ tickets: [Ticket]) -> [String] {
        tickets.sorted(by: DashboardStore.isOrderedBefore).map(\.key)
    }

    @Test("The nearest target end comes first")
    func nearestDeadlineFirst() {
        let order = order([
            ticket("FAR", targetEnd: day(10)),
            ticket("SOON", targetEnd: day(1)),
            ticket("MID", targetEnd: day(5)),
        ])
        #expect(order == ["SOON", "MID", "FAR"])
    }

    @Test("An overdue ticket outranks one still in the future")
    func overdueFirst() {
        #expect(order([ticket("FUTURE", targetEnd: day(3)), ticket("LATE", targetEnd: day(-2))])
            == ["LATE", "FUTURE"])
    }

    @Test("With the same date, the higher priority wins")
    func priorityBreaksTies() {
        let order = order([
            ticket("LOW", priority: "Low", targetEnd: day(3)),
            ticket("HIGH", priority: "Highest", targetEnd: day(3)),
            ticket("MED", priority: "Medium", targetEnd: day(3)),
        ])
        #expect(order == ["HIGH", "MED", "LOW"])
    }

    @Test("A ticket with no target end cannot be imminent, so it sorts after dated ones")
    func undatedSortsLast() {
        #expect(order([ticket("NONE"), ticket("DATED", targetEnd: day(30))]) == ["DATED", "NONE"])
    }

    @Test("Undated tickets fall back to priority, then to most recently updated")
    func undatedFallback() {
        let order = order([
            ticket("OLD", priority: "Medium", updated: day(-5)),
            ticket("NEW", priority: "Medium", updated: day(-1)),
            ticket("URGENT", priority: "Highest", updated: day(-9)),
        ])
        #expect(order == ["URGENT", "NEW", "OLD"])
    }

    @Test("Finished work sinks, however close its date")
    func doneSinks() {
        let order = order([
            ticket("DONE", category: .done, priority: "Highest", targetEnd: day(-5)),
            ticket("OPEN", category: .todo, priority: "Low", targetEnd: day(20)),
        ])
        #expect(order == ["OPEN", "DONE"])
    }

    @Test("Done tickets keep the same ordering among themselves")
    func doneOrderedInternally() {
        let order = order([
            ticket("LATER", category: .done, targetEnd: day(9)),
            ticket("SOONER", category: .done, targetEnd: day(2)),
        ])
        #expect(order == ["SOONER", "LATER"])
    }
}

@Suite("Reading a Jira date field")
struct JiraDateFieldTests {
    @Test("A date-only custom field parses")
    func dayFormat() {
        #expect(JiraDateParser.day(from: "2026-08-25") != nil)
    }

    @Test("Nonsense yields nil rather than a wrong date")
    func garbage() {
        #expect(JiraDateParser.day(from: "next tuesday") == nil)
    }

    @Test("The fallback field is the built-in due date")
    func fallbackField() {
        #expect(SyncEngine.targetEndFallbackFieldID == "duedate")
        #expect(SyncEngine.targetEndFieldName == "Target end")
    }
}
