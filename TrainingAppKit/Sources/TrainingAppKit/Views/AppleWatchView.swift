import SwiftUI

/// Apple Watch (MVP2-123, design doc §2.3): today only Synchronisation, which holds the switch and
/// the permission for sending planned workouts (MVP2-117, MVP2-118).
struct AppleWatchView: View {
    var body: some View {
        List {
            Section {
                AthleteRouteRow(route: .synchronisation)
            }
        }
        .navigationTitle(AthleteRoute.appleWatch.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
