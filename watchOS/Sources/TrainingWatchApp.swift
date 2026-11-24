import SwiftUI
import TrainingCore
import TrainingWatchKit

@main
struct TrainingWatchApp: App {
    @State private var recorder = RunRecorder(backend: WatchRunBackend())
    @State private var zoneStore = WatchZoneStore()
    @State private var planStore = WatchPlanStore()
    /// Receives the athlete's zones and plan from the iPhone (WATCH-102, WATCH-103).
    @State private var syncChannel = WatchSyncChannel.live()

    var body: some Scene {
        WindowGroup {
            RunView(recorder: recorder, zoneStore: zoneStore, planStore: planStore)
                .task {
                    recorder.zoneStore = zoneStore
                    syncChannel?.activate(onReceive: { context in
                        // A part the phone hasn't sent yet is `nil`: keep what the watch has.
                        // In the simulator, test data wins over anything a paired phone sends.
                        if let zones = context.zones, !SimulatorTestData.replacesZones { zoneStore.update(zones) }
                        if let plan = context.plan, !SimulatorTestData.replacesPlan { planStore.update(plan) }
                        context.cues?.save()
                    }, onPreview: { plan in
                        // The phone's "Feel on Watch" (WATCH-117); not in a run, where it could cut
                        // a real cue's repeated taps.
                        switch recorder.phase {
                        case .running, .paused, .starting, .saving: return
                        default: CueHaptics.play(plan)
                        }
                    })
                    #if targetEnvironment(simulator)
                    SimulatorTestData.apply(zoneStore: zoneStore, planStore: planStore)
                    #endif
                }
        }
    }
}
