import SwiftUI
import TrainingWatchKit

@main
struct TrainingWatchApp: App {
    @State private var recorder = RunRecorder()
    @State private var zoneStore = WatchZoneStore()
    /// Receives the athlete's zones from the iPhone (WATCH-102).
    @State private var zoneChannel = WatchZoneChannel()

    var body: some Scene {
        WindowGroup {
            RunView(recorder: recorder, zoneStore: zoneStore)
                .task {
                    zoneChannel.activate { zoneStore.update($0) }
                    #if targetEnvironment(simulator)
                    // `-fakeZones` gives the simulator zones when no phone has sent any (resting 55,
                    // maximum 190), for testing the zone display.
                    if zoneStore.zones == nil, CommandLine.arguments.contains("-fakeZones") {
                        zoneStore.update(WatchZones(settings: .init(
                            effectiveDate: .distantPast, restingHeartRateBPM: 55, maxHeartRateBPM: 190)))
                    }
                    #endif
                }
        }
    }
}
