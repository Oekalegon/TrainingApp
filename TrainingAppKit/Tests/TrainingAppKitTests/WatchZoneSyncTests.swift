import Foundation
import Testing
import TrainingCore
import TrainingWatchKit
@testable import TrainingAppKit

@MainActor
private final class FakeSender: WatchZoneSending {
    struct Failure: Error {}
    var sent: [WatchZones] = []
    var failing = false
    var lastSendError: String?

    func send(_ zones: WatchZones) throws {
        if failing { throw Failure() }
        sent.append(zones)
    }
}

@MainActor
@Suite("WatchZoneSync (WATCH-102)")
struct WatchZoneSyncTests {
    private func settings(max: Double = 190) -> HeartRateZoneSettings {
        HeartRateZoneSettings(
            effectiveDate: Date(timeIntervalSince1970: 0), restingHeartRateBPM: 50, maxHeartRateBPM: max)
    }

    @Test("the first sync sends the athlete's zones")
    func firstSyncSends() {
        let sender = FakeSender()
        WatchZoneSync(sender: sender).sync(settings: settings())
        #expect(sender.sent == [WatchZones(settings: settings())])
    }

    @Test("syncing unchanged settings again sends nothing more")
    func unchangedIsNotResent() {
        let sender = FakeSender()
        let sync = WatchZoneSync(sender: sender)
        sync.sync(settings: settings())
        sync.sync(settings: settings())
        #expect(sender.sent.count == 1)
    }

    @Test("changed settings are sent again")
    func changedIsResent() {
        let sender = FakeSender()
        let sync = WatchZoneSync(sender: sender)
        sync.sync(settings: settings(max: 190))
        sync.sync(settings: settings(max: 185))
        #expect(sender.sent == [WatchZones(settings: settings(max: 190)), WatchZones(settings: settings(max: 185))])
    }

    @Test("no settings on record sends nothing")
    func noSettings() {
        let sender = FakeSender()
        WatchZoneSync(sender: sender).sync(settings: nil)
        #expect(sender.sent.isEmpty)
    }

    @Test("a transport that refuses the zones is reported, and clears when it works again")
    func transportErrorIsReported() {
        let sender = FakeSender()
        let sync = WatchZoneSync(sender: sender)
        sender.lastSendError = "session not reachable"
        sync.sync(settings: settings())
        #expect(sync.lastError == "session not reachable")
        sender.lastSendError = nil
        #expect(sync.lastError == nil)
    }

    @Test("a failed send is reported and tried again on the next sync")
    func failureIsReportedAndRetried() {
        let sender = FakeSender()
        let sync = WatchZoneSync(sender: sender)
        sender.failing = true
        sync.sync(settings: settings())
        #expect(sync.lastError != nil)
        #expect(sender.sent.isEmpty)

        sender.failing = false
        sync.sync(settings: settings())
        #expect(sync.lastError == nil)
        #expect(sender.sent.count == 1)
    }
}
