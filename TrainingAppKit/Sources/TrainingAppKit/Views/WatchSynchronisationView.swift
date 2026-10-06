import SwiftUI

/// Apple Watch ▸ Synchronisation (MVP2-123): hosts ``WatchSchedulingSection``, the switch and the
/// permission for sending planned workouts to the Watch. The week view's ``WatchPermissionBanner``
/// opens this screen (``AthleteRoute/watchSettings``).
struct WatchSynchronisationView: View {
    let sync: WatchScheduleSync

    var body: some View {
        List {
            WatchSchedulingSection(sync: sync)
        }
        .navigationTitle(AthleteRoute.synchronisation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
