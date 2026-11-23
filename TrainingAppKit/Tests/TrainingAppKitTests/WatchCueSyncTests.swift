import Foundation
import Testing
import TrainingWatchKit
@testable import TrainingAppKit

@MainActor
private final class CueSender: WatchSyncSending {
    var cues: [CueSettings] = []
    var lastSendError: String?
    func send(zones: WatchZones) throws {}
    func send(plan: WatchPlan) throws {}
    func send(cues: CueSettings) throws { self.cues.append(cues) }
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
        let changed = CueSettings(haptics: .always, sound: .always, style: .tones)
        sync.update(changed)
        #expect(sender.cues.last == changed && sender.cues.count == 2)
        #expect(WatchCueSync(sender: CueSender(), defaults: store).settings == changed)
    }
}
