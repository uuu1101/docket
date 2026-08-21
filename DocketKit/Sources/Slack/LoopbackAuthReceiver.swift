//  LoopbackAuthReceiver.swift
//  DocketKit

import Foundation
import Network

/// Catches Slack's OAuth redirect on a loopback port.
///
/// Slack accepts `http://localhost` as a desktop redirect only while PKCE is enabled — and
/// PKCE also makes the issued token a rotating one, whatever the app config says, which the
/// token store is built around. The listener is opened for one request and closed.
@MainActor
public final class LoopbackAuthReceiver {
    public struct Callback: Sendable, Equatable {
        public let code: String
        public let state: String?
    }

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var bindContinuation: CheckedContinuation<Bool, Never>?
    private var callbackContinuation: CheckedContinuation<Callback, any Error>?
    private var timeoutTask: Task<Void, Never>?

    public init() {}

    /// Binds the first free port. Slack matches the redirect URI exactly, so callers must
    /// build their redirect from the port returned here.
    public func start(ports: [UInt16]) async throws(SlackOAuthError) -> UInt16 {
        for port in ports where await bind(port: port) {
            return port
        }
        throw .noAvailablePort
    }

    public func awaitCallback(timeout: Duration = .seconds(300)) async throws -> Callback {
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard Task.isCancelled.not else { return }
            self?.finish(with: .failure(SlackOAuthError.timedOut))
        }

        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    public func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    public func cancelAuthorization() {
        finish(with: .failure(SlackOAuthError.cancelled))
    }

    // MARK: - Binding

    private func bind(port: UInt16) async -> Bool {
        // Loopback only: the redirect always arrives from this machine's own browser, and
        // a wildcard bind would expose the port — and the ability to kill an in-flight
        // authorization — to the local network.
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        guard let endpointPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: parameters, on: endpointPort)
        else { return false }

        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state: state, of: listener) }
        }

        let didBind = await withCheckedContinuation { continuation in
            bindContinuation = continuation
            listener.start(queue: .main)
        }

        if didBind.not { self.listener = nil }
        return didBind
    }

    private func handle(state: NWListener.State, of listener: NWListener) {
        switch state {
        case .ready:
            resumeBind(with: true)
        case .failed, .cancelled:
            listener.cancel()
            resumeBind(with: false)
        default:
            break
        }
    }

    private func resumeBind(with didBind: Bool) {
        guard let bindContinuation else { return }
        self.bindContinuation = nil
        bindContinuation.resume(returning: didBind)
    }

    // MARK: - Receiving the redirect

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, let data, data.isEmpty.not else { return }
                self.handle(request: data, on: connection)
            }
        }
    }

    private func handle(request: Data, on connection: NWConnection) {
        let result = Self.parse(request: request)
        respond(on: connection, succeeded: result != nil)

        guard let result else { return }
        finish(with: .success(result))
    }

    /// Pulls the query out of the request line: `GET /slack/callback?code=…&state=… HTTP/1.1`.
    static func parse(request: Data) -> Callback? {
        guard let text = String(data: request, encoding: .utf8),
              let requestLine = text.split(separator: "\r\n", maxSplits: 1).first
        else { return nil }

        let fields = requestLine.split(separator: " ")
        guard fields.count >= 2, fields[0] == "GET" else { return nil }

        guard let components = URLComponents(string: "http://localhost\(fields[1])"),
              let items = components.queryItems
        else { return nil }

        guard let code = items.first(where: { $0.name == "code" })?.value?.nilIfEmpty else { return nil }
        return Callback(code: code, state: items.first { $0.name == "state" }?.value)
    }

    private func respond(on connection: NWConnection, succeeded: Bool) {
        let title = succeeded ? "Docket is connected" : "Something went wrong"
        let detail = succeeded ? "You can close this tab and go back to Docket." : "Try connecting again from Docket."
        let body = """
        <!doctype html><meta charset="utf-8">
        <title>\(title)</title>
        <div style="font:16px -apple-system,system-ui,sans-serif;text-align:center;margin-top:22vh;color:#1d1d1f">
        <h1 style="font-size:22px">\(title)</h1><p style="color:#6e6e73">\(detail)</p></div>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(with result: Result<Callback, any Error>) {
        guard let callbackContinuation else { return }
        self.callbackContinuation = nil
        stop()
        callbackContinuation.resume(with: result)
    }
}
