import SwiftUI

/// Shown at the bottom of the week view when there is no usable iCloud account (MVP2-147): plans,
/// templates, races and goals stay on this device and don't sync. Workouts from Health never go to
/// iCloud in any case (the local-only store), so they are not mentioned. Everything still works.
///
/// Its button opens the system Settings app. Dismissing it hides it until iCloud has worked again
/// and fails once more (``OnboardingViewModel/refreshICloudStatus()``).
struct ICloudUnavailableBanner: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        PermissionBanner(
            symbolName: "icloud.slash",
            title: "iCloud isn't available",
            message: "Your plans, templates and races stay on this device and won't sync to your other devices until you sign in to iCloud.",
            actionTitle: "Open Settings",
            onAction: onOpenSettings,
            dismissLabel: "Dismiss iCloud Notice",
            onDismiss: onDismiss
        )
    }
}
