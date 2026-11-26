import SwiftUI
import TrainingWatchKit
import WatchKit

/// A run screen on the watch (WATCH-138): the shared ``RunScreenPage`` (also drawn by the iPhone editor's preview),
/// with what only the watch knows: how many units its screen fits, and switching the battery monitoring on.
struct WatchRunScreenPage: View {
    let recorder: RunRecorder
    let screen: RunScreen
    /// Whether this screen says "Workout done" once the steps are used up: one screen does, not each.
    var showsDoneNote = true

    var body: some View {
        RunScreenPage(
            source: recorder, screen: screen,
            fittingUnits: RunScreenPage.fittingUnits(forScreenHeight: WKInterfaceDevice.current().screenBounds.height),
            showsDoneNote: showsDoneNote)
            // The battery level can only be read once monitoring is on; once is enough.
            .onAppear { WKInterfaceDevice.current().isBatteryMonitoringEnabled = true }
    }
}
