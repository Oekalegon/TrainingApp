import SwiftUI

/// Apple Health (MVP2-123, MVP2-126, design doc §2.3): what the app reads from Health and the two ways
/// to import it. HealthKit doesn't say whether read access was granted (only whether the prompt was
/// shown), so this can't show which data types are allowed: it offers "Connect Apple Health" while
/// nothing has ever been imported, and "Import Now" always.
struct AppleHealthView: View {
    let isRefreshing: Bool
    let hasNoActivities: Bool
    let onImport: () -> Void
    let onConnect: () -> Void

    var body: some View {
        List {
            Section {
                if hasNoActivities {
                    Button(action: onConnect) {
                        actionLabel("Connect Apple Health")
                    }
                    .disabled(isRefreshing)
                }
                Button(action: onImport) {
                    actionLabel("Import Now")
                }
                .disabled(isRefreshing)
            } footer: {
                Text("TrainingApp reads your workouts, heart rate, resting heart rate, sex and date of birth from Apple Health to work out your training load and fitness. It never writes to Health. New workouts are imported automatically.")
            }
        }
        .navigationTitle(AthleteRoute.appleHealth.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func actionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
            if isRefreshing {
                Spacer()
                ProgressView()
            }
        }
    }
}
