//  AppSettings.swift
//  DocketKit

import Foundation
import Observation

/// User preferences. Secrets live in the keychain; everything here is plain configuration.
@MainActor
@Observable
public final class AppSettings {
    private enum Key {
        static let language = "settings.language"
        static let refreshMinutes = "settings.refreshMinutes"
        static let query = "settings.query"
        static let customJQL = "settings.customJQL"
        static let jiraSiteURL = "settings.jiraSiteURL"
        static let jiraEmail = "settings.jiraEmail"
        static let jiraBotAccountIDs = "settings.jiraBotAccountIDs"
        static let slackUserName = "settings.slackUserName"
        static let slackTeamName = "settings.slackTeamName"
        static let slackTeamID = "settings.slackTeamID"
        static let slackTokenExpiresAt = "settings.slackTokenExpiresAt"
        static let githubRepositories = "settings.githubRepositories"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    public var refreshMinutes: Int {
        didSet { defaults.set(refreshMinutes, forKey: Key.refreshMinutes) }
    }

    public var query: TicketQuery {
        didSet { defaults.set(query.rawValue, forKey: Key.query) }
    }

    /// Only consulted when `query` is `.custom`.
    public var customJQL: String {
        didSet { defaults.set(customJQL, forKey: Key.customJQL) }
    }

    public var jiraSiteURL: String {
        didSet { defaults.set(jiraSiteURL, forKey: Key.jiraSiteURL) }
    }

    public var jiraEmail: String {
        didSet { defaults.set(jiraEmail, forKey: Key.jiraEmail) }
    }

    /// Account ids of the site's automation bots, comma- or whitespace-separated, whose
    /// comments the dashboard hides. Bots reporting `accountType: "app"` are hidden
    /// without being listed.
    public var jiraBotAccountIDs: String {
        didSet { defaults.set(jiraBotAccountIDs, forKey: Key.jiraBotAccountIDs) }
    }

    public var jiraAPIToken: String {
        didSet { keychain.set(jiraAPIToken, for: .jiraAPIToken) }
    }

    public var slackUserToken: String {
        didSet { keychain.set(slackUserToken, for: .slackUserToken) }
    }

    /// Display-only, captured when the authorization completes.
    public private(set) var slackUserName: String {
        didSet { defaults.set(slackUserName, forKey: Key.slackUserName) }
    }

    public private(set) var slackTeamID: String {
        didSet { defaults.set(slackTeamID, forKey: Key.slackTeamID) }
    }

    public private(set) var slackTeamName: String {
        didSet { defaults.set(slackTeamName, forKey: Key.slackTeamName) }
    }

    public private(set) var slackRefreshToken: String {
        didSet { keychain.set(slackRefreshToken, for: .slackRefreshToken) }
    }

    /// `nil` for a non-rotating token, which never needs renewing.
    public private(set) var slackTokenExpiresAt: Date? {
        didSet { defaults.set(slackTokenExpiresAt?.timeIntervalSince1970, forKey: Key.slackTokenExpiresAt) }
    }

    /// Only needed if Slack refuses to renew a PKCE token without one. Kept in the keychain
    /// so it never ships inside the app.
    public var slackClientSecret: String {
        didSet { keychain.set(slackClientSecret, for: .slackClientSecret) }
    }

    public var githubToken: String {
        didSet { keychain.set(githubToken, for: .githubToken) }
    }

    public var githubRepositories: String {
        didSet { defaults.set(githubRepositories, forKey: Key.githubRepositories) }
    }

    public init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain

        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
        refreshMinutes = defaults.object(forKey: Key.refreshMinutes) as? Int ?? 10
        query = TicketQuery(rawValue: defaults.string(forKey: Key.query) ?? "") ?? .default
        customJQL = defaults.string(forKey: Key.customJQL) ?? ""
        jiraSiteURL = defaults.string(forKey: Key.jiraSiteURL) ?? Self.bundledJiraSiteURL
        jiraEmail = defaults.string(forKey: Key.jiraEmail) ?? ""
        jiraBotAccountIDs = defaults.string(forKey: Key.jiraBotAccountIDs) ?? ""
        jiraAPIToken = keychain.value(for: .jiraAPIToken) ?? ""
        slackUserToken = keychain.value(for: .slackUserToken) ?? ""
        slackUserName = defaults.string(forKey: Key.slackUserName) ?? ""
        slackTeamName = defaults.string(forKey: Key.slackTeamName) ?? ""
        slackTeamID = defaults.string(forKey: Key.slackTeamID) ?? ""
        slackRefreshToken = keychain.value(for: .slackRefreshToken) ?? ""
        slackClientSecret = keychain.value(for: .slackClientSecret) ?? ""
        githubToken = keychain.value(for: .githubToken) ?? ""
        githubRepositories = defaults.string(forKey: Key.githubRepositories) ?? Self.bundledGitHubRepositories
        slackTokenExpiresAt = (defaults.object(forKey: Key.slackTokenExpiresAt) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
    }

    /// The JQL actually sent to Jira.
    public var jql: String {
        if let preset = query.jql { return preset }
        let trimmed = customJQL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TicketQuery.fallbackJQL : trimmed
    }

    public var strings: Strings { Strings(language: language.resolved) }

    public var relativeTime: RelativeTime { RelativeTime(language: language.resolved) }

    public var jiraConfiguration: JiraConfiguration? {
        JiraConfiguration(
            siteURLString: jiraSiteURL,
            email: jiraEmail,
            apiToken: jiraAPIToken,
            botAccountIDs: Self.parseAccountIDs(jiraBotAccountIDs)
        )
    }

    /// Splits ids the way people paste them: commas, spaces or newlines.
    static func parseAccountIDs(_ raw: String) -> Set<String> {
        Set(
            raw.split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map(String.init)
                .filter { $0.isEmpty.not }
        )
    }

    /// Prefilled on a fresh install so a new user only has to supply their own credentials.
    /// Set it in `Project.swift` under the `JiraSiteURL` Info.plist key.
    static var bundledJiraSiteURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "JiraSiteURL") as? String) ?? ""
    }

    /// Public, not a secret: Slack client IDs are safe to ship, and PKCE means no client
    /// secret is needed. Set it in `Project.swift` under the `SlackClientID` Info.plist key.
    public var slackClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "SlackClientID") as? String) ?? ""
    }

    /// The https relay page registered on the distributed Slack app, which bounces the
    /// browser back to the loopback receiver. Empty means the build is paired with a
    /// personal Slack app that has the localhost redirects registered directly. Set it in
    /// `Project.swift` under the `SlackRedirectURL` Info.plist key.
    public var slackRedirectURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "SlackRedirectURL") as? String) ?? ""
    }

    public func applySlackCredentials(_ credentials: SlackCredentials) {
        slackUserToken = credentials.userToken
        slackTokenExpiresAt = credentials.expiresAt
        // A renewal returns a fresh refresh token; an authorization sets the first one.
        if let refreshToken = credentials.refreshToken { slackRefreshToken = refreshToken }
        // A renewal carries no identity, so an empty name must not wipe the stored one.
        if credentials.userName.isEmpty.not { slackUserName = credentials.userName }
        if credentials.teamName.isEmpty.not { slackTeamName = credentials.teamName }
        if credentials.teamID.isEmpty.not { slackTeamID = credentials.teamID }
    }

    /// Fills in what `auth.test` knows and the stored credentials may not — a workspace
    /// connected before a field existed carries it from the next check onwards.
    public func applySlackIdentity(_ identity: SlackIdentity) {
        if identity.userName.isEmpty.not { slackUserName = identity.userName }
        if identity.teamName.isEmpty.not { slackTeamName = identity.teamName }
        if identity.teamID.isEmpty.not { slackTeamID = identity.teamID }
    }

    public func disconnectSlack() {
        slackUserToken = ""
        slackRefreshToken = ""
        slackTokenExpiresAt = nil
        slackUserName = ""
        slackTeamID = ""
        slackTeamName = ""
    }

    /// What to show next to the connection state.
    public var slackAccountLabel: String {
        [slackUserName, slackTeamName].filter { $0.isEmpty.not }.joined(separator: " · ")
    }

    static var bundledGitHubRepositories: String {
        (Bundle.main.object(forInfoDictionaryKey: "GitHubRepositories") as? String) ?? ""
    }

    public var githubConfiguration: GitHubConfiguration? {
        GitHubConfiguration(token: githubToken, repositories: githubRepositories)
    }

    public var isSlackConfigured: Bool {
        slackUserToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty.not
    }
}
