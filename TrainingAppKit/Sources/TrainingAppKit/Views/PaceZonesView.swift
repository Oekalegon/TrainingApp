import SwiftUI

/// Pace Zones (MVP2-123, design doc §2.3): the threshold pace. The zones themselves aren't built
/// yet (MVP8), so the screen says so rather than leaving a gap.
struct PaceZonesView: View {
    let viewModel: AthleteViewModel

    var body: some View {
        List {
            Section {
                LabeledContent("Threshold Pace", value: viewModel.thresholdPaceText)
            } footer: {
                Text("Pace zones aren't available yet.")
            }
        }
        .navigationTitle(AthleteRoute.paceZones.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
