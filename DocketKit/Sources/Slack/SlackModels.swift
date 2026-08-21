//  SlackModels.swift
//  DocketKit

import Foundation

public struct SlackIdentity: Sendable, Equatable {
    public let userID: String
    public let userName: String
    public let teamName: String
    /// `T…`. Required by every `slack://` deep link, so a permalink cannot be handed to the
    /// desktop app without it.
    public let teamID: String

    public init(userID: String, userName: String, teamName: String, teamID: String = "") {
        self.userID = userID
        self.userName = userName
        self.teamName = teamName
        self.teamID = teamID
    }
}

public struct SlackChannelInfo: Sendable, Equatable {
    public let id: String
    /// Absent for direct messages, which have no name of their own.
    public let name: String?
    public let isDirectMessage: Bool
    public let userID: String?

    public init(id: String, name: String?, isDirectMessage: Bool, userID: String?) {
        self.id = id
        self.name = name
        self.isDirectMessage = isDirectMessage
        self.userID = userID
    }
}

/// The root message of a thread plus its activity counters.
public struct SlackThreadDetail: Sendable, Equatable {
    public let rootText: String
    public let rootUserID: String?
    public let replyCount: Int
    public let participantIDs: [String]
    public let lastActivityAt: Date
    public let lastReplyUserID: String?

    public init(
        rootText: String,
        rootUserID: String?,
        replyCount: Int,
        participantIDs: [String],
        lastActivityAt: Date,
        lastReplyUserID: String?
    ) {
        self.rootText = rootText
        self.rootUserID = rootUserID
        self.replyCount = replyCount
        self.participantIDs = participantIDs
        self.lastActivityAt = lastActivityAt
        self.lastReplyUserID = lastReplyUserID
    }
}

// MARK: - Wire format

/// Slack replies with a flat object, so `ok`/`error` are read from the same body as the
/// payload rather than wrapping it.
struct SlackStatus: Decodable {
    let ok: Bool
    let error: String?
    let needed: String?
}

struct SlackRepliesPayload: Decodable {
    let messages: [Message]?

    struct Message: Decodable {
        let ts: String
        let text: String?
        let user: String?
        let replyCount: Int?
        let replyUsers: [String]?
        let latestReply: String?

        enum CodingKeys: String, CodingKey {
            case ts, text, user
            case replyCount = "reply_count"
            case replyUsers = "reply_users"
            case latestReply = "latest_reply"
        }
    }
}

struct SlackChannelPayload: Decodable {
    let channel: Channel?

    struct Channel: Decodable {
        let id: String
        let name: String?
        let isIm: Bool?
        let isMpim: Bool?
        let user: String?

        enum CodingKeys: String, CodingKey {
            case id, name, user
            case isIm = "is_im"
            case isMpim = "is_mpim"
        }

        var asEntity: SlackChannelInfo {
            SlackChannelInfo(
                id: id,
                name: name?.nilIfEmpty,
                isDirectMessage: isIm == true || isMpim == true,
                userID: user
            )
        }
    }
}

struct SlackAuthPayload: Decodable {
    let userId: String?
    let user: String?
    let team: String?
    let teamId: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case teamId = "team_id"
        case user, team
    }
}

struct SlackUserPayload: Decodable {
    let user: User?

    struct User: Decodable {
        let id: String
        let realName: String?
        let profile: Profile?

        struct Profile: Decodable {
            let displayName: String?
            let realName: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case realName = "real_name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id
            case realName = "real_name"
            case profile
        }

        var bestName: String {
            let candidates = [profile?.displayName, profile?.realName, realName]
            return candidates.compactMap { $0 }.first { $0.isEmpty.not } ?? id
        }
    }
}

enum SlackTimestamp {
    static func date(from ts: String) -> Date? {
        guard let seconds = Double(ts) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
