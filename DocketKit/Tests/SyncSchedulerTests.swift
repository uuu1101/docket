//  SyncSchedulerTests.swift
//  DocketKitTests

import Foundation
import Testing

@testable import DocketKit

@MainActor
@Suite("Scheduling refresh passes")
struct SyncSchedulerTests {
    /// A pass that can be held open, so a second request arrives while the first is running.
    private final class Pass {
        var started = 0
        var finished = 0
        var cancelled = 0

        func run(holding held: Bool) async {
            started += 1
            if held {
                do {
                    // Long enough that the test's own request always lands mid-pass.
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    cancelled += 1
                    return
                }
            }
            finished += 1
        }
    }

    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    @Test("A request the user made runs even though a pass is already running")
    func forcedSupersedes() async {
        let scheduler = SyncScheduler()
        let pass = Pass()

        scheduler.schedule(force: false) { await pass.run(holding: true) }
        await settle()
        #expect(pass.started == 1)
        #expect(scheduler.isBusy)

        scheduler.schedule(force: true) { await pass.run(holding: false) }
        await settle()

        #expect(pass.cancelled == 1, "the running pass should have been cancelled")
        #expect(pass.finished == 1, "the forced pass should have completed")
        #expect(scheduler.isBusy == false)
    }

    @Test("A periodic tick is skipped while a pass is running, rather than queued")
    func tickIsSkipped() async {
        let scheduler = SyncScheduler()
        let pass = Pass()

        scheduler.schedule(force: false) { await pass.run(holding: true) }
        await settle()
        scheduler.schedule(force: false) { await pass.run(holding: false) }
        await settle()

        #expect(pass.started == 1)
        #expect(pass.cancelled == 0, "the running pass must not be disturbed by a tick")
    }

    @Test("A burst of requests collapses to the newest, which always runs")
    func burstCollapses() async {
        let scheduler = SyncScheduler()
        var ran: [Int] = []

        for index in 1 ... 3 {
            scheduler.schedule(force: true) {
                ran.append(index)
                await Task.yield()
            }
        }
        await settle()

        // Choosing three queries quickly is one decision: the middle pass is superseded
        // before it starts, and the newest — the one the user is looking at — runs.
        #expect(ran.last == 3)
        #expect(ran.contains(2) == false)
        #expect(scheduler.isBusy == false)
    }

    @Test("Nothing is left running after a cancel")
    func cancelClears() async {
        let scheduler = SyncScheduler()
        let pass = Pass()

        scheduler.schedule(force: true) { await pass.run(holding: true) }
        await settle()
        scheduler.cancel()
        await settle()

        #expect(pass.cancelled == 1)
        #expect(scheduler.isBusy == false)
    }
}
