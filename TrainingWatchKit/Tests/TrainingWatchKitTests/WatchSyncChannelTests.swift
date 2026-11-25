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
    var reachable = false
    var previews: [[String: Any]] = []
    var contexts: [[String: Any]] = []

    func activate() { activateCalls += 1 }

    func updateContext(_ context: [String: Any]) throws {
        if failing { throw Failure() }
        contexts.append(context)
    }

    func sendPreview(_ message: [String: Any]) -> Bool {
        guard reachable else { return false }
        previews.append(message)
        return true
    }

    var sent: [WatchContext] { contexts.compactMap { WatchContext(applicationContext: $0) } }
}

@MainActor
@Suite("WatchSyncChannel (WATCH-102, WATCH-103)")
struct WatchSyncChannelTests {
    @Test("a haptic preview reaches the watch's closure, and is refused when the watch isn't reachable (WATCH-117)")
    func hapticPreview() {
        let phoneSession = FakeSession()
        let phone = WatchSyncChannel(session: phoneSession)
        #expect(!phone.preview(haptic: HapticPlan(.success)))
        phoneSession.reachable = true
        #expect(phone.preview(haptic: HapticPlan(.directionUp, taps: 2)))

        var played: [HapticPlan] = []
        let watch = WatchSyncChannel(session: FakeSession())
        watch.activate(onPreview: { played.append($0) })
        watch.receivedPreview(phoneSession.previews[0])
        watch.receivedPreview(["previewHaptic": "buzzSaw"])
        watch.receivedPreview(["previewHaptic": "click", "previewTaps": 99])
        #expect(played == [HapticPlan(.directionUp, taps: 2), HapticPlan(.click, taps: 3)])
    }

    @Test("tone samples cover each note and a short pause, and stay within range (WATCH-117)")
    func toneSamples() {
        let samples = ToneNote.samples([ToneNote(440, 0.1), ToneNote(660, 0.2)])
        let expected = Int(0.1 * ToneNote.sampleRate) + Int(0.2 * ToneNote.sampleRate) + 2 * Int(0.05 * ToneNote.sampleRate)
        #expect(samples.count == expected)
        #expect(samples.allSatisfy { abs($0) <= 0.5 })
        #expect(samples.contains { abs($0) > 0.3 })
    }

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

    @Test("the run screens go out in the same context as the zones (WATCH-109)")
    func screensWithZones() throws {
        let session = FakeSession()
        ready(session)
        let channel = WatchSyncChannel(session: session)
        try channel.send(zones: zones())
        try channel.send(screens: .default)
        #expect(session.sent.last == WatchContext(zones: zones(), screens: .default))
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
