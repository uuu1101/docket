//  TicketQuery.swift
//  DocketKit

import Foundation

/// Which tickets the dashboard shows.
///
/// Presets cover the cases worth a menu entry; `custom` hands the user the raw JQL for
/// everything else.
public enum TicketQuery: String, Sendable, Codable, CaseIterable, Identifiable {
    case assignedOpen
    case assignedOpenOrRecentlyDone
    case reportedOpen
    case watching
    case custom

    public static let `default` = TicketQuery.assignedOpen

    /// Used when a custom query is blank, so the dashboard never sends an empty JQL.
    public static let fallbackJQL = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"

    public var id: String { rawValue }

    /// The JQL this preset stands for, or `nil` for `custom`, which carries its own text.
    public var jql: String? {
        switch self {
        case .assignedOpen:
            Self.fallbackJQL
        case .assignedOpenOrRecentlyDone:
            "assignee = currentUser() AND (statusCategory != Done OR resolutiondate >= -7d) ORDER BY updated DESC"
        case .reportedOpen:
            "reporter = currentUser() AND statusCategory != Done ORDER BY updated DESC"
        case .watching:
            "watcher = currentUser() AND statusCategory != Done ORDER BY updated DESC"
        case .custom:
            nil
        }
    }
}
