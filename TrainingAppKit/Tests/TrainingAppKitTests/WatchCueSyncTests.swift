import Foundation
import Testing
import TrainingWatchKit
@testable import TrainingAppKit

@MainActor
private final class CueSender: WatchSyncSending {
    struct Failure: Error {}
    var cues: [CueSettings] = []
    var failing = false
    var lastSendError: String?
    func send(zones: WatchZones) throws {}
    func send(plan: WatchPlan) throws {}
    func send(cues: CueSettings) throws {
        if failing { throw Failure() }
        self.cues.append(cues)
    }
}

@MainActor
@Suite("WatchCueSync (WATCH-107)")
struct WatchCueSyncTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "WatchCueSyncTests-\(UUID().uuidString)"))
    }

    @Test("a change is kept and sent at once; an unchanged one is not sent again")
    func changeSent() throws {
        let store = try defaults()
        let sender = CueSender()
        let sync = WatchCueSync(sender: sender, defaults: store)
        sync.sync()
        sync.sync()
        #expect(sender.cues == [CueSettings()])
        var changed = CueSettings(haptics: .always, sound: .always)
        changed[.belowZone] = SignalSound(tone: true, speech: true)
        sync.update(changed)
        #expect(sender.cues.last == changed && sender.cues.count == 2)
        #expect(WatchCueSync(sender: CueSender(), defaults: store).settings == changed)
    }

    @Test("a send that fails is reported and tried again at the next sync")
    func failureRetried() throws {
        let sender = CueSender()
        sender.failing = true
        let sync = WatchCueSync(sender: sender, defaults: try defaults())
        sync.sync()
        #expect(sync.lastError != nil && sender.cues.isEmpty)
        sender.failing = false
        sync.sync()
        #expect(sync.lastError == nil && sender.cues == [CueSettings()])
    }
}
