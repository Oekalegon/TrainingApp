import SwiftUI

/// Shown at the bottom of the week view when the athlete declined permission to schedule workouts
/// (MVP2-117): planned workouts won't reach the Watch until it's allowed in Settings. The same kind
/// of dismissible banner the TrainingKit roadmap describes for revoked HealthKit access.
///
/// Dismissing it hides it until permission is granted and later declined again (see
/// ``WatchScheduleSync/showsPermissionDeniedBanner``). Allowing it in Settings hides it on its own:
/// the sync that runs when the app becomes active again sees the new permission.
struct WatchPermissionBanner: View {
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "applewatch.slash")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Planned workouts won't reach your Apple Watch")
                    .font(.subheadline.weight(.semibold))
                Text("TrainingApp isn't allowed to schedule workouts. Allow it in Settings to have each planned workout ready in the Workout app on the day it's due.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(iOS)
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") {
                        openURL(settingsURL)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 4)
                }
                #endif
            }
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
