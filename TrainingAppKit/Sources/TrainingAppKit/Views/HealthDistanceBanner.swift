import SwiftUI

/// Shown at the bottom of the week view when Health is connected but the athlete was never asked to
/// allow distance and speed (MVP2-146): an install that connected before the app began reading them.
/// Allowing them gives every step of a plan-started workout its distance and pace and every workout a
/// pace chart, and the button re-reads the workouts once so earlier ones get them too.
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
            title: "Allow distance and speed for pace",
            message: "TrainingApp can show each step's distance and pace, and a pace chart for your workouts, once Health allows distance and speed. Your workouts are read again once.",
            actionTitle: isUpdating ? "Updating…" : "Allow Distance",
            onAction: onAllow,
            isActionEnabled: !isUpdating,
            dismissLabel: "Dismiss Allow Distance Notice",
            onDismiss: onDismiss
        )
    }
}
