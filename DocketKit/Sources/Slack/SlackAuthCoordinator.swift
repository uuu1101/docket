//  SlackAuthCoordinator.swift
//  DocketKit

import AppKit
import Foundation
import Observation

/// Drives one Slack authorization from start to stored token.
@MainActor
@Observable
public final class SlackAuthCoordinator {
    public enum Phase: Equatable, Sendable {
        case idle
        case waitingForBrowser
        case exchanging
        case failed(String)

        public var isRunning: Bool {
            self == .waitingForBrowser || self == .exchanging
        }
    }

    public private(set) var phase: Phase = .idle

    private let settings: AppSettings
    private var receiver: LoopbackAuthReceiver?
    private var task: Task<Void, Never>?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var redirectURIs: [String] {
        SlackOAuth.redirectPorts.map(SlackOAuth.redirectURI(port:))
    }

    public func connect() {
        guard phase.isRunning.not else { return }
        task?.cancel()
        task = Task { await run() }
    }

    public func cancel() {
        task?.cancel()
        receiver?.cancelAuthorization()
        receiver = nil
        phase = .idle
    }

    public func disconnect() {
        settings.disconnectSlack()
        phase = .idle
    }

    private func run() async {
        let clientID = settings.slackClientID
        guard clientID.isEmpty.not else {
            phase = .failed(settings.strings.slackOAuthErrorMessage(.missingClientID))
            return
        }

        let receiver = LoopbackAuthReceiver()
        self.receiver = receiver
        defer {
            receiver.stop()
            self.receiver = nil
        }

        do {
            let port = try await receiver.start(ports: SlackOAuth.redirectPorts)
            let challenge = PKCEChallenge.random()
            // Ties the redirect back to this attempt, so another tab's callback cannot land here.
            let random = PKCEChallenge.randomToken()

            // A distributed app can only register https redirects, so the browser goes to
            // the relay page, which reads the port off the state and bounces back here. A
            // build paired with a personal app comes straight back to localhost.
            let relay = settings.slackRedirectURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let redirectURI = relay.isEmpty ? SlackOAuth.redirectURI(port: port) : relay
            let state = relay.isEmpty ? random : SlackOAuth.relayState(random: random, port: port)

            let oauth = SlackOAuth(clientID: clientID)
            let authorizeURL = try oauth.authorizeURL(
                redirectURI: redirectURI,
                challenge: challenge,
                state: state
            )

            phase = .waitingForBrowser
            NSWorkspace.shared.open(authorizeURL)

            let callback = try await receiver.awaitCallback()
            guard callback.state == state else { throw SlackOAuthError.stateMismatch }

            phase = .exchanging
            let credentials = try await oauth.exchange(
                code: callback.code,
                verifier: challenge.verifier,
                redirectURI: redirectURI
            )

            settings.applySlackCredentials(try await Self.named(credentials))
            phase = .idle
        } catch let error as SlackOAuthError {
            phase = .failed(settings.strings.slackOAuthErrorMessage(error))
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(settings.strings.slackOAuthErrorMessage(.network(error.localizedDescription)))
        }
    }

    /// The exchange returns ids only, so the display names come from `auth.test`.
    /// A failure here costs a label, not the connection.
    private static func named(_ credentials: SlackCredentials) async throws -> SlackCredentials {
        guard let identity = try? await LiveSlackAPI(token: credentials.userToken).identity() else {
            return credentials
        }
        return SlackCredentials(
            userToken: credentials.userToken,
            userID: identity.userID.isEmpty ? credentials.userID : identity.userID,
            userName: identity.userName,
            teamName: identity.teamName.isEmpty ? credentials.teamName : identity.teamName,
            refreshToken: credentials.refreshToken,
            expiresAt: credentials.expiresAt
        )
    }
}
