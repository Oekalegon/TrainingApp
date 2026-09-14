import SwiftUI

/// A sheet explaining one or all of the four fitness metrics shown throughout the week view —
/// Load, Fitness (CTL), Fatigue (ATL), and Form (TSB) (MVP1-45). Tapping a specific pill in the
/// day list opens just that metric's own explanation (`focusedKind` set); the toolbar's general
/// "Fitness Metrics" entry point opens all four (`focusedKind` `nil`). Purely informational: no
/// state of its own, no actions besides dismissal.
struct FitnessMetricsInfoView: View {
    /// The one metric to explain, or `nil` to list all four — see this type's own doc comment.
    var focusedKind: TrainingMetricKind?
    @Environment(\.dismiss) private var dismiss

    private var kinds: [TrainingMetricKind] {
        focusedKind.map { [$0] } ?? TrainingMetricKind.allCases
    }

    var body: some View {
        NavigationStack {
            List(kinds, id: \.self) { kind in
                Section {
                    Text(kind.explanation)
                        .foregroundStyle(.secondary)
                } header: {
                    // Plain, un-tinted icon+name — matching the day list's own pills
                    // (`MetricPillView`'s doc comment), which deliberately don't tint the icon per
                    // metric either: the icon shape and the name right next to it already
                    // disambiguate the four without needing a color association.
                    Label("\(kind.name) (\(kind.abbreviation))", systemImage: kind.icon)
                        // The header's own default styling already renders it as a small caption;
                        // without this the icon+name reads at that same tiny size instead of
                        // standing out as each section's own title.
                        .font(.headline)
                }
            }
            // "Load", not "Fitness Metrics", when this is one metric's own sheet -- the plural
            // title only fits the all-four case.
            .navigationTitle(focusedKind.map { "\($0.name) (\($0.abbreviation))" } ?? "Fitness Metrics")
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
        // A single metric's explanation is one short paragraph -- a full-height sheet would be
        // mostly empty space, unlike the all-four case, which actually fills the screen.
        .presentationDetents(focusedKind != nil ? [.medium] : [.large])
    }
}
