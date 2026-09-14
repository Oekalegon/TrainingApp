import SwiftUI

/// A sheet explaining the four fitness metrics shown throughout the week view — Load, Fitness
/// (CTL), Fatigue (ATL), and Form (TSB) — reachable from `WeekView`'s toolbar (MVP1-45). Purely
/// informational: no state, no actions besides dismissal.
struct FitnessMetricsInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(TrainingMetricKind.allCases, id: \.self) { kind in
                Section {
                    Text(kind.explanation)
                        .foregroundStyle(.secondary)
                } header: {
                    Label(kind.name, systemImage: kind.icon)
                        .foregroundStyle(kind.color)
                        // The header's own default styling already renders it as a small caption;
                        // without this the icon+name reads at that same tiny size instead of
                        // standing out as each section's own title.
                        .font(.headline)
                }
            }
            .navigationTitle("Fitness Metrics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
