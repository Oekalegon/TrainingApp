import SwiftUI

/// Inline prompt shown instead of the chart/day list when `TrainingModel` has no activities yet
/// (first launch, before HealthKit authorization/initial sync) — design doc §2.1. MVP 1 has no
/// dedicated onboarding screen; this is the whole first-run experience.
struct EmptyStateView: View {
    let isConnecting: Bool
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No training data yet")
                .font(.headline)
            Text("Connect Health data to import your workouts and see your training load.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: connect) {
                if isConnecting {
                    ProgressView()
                } else {
                    Text("Connect Health Data")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
