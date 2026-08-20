//  Clock.swift
//  Docket

import AppKit
import Observation

/// Makes the passage of time observable.
///
/// `Date()` read inside a view body is invisible to SwiftUI, so "3분 전" and "D-3" froze at
/// whatever they were when the row was last drawn — which, for a list row, is when its
/// ticket last changed. Views read `now` from here instead, and a tick redraws them.
@MainActor
@Observable
final class Clock {
    /// A minute is the finest granularity anything on screen shows.
    static let interval: TimeInterval = 60

    private(set) var now = Date()
    private var task: Task<Void, Never>?

    init() {
        start()
        // Sleeping through midnight would otherwise leave every date stale until the next
        // tick, and waking is exactly when the user looks.
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
    }

    private func start() {
        task = Task { [weak self] in
            while Task.isCancelled.not {
                try? await Task.sleep(for: .seconds(Self.interval))
                self?.now = Date()
            }
        }
    }
}

private extension Bool {
    var not: Bool { self == false }
}
