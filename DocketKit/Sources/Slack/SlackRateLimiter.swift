//  SlackRateLimiter.swift
//  DocketKit

import Foundation

/// Serializes Slack calls and spaces them out.
///
/// Every request passes through `acquire` before it goes out, and a 429 pushes the gate out
/// by the server's `Retry-After`.
public actor SlackRateLimiter {
    public enum Tier: Sendable {
        case history
        case lookup

        /// Spacing that keeps each endpoint just inside its bucket.
        var interval: TimeInterval {
            switch self {
            case .history: 1.2
            case .lookup: 0.3
            }
        }
    }

    private var readyAt: Date = .distantPast

    public init() {}

    public func acquire(_ tier: Tier) async {
        let now = Date()
        let start = max(now, readyAt)
        readyAt = start.addingTimeInterval(tier.interval)

        let delay = start.timeIntervalSince(now)
        guard delay > 0 else { return }
        try? await Task.sleep(for: .seconds(delay))
    }

    public func backOff(seconds: TimeInterval) {
        readyAt = max(readyAt, Date().addingTimeInterval(seconds))
    }
}
