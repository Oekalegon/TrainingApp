import SwiftUI

/// Apple Watch ▸ Synchronisation (MVP2-123): hosts ``WatchSchedulingSection``, the switch and the
/// permission for sending planned workouts to the Watch. The week view's ``WatchPermissionBanner``
/// opens this screen (``AthleteRoute/watchSettings``).
struct WatchSynchronisationView: View {
    let sync: WatchScheduleSync
    /// How the watch tells the athlete things (WATCH-107); `nil` hides the section.
    let cues: WatchCueSync?

    var body: some View {
        List {
            WatchSchedulingSection(sync: sync)
            if let cues { WatchCueSection(cues: cues) }
        }
        .navigationTitle(AthleteRoute.synchronisation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
