//  SlackAPI.swift
//  DocketKit

import Foundation

public protocol SlackAPI: Sendable {
    func identity() async throws(SlackError) -> SlackIdentity
    func threadDetail(channelID: String, threadTS: String) async throws(SlackError) -> SlackThreadDetail?
    func displayNames(for userIDs: [String]) async -> [String: String]
    /// Never throws: a channel whose name cannot be read still yields a usable thread.
    func channelInfo(id: String) async -> SlackChannelInfo?
}

public actor LiveSlackAPI: SlackAPI {
    /// A one-off call carries its own token; the app's own calls go through the store so a
    /// rotating token can be renewed underneath them.
    public enum TokenSource: Sendable {
        case fixed(String)
        case store(SlackTokenStore)
    }

    private let tokenSource: TokenSource
    private let session: URLSession
    private let limiter: SlackRateLimiter
    /// Display names change rarely; one lookup per user per launch is plenty.
    private var nameCache: [String: String] = [:]

    public init(token: String, session: URLSession = .shared, limiter: SlackRateLimiter = SlackRateLimiter()) {
        tokenSource = .fixed(token)
        self.session = session
        self.limiter = limiter
    }

    public init(tokenStore: SlackTokenStore, session: URLSession = .shared, limiter: SlackRateLimiter = SlackRateLimiter()) {
        tokenSource = .store(tokenStore)
        self.session = session
        self.limiter = limiter
    }

    public func identity() async throws(SlackError) -> SlackIdentity {
        let data = try await call(method: "auth.test", tier: .lookup, parameters: [:])
        let payload = try decode(SlackAuthPayload.self, from: data)
        return SlackIdentity(
            userID: payload.userId ?? "",
            userName: payload.user ?? "",
            teamName: payload.team ?? ""
        )
    }

    public func threadDetail(channelID: String, threadTS: String) async throws(SlackError) -> SlackThreadDetail? {
        let data = try await call(
            method: "conversations.replies",
            tier: .history,
            parameters: [
                "channel": channelID,
                "ts": threadTS,
                "limit": "1",
            ]
        )
        let payload = try decode(SlackRepliesPayload.self, from: data)
        guard let root = payload.messages?.first else { return nil }

        let rootDate = SlackTimestamp.date(from: root.ts) ?? Date()
        let latestDate = root.latestReply.flatMap(SlackTimestamp.date(from:))
        let participants = ([root.user].compactMap { $0 } + (root.replyUsers ?? []))
            .reduced()

        return SlackThreadDetail(
            rootText: root.text ?? "",
            rootUserID: root.user,
            replyCount: root.replyCount ?? 0,
            participantIDs: participants,
            lastActivityAt: latestDate ?? rootDate,
            lastReplyUserID: root.replyUsers?.last
        )
    }

    public func channelInfo(id: String) async -> SlackChannelInfo? {
        do {
            let data = try await call(method: "conversations.info", tier: .lookup, parameters: ["channel": id])
            let info = try decode(SlackChannelPayload.self, from: data).channel?.asEntity
            // Names and counterpart users are workplace-sensitive; only the channel id is
            // worth having in a diagnostic log.
            Log.slack.info("conversations.info \(id, privacy: .public) -> name=\(info?.name ?? "nil", privacy: .private) isDM=\(info?.isDirectMessage == true) user=\(info?.userID ?? "nil", privacy: .private)")
            return info
        } catch {
            // Not fatal — the thread still works, it just shows its channel id. Worth
            // saying out loud, because a silent fallback looks like a naming bug.
            Log.slack.error("conversations.info failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Never throws: a missing name degrades to the raw user ID rather than failing a refresh.
    public func displayNames(for userIDs: [String]) async -> [String: String] {
        var result: [String: String] = [:]
        for id in userIDs.reduced() {
            if let cached = nameCache[id] {
                result[id] = cached
                continue
            }
            guard let data = try? await call(method: "users.info", tier: .lookup, parameters: ["user": id]),
                  let payload = try? decode(SlackUserPayload.self, from: data),
                  let user = payload.user
            else { continue }

            nameCache[id] = user.bestName
            result[id] = user.bestName
        }
        return result
    }

    // MARK: - Transport

    private func call(
        method: String,
        tier: SlackRateLimiter.Tier,
        parameters: [String: String]
    ) async throws(SlackError) -> Data {
        let token = try await currentToken()
        do {
            return try await perform(method: method, tier: tier, parameters: parameters, token: token)
        } catch {
            // Slack rejected a token we believed was good — renew once, then give up.
            guard Self.isRenewable(error), case let .store(store) = tokenSource else { throw error }
            let renewed = try await store.renew()
            return try await perform(method: method, tier: tier, parameters: parameters, token: renewed)
        }
    }

    private func currentToken() async throws(SlackError) -> String {
        switch tokenSource {
        case let .fixed(token): token
        case let .store(store): try await store.validToken()
        }
    }

    private static func isRenewable(_ error: SlackError) -> Bool {
        error == .tokenExpired || error == .invalidAuth
    }

    private func perform(
        method: String,
        tier: SlackRateLimiter.Tier,
        parameters: [String: String],
        token: String
    ) async throws(SlackError) -> Data {
        await limiter.acquire(tier)

        guard let url = URL(string: "https://slack.com/api/\(method)") else {
            throw .network("Invalid endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncoded(parameters).utf8)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw .network("Unexpected response")
        }

        if http.statusCode == 429 {
            let retryAfter = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30
            await limiter.backOff(seconds: retryAfter)
            throw .rateLimited(retryAfter: retryAfter)
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw .http(status: http.statusCode)
        }

        let status = try decode(SlackStatus.self, from: data)
        guard status.ok else { throw Self.error(for: status) }
        return data
    }

    private nonisolated func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(SlackError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .decoding(error.localizedDescription)
        }
    }

    private static func error(for status: SlackStatus) -> SlackError {
        switch status.error {
        case "token_expired":
            .tokenExpired
        case "not_authed", "invalid_auth", "token_revoked", "account_inactive":
            .invalidAuth
        case "missing_scope", "not_allowed_token_type":
            .missingScope(status.needed ?? "search:read")
        case "ratelimited":
            .rateLimited(retryAfter: 30)
        case let other:
            .api(other ?? "unknown")
        }
    }

    private static func formEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }

}

extension Array where Element: Hashable {
    /// Order-preserving de-duplication.
    func reduced() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
