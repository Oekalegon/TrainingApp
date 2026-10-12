import SwiftUI

/// Shown at the bottom of the week view when Health is connected but the athlete was never asked to
/// allow distance (MVP2-146): an install that connected before the app began reading it. Allowing it
/// gives every step of a plan-started workout its distance and pace, and the button re-reads the
/// workouts once so earlier ones get their steps too.
///
/// Dismissing it hides it for good (``OnboardingViewModel/dismissDistanceBanner()``). It goes away on
/// its own once the athlete has answered the Health sheet, allowing or not.
struct HealthDistanceBanner: View {
    let isUpdating: Bool
    let onAllow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        PermissionBanner(
            symbolName: "figure.run",
            title: "Allow distance to see each step's pace",
            message: "TrainingApp can show the distance and pace of every step of a planned workout once Health allows it. Your workouts are read again once.",
            actionTitle: isUpdating ? "Updating…" : "Allow Distance",
            onAction: onAllow,
            isActionEnabled: !isUpdating,
            dismissLabel: "Dismiss Allow Distance Notice",
            onDismiss: onDismiss
        )
    }
}
