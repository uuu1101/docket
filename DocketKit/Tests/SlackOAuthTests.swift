//  SlackOAuthTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@Suite("PKCE")
struct PKCETests {
    @Test("The S256 challenge matches the RFC 7636 test vector")
    func rfcTestVector() {
        let challenge = PKCEChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(challenge.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("A generated verifier fits PKCE's length range")
    func verifierLength() {
        let verifier = PKCEChallenge.random().verifier
        #expect(verifier.count >= 43)
        #expect(verifier.count <= 128)
    }

    @Test("A generated verifier uses only unreserved characters")
    func verifierCharacters() {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(PKCEChallenge.random().verifier.allSatisfy { allowed.contains($0) })
    }

    @Test("Base64url output carries no padding or URL-unsafe characters")
    func base64URLSafety() {
        let challenge = PKCEChallenge.random().challenge
        #expect(challenge.contains("=") == false)
        #expect(challenge.contains("+") == false)
        #expect(challenge.contains("/") == false)
    }

    @Test("Two attempts never share a verifier")
    func verifiersAreUnique() {
        #expect(PKCEChallenge.random().verifier != PKCEChallenge.random().verifier)
    }
}

@Suite("Authorize URL")
struct AuthorizeURLTests {
    private let oauth = SlackOAuth(clientID: "123.456")

    private func items() throws -> [String: String] {
        let url = try oauth.authorizeURL(
            redirectURI: "http://localhost:53682/slack/callback",
            challenge: PKCEChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            state: "abc123"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @Test("It points at Slack's v2 authorize endpoint")
    func endpoint() throws {
        let url = try oauth.authorizeURL(
            redirectURI: "http://localhost:53682/slack/callback",
            challenge: PKCEChallenge.random(),
            state: "s"
        )
        #expect(url.absoluteString.hasPrefix("https://slack.com/oauth/v2/authorize?"))
    }

    @Test("It carries the PKCE challenge and the S256 method")
    func pkceParameters() throws {
        let items = try items()
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items["code_challenge_method"] == "S256")
    }

    @Test("It requests user scopes and no bot scopes")
    func scopes() throws {
        let items = try items()
        #expect(items["scope"] == "")
        let requested = Set((items["user_scope"] ?? "").split(separator: ",").map(String.init))
        #expect(requested == Set(SlackOAuth.userScopes))
    }

    @Test("Every scope the app calls with is actually requested")
    func requiredScopesRequested() {
        // Each of these backs a call the app makes; a token without it fails at runtime,
        // and adding it to the Slack app config alone does not grant it.
        let required = [
            "channels:history", "groups:history", "im:history", "mpim:history",
            "users:read", "channels:read", "groups:read",
        ]
        #expect(Set(required).isSubset(of: Set(SlackOAuth.userScopes)))
    }

    @Test("Scopes the app no longer uses are not requested")
    func retiredScopesDropped() {
        #expect(SlackOAuth.userScopes.contains("search:read") == false)
    }

    @Test("It passes the state through for the callback to match")
    func state() throws {
        #expect(try items()["state"] == "abc123")
    }

    @Test("Without a client ID it refuses to build a URL")
    func missingClientID() {
        #expect(throws: SlackOAuthError.missingClientID) {
            try SlackOAuth(clientID: "").authorizeURL(
                redirectURI: "http://localhost:53682/slack/callback",
                challenge: PKCEChallenge.random(),
                state: "s"
            )
        }
    }

    @Test("Redirect URIs are loopback HTTP on the registered ports")
    func redirectURIs() {
        #expect(SlackOAuth.redirectPorts.isEmpty == false)
        for port in SlackOAuth.redirectPorts {
            #expect(SlackOAuth.redirectURI(port: port) == "http://localhost:\(port)/slack/callback")
        }
    }
}

@Suite("Reading the token response")
struct TokenExchangeDecodingTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test("A user token is pulled out of authed_user")
    func success() throws {
        let credentials = try SlackOAuth.credentials(from: data("""
        {"ok":true,"app_id":"A1",
         "authed_user":{"id":"U1","scope":"search:read","access_token":"xoxp-123","token_type":"user"},
         "team":{"id":"T1","name":"MVL"}}
        """))
        #expect(credentials.userToken == "xoxp-123")
        #expect(credentials.userID == "U1")
        #expect(credentials.teamName == "MVL")
    }

    @Test("Slack's own error is surfaced verbatim")
    func slackError() {
        #expect(throws: SlackOAuthError.api("invalid_code")) {
            try SlackOAuth.credentials(from: data(#"{"ok":false,"error":"invalid_code"}"#))
        }
    }

    @Test("A response without a user token is rejected rather than half-stored")
    func missingToken() {
        #expect(throws: SlackOAuthError.missingUserToken) {
            try SlackOAuth.credentials(from: data(#"{"ok":true,"authed_user":{"id":"U1"}}"#))
        }
    }

    @Test("A rotating token keeps its refresh token and expiry")
    func rotatingToken() throws {
        let credentials = try SlackOAuth.credentials(from: data("""
        {"ok":true,
         "authed_user":{"id":"U1","access_token":"xoxe.xoxp-1-abc","refresh_token":"xoxe-1-abc","expires_in":43200}}
        """))
        #expect(credentials.userToken == "xoxe.xoxp-1-abc")
        #expect(credentials.refreshToken == "xoxe-1-abc")
        let expiresAt = try #require(credentials.expiresAt)
        // 12 hours out, allowing for the moment spent decoding.
        #expect(abs(expiresAt.timeIntervalSinceNow - 43_200) < 5)
    }

    @Test("A non-rotating token records no expiry, so nothing tries to renew it")
    func nonRotatingToken() throws {
        let credentials = try SlackOAuth.credentials(from: data("""
        {"ok":true,"authed_user":{"id":"U1","access_token":"xoxp-123","token_type":"user"}}
        """))
        #expect(credentials.expiresAt == nil)
        #expect(credentials.refreshToken == nil)
    }

    @Test("A renewal response is read from the top level, not from authed_user")
    func refreshResponseShape() throws {
        let credentials = try SlackOAuth.credentials(from: data("""
        {"ok":true,"token_type":"user","access_token":"xoxe.xoxp-1-new",
         "refresh_token":"xoxe-1-new","expires_in":43200}
        """))
        #expect(credentials.userToken == "xoxe.xoxp-1-new")
        #expect(credentials.refreshToken == "xoxe-1-new")
        #expect(credentials.expiresAt != nil)
    }

    @Test("A renewal carries no identity, and must not present an empty one as real")
    func refreshCarriesNoIdentity() throws {
        let credentials = try SlackOAuth.credentials(from: data("""
        {"ok":true,"access_token":"xoxe.xoxp-1-new","refresh_token":"xoxe-1-new","expires_in":43200}
        """))
        #expect(credentials.userName.isEmpty)
        #expect(credentials.teamName.isEmpty)
    }

    @Test("Malformed JSON reports a decoding failure")
    func malformed() {
        #expect(throws: (any Error).self) {
            try SlackOAuth.credentials(from: data("not json"))
        }
    }
}

@MainActor
@Suite("Parsing the loopback redirect")
struct LoopbackParsingTests {
    private func request(_ line: String) -> Data {
        Data("\(line)\r\nHost: localhost\r\n\r\n".utf8)
    }

    @Test("The code and state come out of the request line")
    func validRequest() {
        let callback = LoopbackAuthReceiver.parse(
            request: request("GET /slack/callback?code=abc&state=xyz HTTP/1.1")
        )
        #expect(callback?.code == "abc")
        #expect(callback?.state == "xyz")
    }

    @Test("A request without a code is not a usable callback")
    func missingCode() {
        #expect(LoopbackAuthReceiver.parse(request: request("GET /slack/callback?state=xyz HTTP/1.1")) == nil)
    }

    @Test("A denial redirect carries no code and is rejected")
    func deniedRedirect() {
        #expect(LoopbackAuthReceiver.parse(request: request("GET /slack/callback?error=access_denied HTTP/1.1")) == nil)
    }

    @Test("An empty code is treated as absent")
    func emptyCode() {
        #expect(LoopbackAuthReceiver.parse(request: request("GET /slack/callback?code=&state=xyz HTTP/1.1")) == nil)
    }

    @Test("Only GET is accepted")
    func nonGET() {
        #expect(LoopbackAuthReceiver.parse(request: request("POST /slack/callback?code=abc HTTP/1.1")) == nil)
    }

    @Test("A garbage request line yields nil rather than a bogus code")
    func garbage() {
        #expect(LoopbackAuthReceiver.parse(request: Data("\r\n\r\n".utf8)) == nil)
    }

    @Test("A callback with no state is parsed, so the caller can reject the mismatch")
    func missingState() {
        let callback = LoopbackAuthReceiver.parse(request: request("GET /slack/callback?code=abc HTTP/1.1"))
        #expect(callback?.code == "abc")
        #expect(callback?.state == nil)
    }
}

@MainActor
@Suite("Renewing a rotating token")
struct TokenRenewalTests {
    private func makeSettings() -> AppSettings {
        AppSettings(
            defaults: UserDefaults(suiteName: "dev.taetae.docket.tests.\(UUID().uuidString)")!,
            keychain: KeychainStore(service: "dev.taetae.docket.tests.\(UUID().uuidString)")
        )
    }

    @Test("Authorization stores the token, its refresh token and its expiry")
    func storesRotatingCredentials() {
        let settings = makeSettings()
        settings.applySlackCredentials(
            SlackCredentials(
                userToken: "xoxe.xoxp-1-abc",
                userID: "U1",
                userName: "theo",
                teamName: "MVL",
                refreshToken: "xoxe-1-abc",
                expiresAt: Date(timeIntervalSinceNow: 43_200)
            )
        )
        #expect(settings.slackUserToken == "xoxe.xoxp-1-abc")
        #expect(settings.slackRefreshToken == "xoxe-1-abc")
        #expect(settings.slackTokenExpiresAt != nil)
        #expect(settings.slackAccountLabel == "theo · MVL")
    }

    @Test("A renewal replaces the token without erasing the stored identity")
    func renewalKeepsIdentity() {
        let settings = makeSettings()
        settings.applySlackCredentials(
            SlackCredentials(
                userToken: "old",
                userID: "U1",
                userName: "theo",
                teamName: "MVL",
                refreshToken: "refresh-1",
                expiresAt: Date(timeIntervalSinceNow: 60)
            )
        )
        // A refresh response carries a token and nothing else.
        settings.applySlackCredentials(
            SlackCredentials(
                userToken: "new",
                userID: "",
                userName: "",
                teamName: "",
                refreshToken: "refresh-2",
                expiresAt: Date(timeIntervalSinceNow: 43_200)
            )
        )
        #expect(settings.slackUserToken == "new")
        #expect(settings.slackRefreshToken == "refresh-2")
        #expect(settings.slackAccountLabel == "theo · MVL")
    }

    @Test("Disconnecting clears the refresh token and the expiry too")
    func disconnectClearsEverything() {
        let settings = makeSettings()
        settings.applySlackCredentials(
            SlackCredentials(
                userToken: "t",
                userID: "U1",
                userName: "theo",
                teamName: "MVL",
                refreshToken: "r",
                expiresAt: Date(timeIntervalSinceNow: 43_200)
            )
        )
        settings.disconnectSlack()
        #expect(settings.slackUserToken.isEmpty)
        #expect(settings.slackRefreshToken.isEmpty)
        #expect(settings.slackTokenExpiresAt == nil)
        #expect(settings.isSlackConfigured == false)
    }

    @Test("A token comfortably inside its life is handed over as is")
    func validTokenNotRenewed() async throws {
        let settings = makeSettings()
        settings.applySlackCredentials(
            SlackCredentials(
                userToken: "still-good",
                userID: "U1",
                userName: "theo",
                teamName: "MVL",
                refreshToken: "r",
                expiresAt: Date(timeIntervalSinceNow: 3_600)
            )
        )
        let token = try await SlackTokenStore(settings: settings).validToken()
        #expect(token == "still-good")
    }

    @Test("A token with no expiry is never renewed")
    func nonExpiringTokenNotRenewed() async throws {
        let settings = makeSettings()
        settings.applySlackCredentials(
            SlackCredentials(userToken: "forever", userID: "U1", userName: "theo", teamName: "MVL")
        )
        #expect(settings.slackTokenExpiresAt == nil)
        let token = try await SlackTokenStore(settings: settings).validToken()
        #expect(token == "forever")
    }

    @Test("With no token at all the store reports Slack as unconfigured")
    func noToken() async {
        let store = SlackTokenStore(settings: makeSettings())
        await #expect(throws: SlackError.notConfigured) { try await store.validToken() }
    }

    @Test("An expired token with no refresh token fails loudly instead of retrying forever")
    func expiredWithoutRefreshToken() async {
        let settings = makeSettings()
        settings.applySlackCredentials(
            SlackCredentials(
                userToken: "expired",
                userID: "U1",
                userName: "theo",
                teamName: "MVL",
                expiresAt: Date(timeIntervalSinceNow: -60)
            )
        )
        let store = SlackTokenStore(settings: settings)
        await #expect(throws: (any Error).self) { try await store.validToken() }
    }
}

@Suite("Relay redirect state")
struct RelayStateTests {
    @Test("The relay state carries the loopback port as its suffix")
    func carriesPort() {
        #expect(SlackOAuth.relayState(random: "abc-123_x", port: 53683) == "abc-123_x.53683")
    }

    @Test("The random part survives untouched, so the exact-match check still holds")
    func randomPartIntact() {
        let random = PKCEChallenge.randomToken()
        let state = SlackOAuth.relayState(random: random, port: 53682)
        #expect(state.hasPrefix(random))
        #expect(state.hasSuffix(".53682"))
    }
}

@MainActor
@Suite("Pasting a token by hand")
struct ManualTokenTests {
    @Test("A pasted token sheds the previous connection's rotation state and identity")
    func pastedTokenClearsRotationState() {
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "dev.taetae.docket.tests.\(UUID().uuidString)")!,
            keychain: KeychainStore(service: "dev.taetae.docket.tests.\(UUID().uuidString)")
        )
        settings.applySlackCredentials(SlackCredentials(
            userToken: "xoxe.xoxp-1-old",
            userID: "U1",
            userName: "Theo",
            teamName: "Acme",
            teamID: "T1",
            refreshToken: "xoxe-1-old",
            expiresAt: Date().addingTimeInterval(43_200)
        ))

        settings.applyManualSlackToken("xoxp-manual")

        #expect(settings.slackUserToken == "xoxp-manual")
        #expect(settings.slackTokenExpiresAt == nil)
        #expect(settings.slackRefreshToken.isEmpty)
        #expect(settings.slackAccountLabel.isEmpty)
        #expect(settings.isSlackConfigured)
    }
}
