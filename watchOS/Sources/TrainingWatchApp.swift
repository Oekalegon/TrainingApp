import SwiftUI
import TrainingCore
import TrainingWatchKit

@main
struct TrainingWatchApp: App {
    @State private var recorder = RunRecorder(backend: WatchRunBackend(), drainStore: BatteryDrainStore())
    @State private var zoneStore = WatchZoneStore()
    @State private var planStore = WatchPlanStore()
    @State private var screenStore = RunScreenStore()
    /// Receives the athlete's zones and plan from the iPhone (WATCH-102, WATCH-103).
    @State private var syncChannel = WatchSyncChannel.live()

    /// In the simulator, `-fakeElevationScreens` keeps the test screens over what a paired phone sends.
    private static var fakesScreens: Bool {
        #if targetEnvironment(simulator)
        CommandLine.arguments.contains("-fakeElevationScreens")
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RunView(recorder: recorder, planStore: planStore, screenStore: screenStore)
                .task {
                    recorder.zoneStore = zoneStore
                    syncChannel?.activate(onReceive: { context in
                        // A part the phone hasn't sent yet is `nil`: keep what the watch has.
                        // In the simulator, test data wins over anything a paired phone sends.
                        if let zones = context.zones, !SimulatorTestData.replacesZones { zoneStore.update(zones) }
                        if let plan = context.plan, !SimulatorTestData.replacesPlan { planStore.update(plan) }
                        context.cues?.save()
                        if let screens = context.screens, !Self.fakesScreens { screenStore.update(screens) }
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
                    // `-fakeElevationScreens`: a free run with the two elevation graphs, to see them on the watch.
                    if CommandLine.arguments.contains("-fakeElevationScreens") {
                        screenStore.update(RunScreenConfig(freeRun: RunScreenSet(id: "fake.elevation", name: "Free run", screens: [
                            RunScreen(id: "whole", items: [.metric(.totalTime), .metric(.distance), .widget(.elevationProfile)]),
                            RunScreen(id: "recent", items: [.metric(.totalTime), .metric(.altitude), .widget(.elevationRecent)]),
                        ])), persists: false)
                    }
                    #endif
                }
        }
    }
}
