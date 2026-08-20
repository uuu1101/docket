//  PullRequestMatcher.swift
//  DocketKit

import Foundation

/// Decides which pull requests belong to which ticket.
public enum PullRequestMatcher {
    /// A ticket key counts as mentioned when it appears in the title or the branch name.
    ///
    /// The match is bounded so `APP-2913` does not claim `APP-29133`, and case is ignored
    /// because branches are often lowercased.
    public static func mentions(issueKey: String, in text: String) -> Bool {
        guard issueKey.isEmpty.not, text.isEmpty.not else { return false }
        let pattern = "(?<![A-Za-z0-9])\(NSRegularExpression.escapedPattern(for: issueKey))(?![0-9])"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }

    public static func links(for issueKey: String, in pullRequests: [GitHubPullRequest]) -> [PullRequestLink] {
        pullRequests
            .filter { mentions(issueKey: issueKey, in: $0.title) || mentions(issueKey: issueKey, in: $0.headRef) }
            .map(\.asLink)
    }
}
