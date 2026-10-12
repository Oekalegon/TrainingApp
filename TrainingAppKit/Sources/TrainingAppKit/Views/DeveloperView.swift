import SwiftUI

/// Developer (MVP2-123, design doc §2.3): the two recovery actions that used to sit at the bottom of
/// the Athlete screen. Force Full Resync re-imports every activity from HealthKit from scratch, for a
/// mapping fix that already-imported activities wouldn't pick up; Deduplicate Activities removes
/// duplicates an older version of the app left behind. Each asks for confirmation first, and neither
/// runs while the other does.
struct DeveloperView: View {
    let isResyncing: Bool
    let onResync: () -> Void
    let isDeduplicating: Bool
    let onDeduplicate: () -> Void
    /// Reads what HealthKit recorded for recent workouts (MVP2-146 spike); `nil` hides the row.
    var workoutInspector: (any WorkoutInspecting)?
    @State private var isConfirmingResync = false
    @State private var isConfirmingDeduplicate = false

    var body: some View {
        List {
            Section {
                Button {
                    isConfirmingResync = true
                } label: {
                    HStack {
                        Text("Force Full Resync")
                        if isResyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isResyncing || isDeduplicating)

                Button {
                    isConfirmingDeduplicate = true
                } label: {
                    HStack {
                        Text("Deduplicate Activities")
                        if isDeduplicating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isResyncing || isDeduplicating)
            } footer: {
                Text("Force Full Resync re-imports every activity from HealthKit from scratch. Use this if an activity's sport or name looks wrong after an app update. Deduplicate Activities removes any duplicate activities left over from an older version of the app.")
            }
            if let workoutInspector {
                Section {
                    NavigationLink("Inspect Recent Workouts") {
                        WorkoutInspectionView(inspector: workoutInspector)
                    }
                } footer: {
                    Text("Lists the events, activities and summaries HealthKit recorded for your recent workouts, and which were started from a plan, to see what the Watch records for each step (MVP2-146). It changes nothing, but the first time it asks for read access to distance and speed.")
                }
            }
        }
        .navigationTitle(AthleteRoute.developer.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "Re-import your entire activity history from HealthKit?",
            isPresented: $isConfirmingResync,
            titleVisibility: .visible
        ) {
            Button("Force Full Resync", role: .destructive, action: onResync)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can take a while for a long training history.")
        }
        .confirmationDialog(
            "Remove duplicate activities?",
            isPresented: $isConfirmingDeduplicate,
            titleVisibility: .visible
        ) {
            Button("Deduplicate Activities", role: .destructive, action: onDeduplicate)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes duplicate activities left over from an older version of the app. This can't be undone.")
        }
    }
}
