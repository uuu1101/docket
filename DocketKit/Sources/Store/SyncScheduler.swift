//  SyncScheduler.swift
//  DocketKit

import Foundation
import Observation

/// Serializes refresh passes so a request is never silently dropped.
///
/// Two things ask for a refresh: the user, by changing what the dashboard shows or pressing
/// the button, and the periodic tick. A user's request must land even while a pass is running
/// — otherwise choosing a different query does nothing until the next tick — so it cancels
/// that pass and waits for it to unwind before starting its own. A tick has nothing to add
/// while a pass is already running, so it is skipped instead.
@MainActor
@Observable
public final class SyncScheduler {
    /// A pass is running or queued.
    public private(set) var isBusy = false

    private var pending = 0
    private var current: Task<Void, Never>?

    public init() {}

    public func schedule(force: Bool, _ work: @escaping @MainActor () async -> Void) {
        if force == false, isBusy { return }

        let previous = current
        pending += 1
        isBusy = true
        current = Task { [weak self] in
            // Cancelling is not enough: the pass unwinds asynchronously, and starting before
            // it does would run two passes over the same store.
            previous?.cancel()
            await previous?.value

            defer {
                if let self {
                    pending -= 1
                    isBusy = pending > 0
                }
            }
            guard Task.isCancelled == false else { return }
            await work()
        }
    }

    public func cancel() {
        current?.cancel()
        current = nil
        pending = 0
        isBusy = false
    }
}
