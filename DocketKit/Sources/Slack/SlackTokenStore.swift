//  SlackTokenStore.swift
//  DocketKit

import Foundation

/// Vends a Slack token that is valid right now.
///
/// A PKCE public client always gets a rotating token from Slack — roughly a 12 hour life —
/// so every call has to go through here rather than reading the stored token directly.
@MainActor
public final class SlackTokenStore {
    /// Renew this far ahead of expiry so a long refresh cannot race a request.
    static let renewalMargin: TimeInterval = 5 * 60

    private let settings: AppSettings
    /// Concurrent callers share one renewal; two refreshes would invalidate each other's
    /// refresh token.
    private var renewal: Task<String, any Error>?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func validToken() async throws(SlackError) -> String {
        let token = settings.slackUserToken
        guard token.isEmpty.not else { throw .notConfigured }

        // No expiry recorded means a non-rotating token, which never needs renewing.
        guard let expiresAt = settings.slackTokenExpiresAt else { return token }
        guard Date().addingTimeInterval(Self.renewalMargin) >= expiresAt else { return token }

        return try await renew()
    }

    public func renew() async throws(SlackError) -> String {
        if let renewal { return try await value(of: renewal) }

        let refreshToken = settings.slackRefreshToken
        guard refreshToken.isEmpty.not else {
            throw .refreshFailed(settings.strings.slackOAuthErrorMessage(.missingRefreshToken))
        }

        let oauth = SlackOAuth(clientID: settings.slackClientID, clientSecret: settings.slackClientSecret)
        let settings = settings
        let task = Task<String, any Error> {
            let credentials = try await oauth.refresh(refreshToken: refreshToken)
            settings.applySlackCredentials(credentials)
            return credentials.userToken
        }
        renewal = task
        defer { renewal = nil }

        return try await value(of: task)
    }

    private func value(of task: Task<String, any Error>) async throws(SlackError) -> String {
        do {
            return try await task.value
        } catch let error as SlackOAuthError {
            throw .refreshFailed(settings.strings.slackOAuthErrorMessage(error))
        } catch {
            throw .refreshFailed(error.localizedDescription)
        }
    }
}
