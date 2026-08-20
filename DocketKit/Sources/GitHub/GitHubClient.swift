//  GitHubClient.swift
//  DocketKit

import Foundation

public enum GitHubError: Error, Sendable, Equatable {
    case notConfigured
    case unauthorized
    case notFound(String)
    case rateLimited
    case http(status: Int)
    case network(String)
    case decoding(String)
}

/// A pull request linked to a ticket.
public struct PullRequestLink: Sendable, Equatable, Codable {
    /// What the button says — "#1396".
    public let name: String
    public let title: String
    public let urlString: String

    public init(name: String, title: String, urlString: String) {
        self.name = name
        self.title = title
        self.urlString = urlString
    }

    public var url: URL? { URL(string: urlString) }
}

/// One pull request as GitHub lists it, before it is matched to a ticket.
public struct GitHubPullRequest: Sendable, Equatable {
    public let number: Int
    public let title: String
    public let urlString: String
    /// The source branch. Ticket keys live here even when the title omits them.
    public let headRef: String

    public init(number: Int, title: String, urlString: String, headRef: String) {
        self.number = number
        self.title = title
        self.urlString = urlString
        self.headRef = headRef
    }

    public var asLink: PullRequestLink {
        PullRequestLink(name: "#\(number)", title: title, urlString: urlString)
    }
}

public protocol GitHubAPI: Sendable {
    /// The most recently updated pull requests in a repository, newest first.
    func recentPullRequests(repository: String) async throws(GitHubError) -> [GitHubPullRequest]
    /// Confirms the token works and says who it belongs to.
    func login() async throws(GitHubError) -> String
}

public struct GitHubConfiguration: Sendable, Equatable {
    public let token: String
    /// `owner/repo` entries. Listing repositories rather than searching an organisation
    /// keeps the token down to read-only access on exactly these.
    public let repositories: [String]

    public init?(token: String, repositories: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Self.parse(repositories)
        guard token.isEmpty.not, parsed.isEmpty.not else { return nil }
        self.token = token
        self.repositories = parsed
    }

    /// Accepts commas, newlines or spaces, and tolerates a pasted GitHub URL.
    static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { entry -> String in
                var text = String(entry).trimmingCharacters(in: .whitespacesAndNewlines)
                if let range = text.range(of: "github.com/") { text = String(text[range.upperBound...]) }
                while text.hasSuffix("/") || text.hasSuffix(".git") {
                    text = text.hasSuffix(".git") ? String(text.dropLast(4)) : String(text.dropLast())
                }
                return text
            }
            .filter { $0.split(separator: "/").count == 2 }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}

public struct LiveGitHubAPI: GitHubAPI {
    /// Two pages of the most recently updated pull requests. Enough to cover the work a
    /// dashboard cares about without paging through a repository's whole history.
    static let pageCount = 2
    static let pageSize = 100

    private let configuration: GitHubConfiguration
    private let session: URLSession

    public init(configuration: GitHubConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func login() async throws(GitHubError) -> String {
        let data = try await get(path: "/user", query: [])
        struct Payload: Decodable { let login: String? }
        return try decode(Payload.self, from: data).login ?? ""
    }

    public func recentPullRequests(repository: String) async throws(GitHubError) -> [GitHubPullRequest] {
        var collected: [GitHubPullRequest] = []

        for page in 1 ... Self.pageCount {
            let data = try await get(
                path: "/repos/\(repository)/pulls",
                query: [
                    URLQueryItem(name: "state", value: "all"),
                    URLQueryItem(name: "sort", value: "updated"),
                    URLQueryItem(name: "direction", value: "desc"),
                    URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                    URLQueryItem(name: "page", value: String(page)),
                ]
            )
            let batch = try decode([PullRequestRemoteModel].self, from: data).compactMap(\.asEntity)
            collected += batch
            // A short page is the last page.
            if batch.count < Self.pageSize { break }
        }

        return collected
    }

    // MARK: - Transport

    private func get(path: String, query: [URLQueryItem]) async throws(GitHubError) -> Data {
        var components = URLComponents(string: "https://api.github.com\(path)")
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw .network("Invalid endpoint") }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw .network("Unexpected response") }
        switch http.statusCode {
        case 200 ..< 300: return data
        case 401: throw .unauthorized
        case 404: throw .notFound(path)
        case 403, 429: throw .rateLimited
        default: throw .http(status: http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(GitHubError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .decoding(error.localizedDescription)
        }
    }
}

// MARK: - Wire format

struct PullRequestRemoteModel: Decodable {
    let number: Int?
    let title: String?
    let htmlURL: String?
    let head: Head?

    struct Head: Decodable {
        let ref: String?
    }

    enum CodingKeys: String, CodingKey {
        case number, title, head
        case htmlURL = "html_url"
    }

    var asEntity: GitHubPullRequest? {
        guard let number, let htmlURL, htmlURL.isEmpty.not else { return nil }
        return GitHubPullRequest(
            number: number,
            title: title ?? "",
            urlString: htmlURL,
            headRef: head?.ref ?? ""
        )
    }
}
