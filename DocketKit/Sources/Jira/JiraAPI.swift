//  JiraAPI.swift
//  DocketKit

import Foundation

public protocol JiraAPI: Sendable {
    func account() async throws(JiraError) -> JiraAccount
    func issues(jql: String, maxResults: Int, extraFieldID: String?) async throws(JiraError) -> [JiraIssue]
    /// The generated id of a custom field, looked up by its display name.
    func fieldID(named name: String) async throws(JiraError) -> String?
    /// The moves the workflow allows from an issue's current status. Depends on the issue,
    /// the workflow and the caller's permissions, so it cannot be fetched in bulk.
    func transitions(issueKey: String) async throws(JiraError) -> [JiraTransition]
    func performTransition(issueKey: String, transitionID: String) async throws(JiraError)
    /// The images and videos the description embeds, in document order.
    func descriptionMedia(issueKey: String) async throws(JiraError) -> [JiraDescriptionMedia]
    /// One attachment's bytes. `thumbnail` asks Jira for its scaled copy, which is what a
    /// description-sized image needs.
    func attachment(id: String, thumbnail: Bool) async throws(JiraError) -> Data
    /// The newest comments a person wrote on an issue, oldest first. Fetched per issue when one
    /// is opened: asking for the comment field on the ticket list tripled the response, since
    /// Jira sends the bodies rather than just a count.
    func comments(issueKey: String, limit: Int) async throws(JiraError) -> JiraComments
}

public struct JiraConfiguration: Sendable, Equatable {
    public let siteURL: URL
    public let email: String
    public let apiToken: String
    /// Site-automation accounts whose comments are hidden. Bots reporting
    /// `accountType: "app"` need no listing; this is for the ones a site runs from an
    /// ordinary account, indistinguishable from a colleague by type alone.
    public let botAccountIDs: Set<String>

    public init(siteURL: URL, email: String, apiToken: String, botAccountIDs: Set<String> = []) {
        self.siteURL = siteURL
        self.email = email
        self.apiToken = apiToken
        self.botAccountIDs = botAccountIDs
    }

    /// Builds a configuration only when every field is present and the site parses as a URL.
    public init?(siteURLString: String, email: String, apiToken: String?, botAccountIDs: Set<String> = []) {
        let trimmed = siteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty.not,
              email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty.not,
              let apiToken, apiToken.isEmpty.not
        else { return nil }

        // Basic credentials ride on every request, so only https is ever modelled: a
        // pasted http:// address is upgraded, anything stranger is refused.
        var normalized = trimmed
        if normalized.lowercased().hasPrefix("http://") {
            normalized = "https://" + normalized.dropFirst("http://".count)
        } else if normalized.lowercased().hasPrefix("https://").not {
            normalized = "https://\(normalized)"
        }
        guard let url = URL(string: normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized),
              url.host != nil,
              url.scheme?.lowercased() == "https"
        else { return nil }

        self.init(
            siteURL: url,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            apiToken: apiToken,
            botAccountIDs: botAccountIDs
        )
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

    /// Jira's own page size, and enough to reach past the longest run of automation seen.
    static let commentPageSize = 50

    public func descriptionMedia(issueKey: String) async throws(JiraError) -> [JiraDescriptionMedia] {
        let data = try await get(
            path: "/rest/api/3/issue/\(issueKey)",
            query: [
                URLQueryItem(name: "fields", value: "description"),
                // Jira's own rendering is the only place the attachment behind a media node
                // is named.
                URLQueryItem(name: "expand", value: "renderedFields"),
            ]
        )
        return try decode(JiraRenderedFieldsResponse.self, from: data).descriptionMedia
    }

    public func attachment(id: String, thumbnail: Bool) async throws(JiraError) -> Data {
        try await get(
            path: "/rest/api/3/attachment/\(thumbnail ? "thumbnail" : "content")/\(id)",
            query: [],
            accept: "*/*"
        )
    }

    public func comments(issueKey: String, limit: Int) async throws(JiraError) -> JiraComments {
        let data = try await get(
            path: "/rest/api/3/issue/\(issueKey)/comment",
            query: [
                // Newest first, so a long thread yields its tail rather than its head.
                URLQueryItem(name: "orderBy", value: "-created"),
                // Wider than what is shown, because automation fills the newest comments on
                // some tickets and the conversation sits behind it.
                URLQueryItem(name: "maxResults", value: String(Self.commentPageSize)),
            ]
        )
        let response = try decode(JiraCommentsResponse.self, from: data)
        let newestFirst = response.comments?
            .compactMap { $0.asEntity(listedBotIDs: configuration.botAccountIDs) } ?? []
        return JiraComments.page(
            from: newestFirst,
            total: response.total ?? newestFirst.count,
            limit: limit
        )
    }

    public func transitions(issueKey: String) async throws(JiraError) -> [JiraTransition] {
        let data = try await get(
            path: "/rest/api/3/issue/\(issueKey)/transitions",
            query: [URLQueryItem(name: "expand", value: "transitions.fields")]
        )
        return try decode(JiraTransitionsResponse.self, from: data).transitions?.compactMap(\.asEntity) ?? []
    }

    public func performTransition(issueKey: String, transitionID: String) async throws(JiraError) {
        let body = try encode(["transition": ["id": transitionID]])
        _ = try await post(path: "/rest/api/3/issue/\(issueKey)/transitions", body: body)
    }

    // MARK: - Transport

    /// `accept` is a parameter because an attachment is bytes: asking for JSON makes Jira
    /// answer with an error rather than the file.
    private func get(path: String, query: [URLQueryItem], accept: String = "application/json") async throws(JiraError) -> Data {
        try await perform(request(path: path, query: query, accept: accept))
    }

    private func post(path: String, body: Data) async throws(JiraError) -> Data {
        var request = try request(path: path, query: [])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request)
    }

    /// One URL construction and one header set for both verbs, so encoding rules and
    /// failure classification cannot quietly diverge between reads and writes.
    private func request(path: String, query: [URLQueryItem], accept: String = "application/json") throws(JiraError) -> URLRequest {
        guard var components = URLComponents(
            url: configuration.siteURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw .invalidSite }

        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw .invalidSite }

        var request = URLRequest(url: url)
        request.setValue(configuration.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    private func perform(_ request: URLRequest) async throws(JiraError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw .network("Unexpected response") }
        switch http.statusCode {
        case 200 ..< 300:
            return data
        case 401, 403:
            throw .unauthorized
        default:
            throw .http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    private func encode(_ body: [String: [String: String]]) throws(JiraError) -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw .decoding(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(JiraError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .decoding(error.localizedDescription)
        }
    }

    /// Jira scatters failure detail across `errorMessages` and a field-keyed `errors`
    /// object — transition validators often fill only the latter, leaving `errorMessages`
    /// empty. Both are read so a refusal always carries its reason.
    private static func errorMessage(from data: Data) -> String {
        struct Payload: Decodable {
            let errorMessages: [String]?
            let errors: [String: String]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return "" }
        if let first = payload.errorMessages?.first(where: { $0.isEmpty.not }) {
            return first
        }
        if let errors = payload.errors, errors.isEmpty.not {
            return errors.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
        }
        return ""
    }
}
