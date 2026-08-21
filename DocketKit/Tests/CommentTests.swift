//  CommentTests.swift
//  DocketKit

import Foundation
import Testing

@testable import DocketKit

@Suite("Jira comments")
struct CommentTests {
    /// Mirrors `LiveJiraAPI.comments(issueKey:limit:)` from the response onwards, with the
    /// test's own bot on the site list so the mechanism is exercised without shipping an id.
    private func parse(_ json: String, limit: Int = 10) throws -> JiraComments {
        let response = try JSONDecoder().decode(JiraCommentsResponse.self, from: Data(json.utf8))
        let newestFirst = response.comments?.compactMap { $0.asEntity(listedBotIDs: [bot.id]) } ?? []
        return JiraComments.page(from: newestFirst, total: response.total ?? newestFirst.count, limit: limit)
    }

    /// Newest first, as Jira returns them for `orderBy=-created`.
    private func response(_ authors: [(name: String, id: String, type: String)], total: Int? = nil) -> String {
        let comments = authors.enumerated().map { index, author in
            """
            {
              "id": "\(index)",
              "author": {
                "accountId": "\(author.id)",
                "accountType": "\(author.type)",
                "displayName": "\(author.name)"
              },
              "created": "2026-08-\(String(format: "%02d", 28 - index))T09:00:00.000+0900"
            }
            """
        }
        return #"{ "total": \#(total ?? authors.count), "comments": [\#(comments.joined(separator: ","))] }"#
    }

    private let bot = (name: "Automation bot", id: "712020:00000000-0000-0000-0000-0000000000b0", type: "atlassian")
    private let app = (name: "Automation for Jira", id: "557058:f58131cb", type: "app")
    private let human = (name: "Ana", id: "712020:aaaa", type: "atlassian")

    @Test("A page reads oldest first, whatever order the server sent")
    func ordersChronologically() throws {
        let comments = try parse(#"""
        {
          "total": 2,
          "comments": [
            {
              "id": "2",
              "author": { "displayName": "Bo" },
              "created": "2026-08-18T15:04:00.000+0900",
              "body": { "type": "doc", "content": [
                { "type": "paragraph", "content": [{ "type": "text", "text": "Later" }] }
              ] }
            },
            {
              "id": "1",
              "author": { "displayName": "Ana" },
              "created": "2026-08-18T09:00:00.000+0900",
              "body": { "type": "doc", "content": [
                { "type": "paragraph", "content": [{ "type": "text", "text": "Earlier" }] }
              ] }
            }
          ]
        }
        """#)

        #expect(comments.comments.map(\.authorName) == ["Ana", "Bo"])
        #expect(comments.comments.first?.blocks == [.paragraph([ADFSpan(text: "Earlier")])])
        #expect(comments.comments.first?.createdAt ?? .distantFuture < comments.comments[1].createdAt)
        #expect(comments.hasMore == false)
    }

    @Test("A fetched tail knows the thread is longer than what it holds")
    func reportsMore() throws {
        let comments = try parse(#"""
        { "total": 34, "comments": [{ "id": "9", "author": { "displayName": "Ana" }, "created": "2026-08-18T09:00:00.000+0900" }] }
        """#)

        #expect(comments.total == 34)
        #expect(comments.hasMore)
    }

    @Test("An empty thread yields nothing to draw")
    func handlesEmpty() throws {
        let comments = try parse(#"{ "total": 0, "comments": [], "startAt": 0 }"#)

        #expect(comments.comments.isEmpty)
        #expect(comments.hasMore == false)
    }

    @Test("A comment with no author or body still renders")
    func toleratesMissingFields() throws {
        let comments = try parse(#"{ "comments": [{ "id": "5" }] }"#)

        #expect(comments.comments.count == 1)
        #expect(comments.comments.first?.authorName == "")
        #expect(comments.comments.first?.blocks.isEmpty == true)
        // Without `total`, the count of what arrived is the only honest answer.
        #expect(comments.total == 1)
    }

    @Test("The site's automation account is hidden even though its type says otherwise")
    func hidesSiteAutomation() throws {
        let comments = try parse(response([bot, bot, human]))

        #expect(comments.comments.map(\.authorName) == ["Ana"])
        // The header still reports what Jira holds, so the link to it is not a contradiction.
        #expect(comments.total == 3)
        #expect(comments.hasMore)
    }

    @Test("App accounts are hidden by type, without needing to be listed")
    func hidesAppAccounts() throws {
        let comments = try parse(response([app, human]))

        #expect(comments.comments.map(\.authorName) == ["Ana"])
    }

    @Test("A person whose name contains a bot's is still a person")
    func keepsPeopleNamedLikeBots() throws {
        let comments = try parse(response([(name: "Abbot Vance", id: "5cb84285000000000000000a", type: "atlassian")]))

        #expect(comments.comments.map(\.authorName) == ["Abbot Vance"])
    }

    @Test("The window reaches past a run of automation to find the conversation")
    func reachesPastAutomation() throws {
        let authors = Array(repeating: bot, count: 12) + [human, human]
        let comments = try parse(response(authors), limit: 10)

        #expect(comments.comments.count == 2)
        #expect(comments.comments.allSatisfy { $0.isAutomated == false })
    }

    @Test("Only the newest comments are kept when people wrote more than fit")
    func keepsNewest() throws {
        let authors = Array(repeating: human, count: 14)
        let comments = try parse(response(authors), limit: 10)

        #expect(comments.comments.count == 10)
        // Oldest first within the window, and the last one is the newest comment of all.
        #expect(comments.comments.first?.id == "9")
        #expect(comments.comments.last?.id == "0")
    }

    @Test("A thread of nothing but automation shows nothing rather than noise")
    func hidesAutomationOnlyThreads() throws {
        let comments = try parse(response(Array(repeating: bot, count: 13)))

        #expect(comments.comments.isEmpty)
        #expect(comments.total == 13)
    }

    @Test("A comment with no id is dropped rather than drawn without identity")
    func dropsIdentityless() throws {
        let comments = try parse(#"{ "total": 1, "comments": [{ "author": { "displayName": "Ana" } }] }"#)

        #expect(comments.comments.isEmpty)
    }
}

@MainActor
@Suite("Listing the site's own bots")
struct BotAccountIDTests {
    @Test("Ids split on commas, spaces and newlines, however they were pasted")
    func parsesPastedIDs() {
        #expect(AppSettings.parseAccountIDs("a, b\nc d,,  ") == ["a", "b", "c", "d"])
        #expect(AppSettings.parseAccountIDs("") == [])
        #expect(AppSettings.parseAccountIDs("  ,  ") == [])
    }

    @Test("The listed ids travel into the Jira configuration")
    func configurationCarriesIDs() {
        let configuration = JiraConfiguration(
            siteURLString: "https://example.atlassian.net",
            email: "a@example.com",
            apiToken: "t",
            botAccountIDs: ["712020:bot"]
        )
        #expect(configuration?.botAccountIDs == ["712020:bot"])
    }
}
