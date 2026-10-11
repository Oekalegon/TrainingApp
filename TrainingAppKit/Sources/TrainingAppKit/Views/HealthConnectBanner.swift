import SwiftUI

/// Shown at the bottom of the week view while nothing has been imported from Health but plans exist
/// (MVP2-147): the calendar is showing, so the full "No training data yet" prompt isn't, and this is
/// the way to connect from here. Its button asks for Health access and imports (`WeekViewModel.connectHealthData`).
///
/// Dismissing it hides it for good (``OnboardingViewModel/dismissHealthBanner()``); the Athlete tab's
/// Apple Health row still offers "Connect Apple Health". It goes away on its own once an import has
/// completed.
struct HealthConnectBanner: View {
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        PermissionBanner(
            symbolName: "heart.text.square",
            title: "Connect Health Data",
            message: "Import your workouts from Apple Health to see your training load next to your plans.",
            actionTitle: isConnecting ? "Connecting…" : "Connect Apple Health",
            onAction: { if !isConnecting { onConnect() } },
            dismissLabel: "Dismiss Connect Health Notice",
            onDismiss: onDismiss
        )
    }
}
