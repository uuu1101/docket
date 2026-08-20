//  SyncEngine.swift
//  DocketKit

import Foundation

/// A thread as it comes off the network, before it touches SwiftData.
public struct ThreadSnapshot: Sendable, Equatable {
    /// Scoped to the ticket: one Slack thread can legitimately be attached to several.
    public let id: String
    public let channelID: String
    public let channelName: String
    public let threadTS: String
    public let permalinkString: String
    public let rootAuthorName: String
    public let rootText: String
    public let replyCount: Int
    public let participantNames: [String]
    public let lastActivityAt: Date
    public let lastReplyAuthorName: String?
    public let origin: ThreadOrigin
}

/// Talks to Jira and Slack. Owns no state that outlives a refresh.
public struct SyncEngine: Sendable {
    private let jira: JiraAPI
    private let slack: SlackAPI?

    public init(jira: JiraAPI, slack: SlackAPI?) {
        self.jira = jira
        self.slack = slack
    }

    /// The field the dashboard sorts by. Advanced Roadmaps generates its id per site, so
    /// it is looked up by name, with the built-in due date as the fallback.
    public static let targetEndFieldName = "Target end"
    public static let targetEndFallbackFieldID = "duedate"

    public func issues(jql: String, targetEndFieldID: String?) async throws(JiraError) -> [JiraIssue] {
        try await jira.issues(jql: jql, maxResults: 100, extraFieldID: targetEndFieldID)
    }

    public func resolveTargetEndFieldID() async -> String {
        let found = try? await jira.fieldID(named: Self.targetEndFieldName)
        return found ?? Self.targetEndFallbackFieldID
    }

    /// Scoped to the ticket: one Slack thread can legitimately be attached to several.
    static func snapshotID(issueKey: String, channelID: String, threadTS: String) -> String {
        "\(issueKey)|\(channelID):\(threadTS)"
    }

    /// Fetches one specific thread, for a link the user attached by hand or for refreshing
    /// one that is already attached. Returns `nil` when the thread no longer exists.
    public func thread(
        issueKey: String,
        channelID: String,
        threadTS: String,
        permalink: URL,
        knownChannelName: String?,
        origin: ThreadOrigin
    ) async throws(SlackError) -> ThreadSnapshot? {
        guard let slack else { throw .notConfigured }
        guard let detail = try await slack.threadDetail(channelID: channelID, threadTS: threadTS) else {
            return nil
        }

        var userIDs = ([detail.rootUserID] + detail.participantIDs.map { Optional($0) }).compactMap { $0 }
        // A stored name equal to the channel id is the unresolved fallback, not a name.
        // Treating it as known would freeze the raw id on the card forever.
        var channelName = knownChannelName?.nilIfEmpty.flatMap { $0 == channelID ? nil : $0 }
        var directMessagePartnerID: String?

        if channelName == nil {
            let info = await slack.channelInfo(id: channelID)
            channelName = info?.name
            // A DM has no name of its own, so it is labelled with the person on the other side.
            if channelName == nil, let partner = info?.userID {
                directMessagePartnerID = partner
                userIDs.append(partner)
            }
        }

        let names = await slack.displayNames(for: userIDs)
        let resolvedChannelName = channelName
            ?? directMessagePartnerID.flatMap { names[$0] }
            ?? channelID

        return ThreadSnapshot(
            id: Self.snapshotID(issueKey: issueKey, channelID: channelID, threadTS: threadTS),
            channelID: channelID,
            channelName: resolvedChannelName,
            threadTS: threadTS,
            permalinkString: permalink.absoluteString,
            rootAuthorName: detail.rootUserID.flatMap { names[$0] } ?? "",
            rootText: detail.rootText,
            replyCount: detail.replyCount,
            participantNames: detail.participantIDs.compactMap { names[$0] },
            lastActivityAt: detail.lastActivityAt,
            lastReplyAuthorName: detail.lastReplyUserID.flatMap { names[$0] },
            origin: origin
        )
    }
}
