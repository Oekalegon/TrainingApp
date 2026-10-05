import SwiftUI

/// Shown at the bottom of the week view when the athlete declined permission to schedule workouts
/// (MVP2-117): planned workouts won't reach the Watch until it's allowed again. The same kind of
/// dismissible banner the TrainingKit roadmap describes for revoked HealthKit access.
///
/// Yellow with black content in both light and dark mode, so it stands out from the grey week
/// background behind it. Its button opens the Athlete tab, whose Apple Watch section
/// (``WatchSchedulingSection``) shows the permission and where to turn it back on.
///
/// Dismissing it hides it until permission is granted and later declined again (see
/// ``WatchScheduleSync/showsPermissionDeniedBanner``). Allowing it hides it on its own: the sync
/// that runs when the app becomes active again sees the new permission.
struct WatchPermissionBanner: View {
    let onShowWatchSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "applewatch.slash")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Planned workouts won't reach your Apple Watch")
                    .font(.subheadline.weight(.semibold))
                Text("This app isn't allowed to schedule workouts, so planned workouts won't be ready in the Workout app on the day they're due.")
                    .font(.footnote)
                    .foregroundStyle(.black.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Athlete Tab", action: onShowWatchSettings)
                    .font(.footnote.weight(.semibold))
                    .underline()
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            // A 44 pt hit area around the small glyph, pulled into the banner's padding so the
            // banner doesn't grow to fit it.
            Button("Dismiss Watch Permission Notice", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.black.opacity(0.6))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .padding(.top, -12)
                .padding(.trailing, -12)
        }
        .foregroundStyle(.black)
        .padding()
        .background(.yellow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
