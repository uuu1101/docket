//  StatusCategory.swift
//  DocketKit

import Foundation

/// Jira groups every workflow status into one of three categories.
/// Status *names* vary per project, so ordering and colors key off the category.
public enum StatusCategory: String, Sendable, Codable, CaseIterable {
    case todo
    case inProgress
    case done

    /// Maps Jira's `statusCategory.key` (`new` / `indeterminate` / `done`).
    public init(jiraKey: String) {
        switch jiraKey {
        case "done": self = .done
        case "indeterminate": self = .inProgress
        default: self = .todo
        }
    }

    /// Statuses a project files under Done while the work is still in flight. Jira's own
    /// category is wrong for these, and they belong with the rest of the active work.
    public static let inProgressOverrides: Set<String> = ["ready for qa"]

    /// The category to use, after the overrides have their say.
    public static func resolved(jiraKey: String, statusName: String) -> StatusCategory {
        let name = statusName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if inProgressOverrides.contains(name) { return .inProgress }
        return StatusCategory(jiraKey: jiraKey)
    }

    /// In Review sits closest to the finish line, so in-progress work sorts above to-do.
    public var sortWeight: Int {
        switch self {
        case .inProgress: 0
        case .todo: 1
        case .done: 2
        }
    }
}
