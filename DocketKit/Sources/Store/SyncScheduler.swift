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
    /// Passes queued but not yet begun — by construction never more than one.
    private var waiting = 0
    /// What the waiting pass will run. A forced request that arrives while one is still
    /// waiting replaces this instead of queuing another pass: two views reacting to the
    /// same change cost one fetch, and it is the newest request that runs.
    private var queuedWork: (@MainActor () async -> Void)?
    private var current: Task<Void, Never>?

    public init() {}

    public func schedule(force: Bool, _ work: @escaping @MainActor () async -> Void) {
        if force == false, isBusy { return }
        if force, waiting > 0 {
            queuedWork = work
            return
        }

        let previous = current
        pending += 1
        waiting += 1
        isBusy = true
        queuedWork = work
        current = Task { [weak self] in
            // Cancelling is not enough: the pass unwinds asynchronously, and starting before
            // it does would run two passes over the same store.
            previous?.cancel()
            await previous?.value

            guard let self else { return }
            waiting -= 1
            let work = queuedWork
            queuedWork = nil
            defer {
                pending -= 1
                isBusy = pending > 0
            }
            guard Task.isCancelled == false else { return }
            await work?()
        }
    }

    public func cancel() {
        current?.cancel()
        current = nil
        pending = 0
        waiting = 0
        queuedWork = nil
        isBusy = false
    }
}
