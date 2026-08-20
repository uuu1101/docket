//  JiraAPI.swift
//  DocketKit

import Foundation

public protocol JiraAPI: Sendable {
    func account() async throws(JiraError) -> JiraAccount
    func issues(jql: String, maxResults: Int, extraFieldID: String?) async throws(JiraError) -> [JiraIssue]
    /// The generated id of a custom field, looked up by its display name.
    func fieldID(named name: String) async throws(JiraError) -> String?
}

public struct JiraConfiguration: Sendable, Equatable {
    public let siteURL: URL
    public let email: String
    public let apiToken: String

    public init(siteURL: URL, email: String, apiToken: String) {
        self.siteURL = siteURL
        self.email = email
        self.apiToken = apiToken
    }

    /// Builds a configuration only when every field is present and the site parses as a URL.
    public init?(siteURLString: String, email: String, apiToken: String?) {
        let trimmed = siteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty.not,
              email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty.not,
              let apiToken, apiToken.isEmpty.not
        else { return nil }

        let normalized = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized),
              url.host != nil
        else { return nil }

        self.init(siteURL: url, email: email.trimmingCharacters(in: .whitespacesAndNewlines), apiToken: apiToken)
    }

    /// Used when only the Slack half of a `SyncEngine` is needed.
    public static let placeholder = JiraConfiguration(
        siteURL: URL(string: "https://example.invalid")!,
        email: "",
        apiToken: ""
    )

    var authorizationHeader: String {
        let credentials = Data("\(email):\(apiToken)".utf8).base64EncodedString()
        return "Basic \(credentials)"
    }
}

public struct LiveJiraAPI: JiraAPI {
    private let configuration: JiraConfiguration
    private let session: URLSession

    public init(configuration: JiraConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func account() async throws(JiraError) -> JiraAccount {
        let data = try await get(path: "/rest/api/3/myself", query: [])
        return try decode(JiraMyselfRemoteModel.self, from: data).asEntity
    }

    public func issues(jql: String, maxResults: Int, extraFieldID: String?) async throws(JiraError) -> [JiraIssue] {
        var fields = "summary,status,priority,issuetype,updated,description"
        if let extraFieldID { fields += ",\(extraFieldID)" }

        let data = try await get(
            path: "/rest/api/3/search/jql",
            query: [
                URLQueryItem(name: "jql", value: jql),
                URLQueryItem(name: "fields", value: fields),
                URLQueryItem(name: "maxResults", value: String(maxResults)),
            ]
        )
        let response = try decode(JiraSearchResponse.self, from: data)
        return response.issues.map {
            $0.asEntity(siteURL: configuration.siteURL, targetEndFieldID: extraFieldID)
        }
    }

    public func fieldID(named name: String) async throws(JiraError) -> String? {
        let data = try await get(path: "/rest/api/3/field", query: [])
        let fields = try decode([JiraFieldRemoteModel].self, from: data)
        let wanted = name.lowercased()
        return fields.first { $0.name?.lowercased() == wanted }?.id
    }

    // MARK: - Transport

    private func get(path: String, query: [URLQueryItem]) async throws(JiraError) -> Data {
        guard var components = URLComponents(
            url: configuration.siteURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw .invalidSite }

        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw .invalidSite }

        var request = URLRequest(url: url)
        request.setValue(configuration.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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

        switch http.statusCode {
        case 200 ..< 300:
            return data
        case 401, 403:
            throw .unauthorized
        default:
            throw .http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(JiraError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .decoding(error.localizedDescription)
        }
    }

    /// Jira returns `{"errorMessages": [...]}` on most failures; fall back to raw text.
    private static func errorMessage(from data: Data) -> String {
        struct Payload: Decodable {
            let errorMessages: [String]?
        }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data),
           let first = payload.errorMessages?.first {
            return first
        }
        return ""
    }
}
