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

    var sentZones: [WatchZones] { contexts.compactMap { WatchZones(applicationContext: $0) } }
}

@MainActor
@Suite("WatchZoneChannel (WATCH-102)")
struct WatchZoneChannelTests {
    private func zones(max: Double = 190) -> WatchZones {
        WatchZones(settings: HeartRateZoneSettings(
            effectiveDate: Date(timeIntervalSince1970: 0), restingHeartRateBPM: 50, maxHeartRateBPM: max))
    }

    private func ready(_ session: FakeSession) {
        session.isActivated = true
        session.canReceiveContext = true
    }

    @Test("activating starts the session")
    func activates() {
        let session = FakeSession()
        WatchZoneChannel(session: session).activate()
        #expect(session.activateCalls == 1)
    }

    @Test("zones sent before the session is active go out once it activates")
    func heldUntilActivated() throws {
        let session = FakeSession()
        session.canReceiveContext = true
        let channel = WatchZoneChannel(session: session)
        try channel.send(zones())
        #expect(session.contexts.isEmpty)
        session.isActivated = true
        channel.sessionActivated(receivedData: nil)
        #expect(session.sentZones == [zones()])
    }

    @Test("zones sent while no watch has the app go out once one does")
    func heldUntilWatchAppInstalled() throws {
        let session = FakeSession()
        session.isActivated = true
        let channel = WatchZoneChannel(session: session)
        try channel.send(zones())
        #expect(session.contexts.isEmpty)
        session.canReceiveContext = true
        channel.watchStateChanged()
        #expect(session.sentZones == [zones()])
    }

    @Test("a watch added after the zones were sent gets them again, in the same session")
    func resentForANewWatch() throws {
        let session = FakeSession()
        ready(session)
        let channel = WatchZoneChannel(session: session)
        try channel.send(zones())
        #expect(session.contexts.count == 1)
        channel.watchStateChanged()
        #expect(session.sentZones == [zones(), zones()])
    }

    @Test("a state change before any zones were sent sends nothing")
    func nothingToResend() {
        let session = FakeSession()
        ready(session)
        WatchZoneChannel(session: session).watchStateChanged()
        #expect(session.contexts.isEmpty)
    }

    @Test("newer zones replace older ones that were still waiting")
    func newerReplacesWaiting() throws {
        let session = FakeSession()
        let channel = WatchZoneChannel(session: session)
        try channel.send(zones(max: 190))
        try channel.send(zones(max: 185))
        ready(session)
        channel.sessionActivated(receivedData: nil)
        #expect(session.sentZones == [zones(max: 185)])
    }

    @Test("a failed hand-over is reported, kept and tried again at the next state change")
    func failureIsReportedAndRetried() throws {
        let session = FakeSession()
        ready(session)
        session.failing = true
        let channel = WatchZoneChannel(session: session)
        try channel.send(zones())
        #expect(channel.lastSendError != nil)
        #expect(session.contexts.isEmpty)

        session.failing = false
        channel.watchStateChanged()
        #expect(channel.lastSendError == nil)
        #expect(session.sentZones == [zones()])
    }

    @Test("the watch passes on zones it received, including the context waiting at activation")
    func receiving() throws {
        let session = FakeSession()
        let channel = WatchZoneChannel(session: session)
        var received: [WatchZones] = []
        channel.activate { received.append($0) }
        channel.received(data: try JSONEncoder().encode(zones(max: 185)))
        session.isActivated = true
        channel.sessionActivated(receivedData: try JSONEncoder().encode(zones(max: 190)))
        #expect(received == [zones(max: 185), zones(max: 190)])
    }

    @Test("unreadable data is ignored")
    func unreadableData() {
        let channel = WatchZoneChannel(session: FakeSession())
        var received: [WatchZones] = []
        channel.activate { received.append($0) }
        channel.received(data: Data("not json".utf8))
        #expect(received.isEmpty)
    }
}
