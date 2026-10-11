import SwiftUI

/// The spike's report on recent workouts (MVP2-146), as text the developer can read, copy or share:
/// pushed from the Developer screen's "Inspect Recent Workouts".
struct WorkoutInspectionView: View {
    let inspector: any WorkoutInspecting
    /// How many recent workouts to read.
    var limit = 30
    @State private var report: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let report {
                ScrollView {
                    Text(report)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else if let errorMessage {
                ContentUnavailableView("Couldn't Read Workouts", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("Reading workouts…")
            }
        }
        .navigationTitle("Inspect Workouts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let report {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: report, subject: Text("Workout inspection"))
                }
            }
        }
        .task {
            do {
                report = try await inspector.inspectRecentWorkouts(limit: limit)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
