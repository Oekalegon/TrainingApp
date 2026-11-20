import Foundation
import Testing
import TrainingCore
@testable import TrainingWatchKit

@MainActor
private final class FakeSession: WatchSessionControlling {
    struct Failure: Error {}
    var isActivated = false
    var canReceiveContext = false
    var failing = false
    var activateCalls = 0
    var contexts: [[String: Any]] = []

    func activate() { activateCalls += 1 }

    func updateContext(_ context: [String: Any]) throws {
        if failing { throw Failure() }
        contexts.append(context)
    }

    var sent: [WatchContext] { contexts.compactMap { WatchContext(applicationContext: $0) } }
}

@MainActor
@Suite("WatchSyncChannel (WATCH-102, WATCH-103)")
struct WatchSyncChannelTests {
    private func zones(max: Double = 190) -> WatchZones {
        WatchZones(settings: HeartRateZoneSettings(
            effectiveDate: Date(timeIntervalSince1970: 0), restingHeartRateBPM: 50, maxHeartRateBPM: max))
    }

    private func plan(_ name: String = "Steady") -> WatchPlan {
        WatchPlan(
            workouts: [WatchPlannedWorkout(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: Date(timeIntervalSince1970: 1_700_000_000),
                name: name, blocks: [])],
            sentAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func ready(_ session: FakeSession) {
        session.isActivated = true
        session.canReceiveContext = true
    }

    @Test("activating starts the session")
    func activates() {
        let session = FakeSession()
        WatchSyncChannel(session: session).activate()
        #expect(session.activateCalls == 1)
    }

    @Test("zones sent before the session is active go out once it activates")
    func heldUntilActivated() throws {
        let session = FakeSession()
        session.canReceiveContext = true
        let channel = WatchSyncChannel(session: session)
        try channel.send(zones: zones())
        #expect(session.contexts.isEmpty)
        session.isActivated = true
        channel.sessionActivated(receivedData: nil)
        #expect(session.sent == [WatchContext(zones: zones())])
    }

    @Test("a send while no watch has the app goes out once one does")
    func heldUntilWatchAppInstalled() throws {
        let session = FakeSession()
        session.isActivated = true
        let channel = WatchSyncChannel(session: session)
        try channel.send(plan: plan())
        #expect(session.contexts.isEmpty)
        session.canReceiveContext = true
        channel.watchStateChanged()
        #expect(session.sent == [WatchContext(plan: plan())])
    }

    @Test("the plan and the zones go out as one context, so neither wipes out the other")
    func zonesAndPlanTogether() throws {
        let session = FakeSession()
        ready(session)
        let channel = WatchSyncChannel(session: session)
        try channel.send(zones: zones())
        try channel.send(plan: plan())
        #expect(session.sent.last == WatchContext(zones: zones(), plan: plan()))
        try channel.send(zones: zones(max: 185))
        #expect(session.sent.last == WatchContext(zones: zones(max: 185), plan: plan()))
    }

    @Test("a watch added after the context was sent gets it again, in the same session")
    func resentForANewWatch() throws {
        let session = FakeSession()
        ready(session)
        let channel = WatchSyncChannel(session: session)
        try channel.send(zones: zones())
        #expect(session.contexts.count == 1)
        channel.watchStateChanged()
        #expect(session.sent == [WatchContext(zones: zones()), WatchContext(zones: zones())])
    }

    @Test("a state change before anything was sent sends nothing")
    func nothingToResend() {
        let session = FakeSession()
        ready(session)
        WatchSyncChannel(session: session).watchStateChanged()
        #expect(session.contexts.isEmpty)
    }

    @Test("newer values replace older ones that were still waiting")
    func newerReplacesWaiting() throws {
        let session = FakeSession()
        let channel = WatchSyncChannel(session: session)
        try channel.send(plan: plan("Old"))
        try channel.send(plan: plan("New"))
        ready(session)
        channel.sessionActivated(receivedData: nil)
        #expect(session.sent == [WatchContext(plan: plan("New"))])
    }

    @Test("a failed hand-over is reported, kept and tried again at the next state change")
    func failureIsReportedAndRetried() throws {
        let session = FakeSession()
        ready(session)
        session.failing = true
        let channel = WatchSyncChannel(session: session)
        try channel.send(plan: plan())
        #expect(channel.lastSendError != nil)
        #expect(session.contexts.isEmpty)

        session.failing = false
        channel.watchStateChanged()
        #expect(channel.lastSendError == nil)
        #expect(session.sent == [WatchContext(plan: plan())])
    }

    @Test("the watch passes on what it received, including the context waiting at activation")
    func receiving() throws {
        let session = FakeSession()
        let channel = WatchSyncChannel(session: session)
        var received: [WatchContext] = []
        channel.activate { received.append($0) }
        let first = WatchContext(zones: zones(max: 185))
        let second = WatchContext(zones: zones(), plan: plan())
        channel.received(data: try JSONEncoder().encode(first))
        session.isActivated = true
        channel.sessionActivated(receivedData: try JSONEncoder().encode(second))
        #expect(received == [first, second])
    }

    @Test("unreadable data is ignored")
    func unreadableData() {
        let channel = WatchSyncChannel(session: FakeSession())
        var received: [WatchContext] = []
        channel.activate { received.append($0) }
        channel.received(data: Data("not json".utf8))
        #expect(received.isEmpty)
    }
}
