//  RelativeTime.swift
//  DocketKit

import Foundation

/// Formats "3분 전" / "3 minutes ago" in whichever language the UI is set to.
public struct RelativeTime: Sendable {
    private let language: ResolvedLanguage

    public init(language: ResolvedLanguage) {
        self.language = language
    }

    public func string(for date: Date, relativeTo now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.locale
        formatter.unitsStyle = .short
        // Anything under a minute reads better as "just now" than "0 seconds ago".
        if now.timeIntervalSince(date) < 60 {
            return language == .korean ? "방금" : "just now"
        }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
