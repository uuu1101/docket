//  ModelTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("Status category mapping")
struct StatusCategoryTests {
    @Test("Jira category keys map onto the three buckets", arguments: [
        ("new", StatusCategory.todo),
        ("indeterminate", StatusCategory.inProgress),
        ("done", StatusCategory.done),
        ("something-unexpected", StatusCategory.todo),
    ])
    func mapping(key: String, expected: StatusCategory) {
        #expect(StatusCategory(jiraKey: key) == expected)
    }

    @Test("In-progress work sorts above the backlog")
    func ordering() {
        #expect(StatusCategory.inProgress.sortWeight < StatusCategory.todo.sortWeight)
        #expect(StatusCategory.todo.sortWeight < StatusCategory.done.sortWeight)
    }
}

@Suite("Priority ranking")
struct PriorityRankTests {
    @Test("Both naming schemes rank consistently", arguments: [
        ("Highest", 0), ("P1", 1), ("High", 1), ("P2", 2),
        ("Medium", 2), ("P3", 3), ("Low", 4), ("Lowest", 5),
    ])
    func ranks(name: String, expected: Int) {
        #expect(PriorityRank.value(for: name) == expected)
    }

    @Test("A missing priority sorts last")
    func missingPriority() {
        #expect(PriorityRank.value(for: nil) > PriorityRank.value(for: "Lowest"))
    }
}

@Suite("Jira date parsing")
struct JiraDateParserTests {
    @Test("Jira's offset format with milliseconds parses")
    func jiraFormat() {
        let date = JiraDateParser.date(from: "2026-08-18T10:22:33.123+0900")
        #expect(date != nil)
    }

    @Test("Plain ISO-8601 still parses")
    func isoFallback() {
        #expect(JiraDateParser.date(from: "2026-08-18T10:22:33Z") != nil)
    }

    @Test("Nonsense yields nil rather than a wrong date")
    func garbage() {
        #expect(JiraDateParser.date(from: "not a date") == nil)
    }
}

@Suite("Language resolution")
struct LanguageTests {
    @Test("Explicit choices win over the system locale")
    func explicitChoice() {
        #expect(AppLanguage.korean.resolved == .korean)
        #expect(AppLanguage.english.resolved == .english)
    }

    @Test("Both languages produce non-empty, distinct copy")
    func stringsDiffer() {
        let korean = Strings(language: .korean)
        let english = Strings(language: .english)
        #expect(korean.refresh.isEmpty == false)
        #expect(english.refresh.isEmpty == false)
        #expect(korean.refresh != english.refresh)
    }

    @Test("Counted strings agree on the number in both languages")
    func pluralization() {
        #expect(Strings(language: .english).replyCount(1) == "1 reply")
        #expect(Strings(language: .english).replyCount(4) == "4 replies")
        #expect(Strings(language: .korean).replyCount(4) == "답글 4")
    }
}

@Suite("Jira configuration parsing")
struct JiraConfigurationTests {
    @Test("A bare host gets an https scheme")
    func addsScheme() {
        let configuration = JiraConfiguration(siteURLString: "team.atlassian.net", email: "a@b.com", apiToken: "t")
        #expect(configuration?.siteURL.absoluteString == "https://team.atlassian.net")
    }

    @Test("A trailing slash is dropped so paths do not double up")
    func dropsTrailingSlash() {
        let configuration = JiraConfiguration(siteURLString: "https://team.atlassian.net/", email: "a@b.com", apiToken: "t")
        #expect(configuration?.siteURL.absoluteString == "https://team.atlassian.net")
    }

    @Test("Any missing field yields no configuration", arguments: [
        ("", "a@b.com", "t"),
        ("team.atlassian.net", "", "t"),
        ("team.atlassian.net", "a@b.com", ""),
    ])
    func incomplete(site: String, email: String, token: String) {
        #expect(JiraConfiguration(siteURLString: site, email: email, apiToken: token) == nil)
    }
}
