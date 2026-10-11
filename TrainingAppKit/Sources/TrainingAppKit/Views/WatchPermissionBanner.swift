import SwiftUI

/// Shown at the bottom of the week view when the athlete declined permission to schedule workouts
/// (MVP2-117): planned workouts won't reach the Watch until it's allowed again. The same kind of
/// dismissible banner as ``HealthConnectBanner`` and ``ICloudUnavailableBanner`` (MVP2-147): a
/// ``PermissionBanner``.
///
/// Its button opens the Athlete tab's Apple Watch ▸ Synchronisation screen, whose section
/// (``WatchSchedulingSection``) shows the permission and where to turn it back on.
///
/// Dismissing it hides it until permission is granted and later declined again (see
/// ``WatchScheduleSync/showsPermissionDeniedBanner``). Allowing it hides it on its own: the sync
/// that runs when the app becomes active again sees the new permission.
struct WatchPermissionBanner: View {
    let onShowWatchSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        PermissionBanner(
            symbolName: "applewatch.slash",
            title: "Planned workouts won't reach your Apple Watch",
            message: "This app isn't allowed to schedule workouts, so planned workouts won't be ready in the Workout app on the day they're due.",
            actionTitle: "Open Watch Settings",
            onAction: onShowWatchSettings,
            dismissLabel: "Dismiss Watch Permission Notice",
            onDismiss: onDismiss
        )
    }
}
