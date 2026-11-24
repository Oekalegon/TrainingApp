import SwiftUI

/// Apple Watch (MVP2-123, design doc §2.3): Synchronisation, which holds the switch and the
/// permission for sending planned workouts (MVP2-117, MVP2-118), and Alerts During a Run, how the
/// watch tells the athlete things with sound and haptics (WATCH-107).
struct AppleWatchView: View {
    /// Whether the settings for the watch's alerts (WATCH-107) can be shown.
    let showsAlerts: Bool

    var body: some View {
        List {
            Section {
                AthleteRouteRow(route: .synchronisation)
                if showsAlerts {
                    AthleteRouteRow(route: .watchAlerts)
                }
            }
        }
        .navigationTitle(AthleteRoute.appleWatch.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
