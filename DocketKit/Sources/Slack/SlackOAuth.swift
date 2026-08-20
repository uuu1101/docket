//  SlackOAuth.swift
//  DocketKit

import CryptoKit
import Foundation

public enum SlackOAuthError: Error, Sendable, Equatable {
    case missingClientID
    case noAvailablePort
    case listenerFailed(String)
    case cancelled
    case timedOut
    case stateMismatch
    case denied(String)
    case missingUserToken
    case missingRefreshToken
    case network(String)
    case api(String)
    case decoding(String)
}

/// The credentials handed back by a completed authorization.
public struct SlackCredentials: Sendable, Equatable {
    public let userToken: String
    public let userID: String
    public let userName: String
    public let teamName: String
    /// Present when the app is a PKCE public client, which Slack always treats as rotating.
    public let refreshToken: String?
    /// `nil` for a non-rotating token, which never needs renewing.
    public let expiresAt: Date?

    public init(
        userToken: String,
        userID: String,
        userName: String,
        teamName: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.userToken = userToken
        self.userID = userID
        self.userName = userName
        self.teamName = teamName
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// PKCE authorization for Slack, built for a keyless desktop client.
///
/// Slack's `oauth.v2.access` normally needs a client secret, which a distributed desktop
/// app cannot hold. PKCE replaces the secret with a per-attempt verifier, so no backend and
/// no embedded secret are required.
public struct SlackOAuth: Sendable {
    /// Everything the app needs from Slack, and nothing more.
    ///
    /// This list is what Slack actually grants — the scopes on the app configuration only
    /// set the ceiling, so adding one there without adding it here changes nothing.
    public static let userScopes = [
        // Reads a thread's root message, reply count and participants. Each conversation
        // type needs its own history scope.
        "channels:history",
        "groups:history",
        "im:history",
        "mpim:history",
        // Turns user ids into display names.
        "users:read",
        // Resolves the channel name an attached thread lives in.
        "channels:read",
        "groups:read",
    ]

    /// Slack matches the redirect URI exactly, so the ports have to be fixed and registered
    /// on the app config. Several are offered because a single one can be taken.
    public static let redirectPorts: [UInt16] = [53682, 53683, 53684]

    public static func redirectURI(port: UInt16) -> String {
        "http://localhost:\(port)/slack/callback"
    }

    /// The state a distributed app sends: the random token with the loopback port as a
    /// suffix. Slack refuses public distribution while any redirect URL is plain http, so
    /// the browser goes to an https relay page instead — and that page learns which port
    /// to bounce back to from the state, the only value Slack passes through untouched.
    public static func relayState(random: String, port: UInt16) -> String {
        "\(random).\(port)"
    }

    public let clientID: String
    /// Slack's own docs disagree on whether renewing a PKCE token needs a secret, so it is
    /// optional: the app tries without one and only asks for it if Slack insists.
    public let clientSecret: String?
    private let session: URLSession

    public init(clientID: String, clientSecret: String? = nil, session: URLSession = .shared) {
        self.clientID = clientID
        self.clientSecret = clientSecret?.nilIfEmpty
        self.session = session
    }

    // MARK: - Authorization URL

    public func authorizeURL(redirectURI: String, challenge: PKCEChallenge, state: String) throws(SlackOAuthError) -> URL {
        guard clientID.isEmpty.not else { throw .missingClientID }

        var components = URLComponents(string: "https://slack.com/oauth/v2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            // No bot scopes: search.messages is a user-token endpoint.
            URLQueryItem(name: "scope", value: ""),
            URLQueryItem(name: "user_scope", value: Self.userScopes.joined(separator: ",")),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = components?.url else { throw .api("Could not build the authorize URL") }
        return url
    }

    // MARK: - Code exchange

    public func exchange(
        code: String,
        verifier: String,
        redirectURI: String
    ) async throws(SlackOAuthError) -> SlackCredentials {
        guard clientID.isEmpty.not else { throw .missingClientID }

        return try await post([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
        ])
    }

    /// Renews a rotating token. PKCE parameters play no part here — only the refresh token.
    public func refresh(refreshToken: String) async throws(SlackOAuthError) -> SlackCredentials {
        guard clientID.isEmpty.not else { throw .missingClientID }

        var parameters = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        if let clientSecret { parameters["client_secret"] = clientSecret }

        return try await post(parameters)
    }

    private func post(_ parameters: [String: String]) async throws(SlackOAuthError) -> SlackCredentials {
        guard let url = URL(string: "https://slack.com/api/oauth.v2.access") else {
            throw .network("Invalid endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncoded(parameters).utf8)
        request.timeoutInterval = 20

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw .network(error.localizedDescription)
        }

        return try Self.credentials(from: data)
    }

    static func credentials(from data: Data) throws(SlackOAuthError) -> SlackCredentials {
        let payload: OAuthAccessPayload
        do {
            payload = try JSONDecoder().decode(OAuthAccessPayload.self, from: data)
        } catch {
            throw .decoding(error.localizedDescription)
        }

        guard payload.ok else { throw .api(payload.error ?? "unknown") }

        // An authorization nests the token under `authed_user`; a refresh returns it flat.
        let fields = payload.tokenFields
        guard let token = fields.accessToken?.nilIfEmpty else { throw .missingUserToken }

        return SlackCredentials(
            userToken: token,
            userID: fields.id ?? "",
            userName: "",
            teamName: payload.team?.name ?? "",
            refreshToken: fields.refreshToken?.nilIfEmpty,
            expiresAt: fields.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    private static func formEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }
}

// MARK: - PKCE

public struct PKCEChallenge: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    /// Derives the S256 challenge Slack expects from a verifier.
    public init(verifier: String) {
        self.verifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64URLEncodedString
    }

    public static func random() -> PKCEChallenge {
        PKCEChallenge(verifier: Self.randomToken())
    }

    /// 32 random bytes, base64url encoded: 43 characters, inside PKCE's 43...128 range and
    /// using only unreserved characters.
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // An all-zero buffer would make the verifier and state predictable, so a failure
        // falls back to the system generator rather than proceeding silently.
        if status != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes).base64URLEncodedString
    }
}

extension Data {
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Wire format

struct OAuthAccessPayload: Decodable {
    let ok: Bool
    let error: String?
    let authedUser: AuthedUser?
    let team: Team?
    let id: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    /// The nested shape when present, the flat one otherwise.
    var tokenFields: AuthedUser {
        authedUser ?? AuthedUser(
            id: id,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            scope: nil
        )
    }

    struct AuthedUser: Decodable {
        let id: String?
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case id, scope
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    struct Team: Decodable {
        let id: String?
        let name: String?
    }

    enum CodingKeys: String, CodingKey {
        case ok, error, team, id
        case authedUser = "authed_user"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
