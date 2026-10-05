import SwiftUI

/// The Athlete tab's Apple Watch section (MVP2-117): whether the app may put planned workouts on
/// the Watch, an Allow button while the athlete hasn't been asked, and where to turn it back on
/// once declined. The week view's ``WatchPermissionBanner`` opens the Athlete tab to show this.
///
/// iOS asks only once, so for a declined permission this can only point to the Watch app's
/// Workout settings; ``WatchScheduleSync/requestPermission(asOf:)`` wouldn't show the prompt again.
/// Reads the permission when it appears, so it's current before any sync has run; the sync that
/// runs when the app becomes active updates it after a change in the Watch app.
struct WatchSchedulingSection: View {
    let sync: WatchScheduleSync
    /// Whether the permission prompt is up, so a second tap can't ask again.
    @State private var isRequesting = false

    var body: some View {
        Section {
            LabeledContent("Planned Workouts", value: sync.authorization?.statusText ?? "Checking…")
            if sync.authorization == .notDetermined {
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
                Text(authorization.explanation)
            }
        }
        .task {
            await sync.refreshAuthorization()
        }
    }
}
