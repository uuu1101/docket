//  JiraModels.swift
//  DocketKit

import Foundation

/// One issue, flattened out of Jira's nested `fields` payload.
public struct JiraIssue: Sendable, Equatable, Identifiable {
    public var id: String { key }
    public let key: String
    /// Jira's numeric id. The development panel is addressed by id, not by key.
    public let numericID: String
    public let summary: String
    public let statusName: String
    public let statusCategory: StatusCategory
    public let priorityName: String?
    public let issueType: String
    public let updatedAt: Date
    public let browseURL: URL
    /// Every URL the description carries, in the order they appear.
    public let descriptionURLs: [URL]
    /// The description itself, kept as JSON so a change to the renderer needs no refetch.
    public let description: JSONValue?
    /// Advanced Roadmaps' "Target end", or the plain due date when that field is absent.
    public let targetEndDate: Date?

    public var descriptionLinks: DescriptionLinks { DescriptionLinks(urls: descriptionURLs) }

    public init(
        key: String,
        numericID: String = "",
        summary: String,
        statusName: String,
        statusCategory: StatusCategory,
        priorityName: String?,
        issueType: String,
        updatedAt: Date,
        browseURL: URL,
        descriptionURLs: [URL] = [],
        description: JSONValue? = nil,
        targetEndDate: Date? = nil
    ) {
        self.key = key
        self.numericID = numericID
        self.summary = summary
        self.statusName = statusName
        self.statusCategory = statusCategory
        self.priorityName = priorityName
        self.issueType = issueType
        self.updatedAt = updatedAt
        self.browseURL = browseURL
        self.descriptionURLs = descriptionURLs
        self.description = description
        self.targetEndDate = targetEndDate
    }
}

public struct JiraAccount: Sendable, Equatable {
    public let accountID: String
    public let displayName: String

    public init(accountID: String, displayName: String) {
        self.accountID = accountID
        self.displayName = displayName
    }
}

// MARK: - Wire format

struct JiraSearchResponse: Decodable {
    let issues: [JiraIssueRemoteModel]
}

struct JiraIssueRemoteModel: Decodable {
    let key: String
    let id: String
    let fields: Fields
    /// The same object again, untyped, so a custom field can be read by its generated id.
    let rawFields: [String: JSONValue]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        fields = try container.decode(Fields.self, forKey: .fields)
        rawFields = try container.decode([String: JSONValue].self, forKey: .fields)
    }

    enum CodingKeys: String, CodingKey {
        case key, id, fields
    }

    struct Fields: Decodable {
        let summary: String
        let status: Status
        let priority: Named?
        let issuetype: Named?
        let updated: String
        /// Atlassian Document Format, walked untyped for the links inside it.
        let description: JSONValue?
    }

    struct Status: Decodable {
        let name: String
        let statusCategory: Category

        struct Category: Decodable {
            let key: String
        }
    }

    struct Named: Decodable {
        let name: String
    }
}

/// One comment on an issue.
public struct JiraComment: Sendable, Equatable, Identifiable {
    public let id: String
    public let authorName: String
    public let createdAt: Date
    /// The comment body, in the same format as the description.
    public let body: JSONValue?
    /// Written by a rule rather than a person, and so not part of the conversation.
    public let isAutomated: Bool

    public init(id: String, authorName: String, createdAt: Date, body: JSONValue?, isAutomated: Bool = false) {
        self.id = id
        self.authorName = authorName
        self.createdAt = createdAt
        self.body = body
        self.isAutomated = isAutomated
    }

    public var blocks: [ADFBlock] { ADFDocument.blocks(from: body) }
}

/// A page of comments, plus how many exist in total.
public struct JiraComments: Sendable, Equatable {
    /// Oldest first: a conversation reads forwards, even when only its tail was fetched.
    public let comments: [JiraComment]
    /// Every comment on the issue, automation included — what Jira shows if the reader follows
    /// the link, which is why it can exceed what is listed here.
    public let total: Int

    public init(comments: [JiraComment], total: Int) {
        self.comments = comments
        self.total = total
    }

    public var hasMore: Bool { total > comments.count }

    /// Keeps the newest `limit` comments a person wrote, oldest first.
    ///
    /// Automation dominates some tickets — one issue answered with thirteen sprint-field
    /// reminders and nothing else — so a window taken before filtering can hold no
    /// conversation at all.
    public static func page(from newestFirst: [JiraComment], total: Int, limit: Int) -> JiraComments {
        let readable = newestFirst.lazy.filter { $0.isAutomated == false }.prefix(limit)
        return JiraComments(comments: readable.reversed(), total: total)
    }
}

/// Authors whose comments are automation.
enum JiraAutomationAuthor {
    /// Marketplace actors (`Automation for Jira` and its siblings) report this account type.
    static let appAccountType = "app"

    /// A site can also drive its rules from an ordinary account that reports
    /// `accountType: "atlassian"`, indistinguishable from a colleague by type alone. Such
    /// bots can be listed here by account id — the id rather than the display name, so a
    /// person whose name merely resembles a bot's is never mistaken for one.
    static let accountIDs: Set<String> = []

    static func isAutomated(
        accountID: String?,
        accountType: String?,
        listedIDs: Set<String> = accountIDs
    ) -> Bool {
        if accountType == appAccountType { return true }
        guard let accountID else { return false }
        return listedIDs.contains(accountID)
    }
}

struct JiraCommentsResponse: Decodable {
    let comments: [Comment]?
    let total: Int?

    struct Comment: Decodable {
        let id: String?
        let author: Author?
        let created: String?
        let body: JSONValue?

        struct Author: Decodable {
            let accountId: String?
            let accountType: String?
            let displayName: String?
        }

        var asEntity: JiraComment? { asEntity(listedBotIDs: JiraAutomationAuthor.accountIDs) }

        func asEntity(listedBotIDs: Set<String>) -> JiraComment? {
            guard let id else { return nil }
            return JiraComment(
                id: id,
                authorName: author?.displayName ?? "",
                createdAt: created.flatMap(JiraDateParser.date(from:)) ?? .distantPast,
                body: body,
                isAutomated: JiraAutomationAuthor.isAutomated(
                    accountID: author?.accountId,
                    accountType: author?.accountType,
                    listedIDs: listedBotIDs
                )
            )
        }
    }
}

/// A move the workflow allows from the issue's current status.
public struct JiraTransition: Sendable, Equatable, Identifiable {
    public let id: String
    /// The workflow's own name for the move, such as "Start Review".
    public let name: String
    /// Where the issue lands. This is what the user is shown: "검토 중" says more than
    /// "Start Review".
    public let toStatusName: String
    public let toStatusCategory: StatusCategory
    /// Fields the transition screen demands. A move needing these cannot be completed from
    /// here and fails with an explanation.
    public let requiredFields: [String]

    public init(
        id: String,
        name: String,
        toStatusName: String,
        toStatusCategory: StatusCategory,
        requiredFields: [String] = []
    ) {
        self.id = id
        self.name = name
        self.toStatusName = toStatusName
        self.toStatusCategory = toStatusCategory
        self.requiredFields = requiredFields
    }
}

struct JiraTransitionsResponse: Decodable {
    let transitions: [Transition]?

    struct Transition: Decodable {
        let id: String?
        let name: String?
        let to: To?
        let fields: [String: Field]?

        struct To: Decodable {
            let name: String?
            let statusCategory: JiraIssueRemoteModel.Status.Category?
        }

        struct Field: Decodable {
            let required: Bool?
            /// The human-readable label ("Resolution"), because the map is keyed by raw
            /// field ids ("customfield_10104") that mean nothing in a refusal message.
            let name: String?
        }

        var asEntity: JiraTransition? {
            guard let id, let name, let statusName = to?.name else { return nil }
            return JiraTransition(
                id: id,
                name: name,
                toStatusName: statusName,
                toStatusCategory: StatusCategory.resolved(
                    jiraKey: to?.statusCategory?.key ?? "",
                    statusName: statusName
                ),
                requiredFields: (fields ?? [:])
                    .filter { $0.value.required == true }
                    .map { $0.value.name ?? $0.key }
                    .sorted()
            )
        }
    }
}

struct JiraFieldRemoteModel: Decodable {
    let id: String
    let name: String?
}

struct JiraMyselfRemoteModel: Decodable {
    let accountId: String
    let displayName: String

    var asEntity: JiraAccount {
        JiraAccount(accountID: accountId, displayName: displayName)
    }
}

extension JiraIssueRemoteModel {
    func asEntity(siteURL: URL, targetEndFieldID: String?) -> JiraIssue {
        JiraIssue(
            key: key,
            numericID: id,
            summary: fields.summary,
            statusName: fields.status.name,
            statusCategory: StatusCategory.resolved(
                jiraKey: fields.status.statusCategory.key,
                statusName: fields.status.name
            ),
            priorityName: fields.priority?.name,
            issueType: fields.issuetype?.name ?? "Task",
            updatedAt: JiraDateParser.date(from: fields.updated) ?? .distantPast,
            browseURL: siteURL.appendingPathComponent("browse").appendingPathComponent(key),
            descriptionURLs: DescriptionLinks.urls(in: fields.description),
            description: fields.description,
            targetEndDate: date(forFieldID: targetEndFieldID)
        )
    }
}

extension JiraIssueRemoteModel {
    /// Date fields arrive as `yyyy-MM-dd`; a few arrive with a time attached.
    func date(forFieldID id: String?) -> Date? {
        guard let id, case let .string(text)? = rawFields[id] else { return nil }
        return JiraDateParser.day(from: text) ?? JiraDateParser.date(from: text)
    }
}

/// Jira stamps `updated` as ISO-8601 with milliseconds and a `+0900`-style offset,
/// which `ISO8601DateFormatter` rejects without help.
enum JiraDateParser {
    // Built per call: neither formatter type is Sendable, and a refresh parses only a
    // few dozen dates.
    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }

    private static var fallback: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func day(from string: String) -> Date? {
        dayFormatter.date(from: string)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? fallback.date(from: string)
    }
}
