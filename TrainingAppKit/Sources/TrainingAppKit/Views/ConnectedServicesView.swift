import SwiftUI

/// Connected Services (MVP2-123, design doc §2.3): Apple Health, and Apple Watch where the device can
/// schedule workouts. One Apple Watch row, not one per paired watch: iOS gives an app no list of
/// paired watches (MVP2-125), and WorkoutKit asks for one permission for whichever watch is active.
struct ConnectedServicesView: View {
    let showsAppleWatch: Bool

    var body: some View {
        List {
            Section {
                AthleteRouteRow(route: .appleHealth)
                if showsAppleWatch {
                    AthleteRouteRow(route: .appleWatch)
                }
            }
        }
        .navigationTitle(AthleteRoute.connectedServices.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
