//  Models.swift
//  DocketKit

import Foundation
import SwiftData

@Model
public final class Ticket {
    @Attribute(.unique) public var key: String
    public var summary: String
    public var statusName: String
    public var statusCategoryRaw: String
    public var priorityName: String?
    public var priorityRank: Int
    public var issueType: String
    public var updatedAt: Date
    public var browseURLString: String
    /// Advanced Roadmaps' "Target end", or the due date when that field is absent.
    public var targetEndDate: Date?
    /// Jira's numeric id, kept from when the development panel was the source of PRs.
    public var numericID: String = ""
    /// The status the user last had on screen. `nil` means they have never opened it, which
    /// is what makes a newly assigned ticket stand out.
    public var seenStatusName: String?
    /// Pull requests found on GitHub, encoded rather than modelled: a handful of links per
    /// ticket does not earn its own entity, and a new entity means a migration.
    public var pullRequestsData: Data?
    /// When Slack was last searched for this ticket. `nil` means never.
    public var slackSyncedAt: Date?
    /// Found in the Jira description. Replaced whenever the description changes.
    public var detectedFigmaURLString: String?
    /// Set by the user. Wins over the detected one; clearing it falls back to detection.
    public var chosenFigmaURLString: String?
    /// Slack links found in the Jira description, kept so a refresh can attach them.
    public var jiraThreadLinkStrings: [String] = []

    @Relationship(deleteRule: .cascade, inverse: \SlackThread.ticket)
    public var threads: [SlackThread] = []

    public init(
        key: String,
        summary: String,
        statusName: String,
        statusCategory: StatusCategory,
        priorityName: String?,
        issueType: String,
        updatedAt: Date,
        browseURLString: String,
        targetEndDate: Date? = nil
    ) {
        self.key = key
        self.summary = summary
        self.statusName = statusName
        statusCategoryRaw = statusCategory.rawValue
        self.priorityName = priorityName
        priorityRank = PriorityRank.value(for: priorityName)
        self.issueType = issueType
        self.updatedAt = updatedAt
        self.browseURLString = browseURLString
        self.targetEndDate = targetEndDate
    }

    public var statusCategory: StatusCategory {
        get { StatusCategory(rawValue: statusCategoryRaw) ?? .todo }
        set { statusCategoryRaw = newValue.rawValue }
    }

    public var browseURL: URL? { URL(string: browseURLString) }

    public var pullRequests: [PullRequestLink] {
        get {
            guard let pullRequestsData else { return [] }
            return (try? JSONDecoder().decode([PullRequestLink].self, from: pullRequestsData)) ?? []
        }
        set { pullRequestsData = try? JSONEncoder().encode(newValue) }
    }

    public var figmaURL: URL? {
        (chosenFigmaURLString ?? detectedFigmaURLString).flatMap { URL(string: $0) }
    }

    /// True when the link on screen came from the user rather than from Jira.
    public var hasChosenFigmaURL: Bool { chosenFigmaURLString?.isEmpty == false }

    public var pendingJiraThreadLinks: [SlackPermalink] {
        jiraThreadLinkStrings.compactMap { URL(string: $0) }.compactMap(SlackPermalink.init(url:))
    }

    public var visibleThreads: [SlackThread] {
        threads.filter { $0.isHidden.not }.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    public var unreadReplyCount: Int {
        visibleThreads.reduce(0) { $0 + $1.unreadReplyCount }
    }

    /// Never opened, so everything about it is new.
    public var isUnseen: Bool { seenStatusName == nil }

    /// Moved along the workflow since the user last looked.
    public var hasUnseenStatusChange: Bool {
        guard let seenStatusName else { return false }
        return seenStatusName != statusName
    }

    /// Worth a mark in the menu bar.
    public var needsAttention: Bool {
        isUnseen || hasUnseenStatusChange || unreadReplyCount > 0
    }
}

@Model
public final class SlackThread {
    /// `channelID:threadTS` — the same thread found by both queries collapses onto one row.
    @Attribute(.unique) public var id: String
    public var channelID: String
    public var channelName: String
    public var threadTS: String
    public var permalinkString: String
    public var rootAuthorName: String
    public var rootText: String
    public var replyCount: Int
    public var participantNames: [String]
    public var lastActivityAt: Date
    public var lastReplyAuthorName: String?
    /// Where the thread came from. Stored under the old column name to avoid a migration.
    public var matchKindRaw: String
    /// Set by the user; every sync preserves it.
    public var isHidden: Bool
    /// `replyCount` as of the last time the user expanded this thread.
    public var seenReplyCount: Int
    /// When Slack last answered for this thread. `nil` means the link was attached without
    /// a Slack connection, so only the link itself is known.
    public var lastFetchedAt: Date?

    public var ticket: Ticket?

    public init(
        id: String,
        channelID: String,
        channelName: String,
        threadTS: String,
        permalinkString: String,
        rootAuthorName: String,
        rootText: String,
        replyCount: Int,
        participantNames: [String],
        lastActivityAt: Date,
        lastReplyAuthorName: String?,
        origin: ThreadOrigin = .manual,
        isHidden: Bool = false,
        seenReplyCount: Int = 0,
        lastFetchedAt: Date? = nil
    ) {
        self.id = id
        self.channelID = channelID
        self.channelName = channelName
        self.threadTS = threadTS
        self.permalinkString = permalinkString
        self.rootAuthorName = rootAuthorName
        self.rootText = rootText
        self.replyCount = replyCount
        self.participantNames = participantNames
        self.lastActivityAt = lastActivityAt
        self.lastReplyAuthorName = lastReplyAuthorName
        matchKindRaw = origin.rawValue
        self.isHidden = isHidden
        self.seenReplyCount = seenReplyCount
        self.lastFetchedAt = lastFetchedAt
    }

    public var origin: ThreadOrigin {
        get { ThreadOrigin(rawValue: matchKindRaw) ?? .manual }
        set { matchKindRaw = newValue.rawValue }
    }

    public var isManual: Bool { origin == .manual }

    public var permalink: URL? { URL(string: permalinkString) }

    public var unreadReplyCount: Int { max(0, replyCount - seenReplyCount) }

    /// Only the link is stored; connecting Slack lets the next refresh fill the rest in.
    public var isLinkOnly: Bool { lastFetchedAt == nil }
}

public enum ThreadOrigin: String, Sendable, CaseIterable {
    /// Pasted in by the user. Removing it is final.
    case manual
    /// Found in the Jira description. Removing it only hides it, because the link is still
    /// in Jira and the next refresh would otherwise bring it straight back.
    case jira
}

/// Sorts tickets by urgency across the two naming schemes Jira projects use in practice.
public enum PriorityRank {
    public static func value(for name: String?) -> Int {
        guard let name = name?.lowercased() else { return 99 }
        return switch name {
        case let value where value.contains("highest") || value.contains("blocker") || value.contains("p0"): 0
        case let value where value.contains("p1"): 1
        case let value where value.contains("high"): 1
        case let value where value.contains("p2"): 2
        case let value where value.contains("medium") || value.contains("normal"): 2
        case let value where value.contains("p3"): 3
        case let value where value.contains("lowest"): 5
        case let value where value.contains("low"): 4
        default: 99
        }
    }
}
