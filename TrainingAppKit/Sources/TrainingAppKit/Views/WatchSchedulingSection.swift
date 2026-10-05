import SwiftUI

/// The Athlete tab's Apple Watch section (MVP2-117, MVP2-118): a "Send Planned Workouts to Apple
/// Watch" switch, whether the app may put planned workouts on the Watch, an Allow button while the
/// athlete hasn't been asked, and where to turn it back on once declined. The week view's
/// ``WatchPermissionBanner`` opens the Athlete tab to show this.
///
/// The switch is the app's own setting (``WatchScheduleSync/isEnabled``) and works on top of iOS's
/// permission: turning it off removes the app's workouts from the Watch without touching the
/// permission. iOS asks only once, so for a declined permission this can only point to the Watch
/// app's Workout settings; neither the switch nor ``WatchScheduleSync/requestPermission(asOf:)``
/// shows the prompt again. On a device that can't schedule workouts, only the status shows.
///
/// Reads the permission when it appears, so it's current before any sync has run; the sync that
/// runs when the app becomes active updates it after a change in the Watch app.
struct WatchSchedulingSection: View {
    let sync: WatchScheduleSync
    /// Whether the permission prompt is up, so a second tap can't ask again.
    @State private var isRequesting = false

    var body: some View {
        Section {
            if sync.authorization != .unavailable {
                Toggle(
                    "Send Planned Workouts to Apple Watch",
                    isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) })
                )
            }
            LabeledContent("Watch Permission", value: sync.authorization?.statusText ?? "Checking…")
            if sync.isEnabled, sync.authorization == .notDetermined {
                Button {
                    isRequesting = true
                    Task {
                        await sync.requestPermission()
                        isRequesting = false
                    }
                } label: {
                    HStack {
                        Text("Allow Sending to Apple Watch")
                        if isRequesting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRequesting)
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            if let authorization = sync.authorization {
                Text(authorization.explanation(isEnabled: sync.isEnabled))
            }
        }
        .task {
            await sync.refreshAuthorization()
        }
    }
}
