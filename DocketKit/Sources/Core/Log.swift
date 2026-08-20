//  Log.swift
//  DocketKit

import OSLog

/// The app's log. A menu bar app has no console, so anything worth diagnosing has to go to
/// the unified log where `log show --predicate 'subsystem == "dev.taetae.docket"'` finds it.
public enum Log {
    public static let slack = Logger(subsystem: "dev.taetae.docket", category: "slack")
    public static let jira = Logger(subsystem: "dev.taetae.docket", category: "jira")
    public static let github = Logger(subsystem: "dev.taetae.docket", category: "github")
    public static let store = Logger(subsystem: "dev.taetae.docket", category: "store")
}
