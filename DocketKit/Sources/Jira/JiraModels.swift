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
