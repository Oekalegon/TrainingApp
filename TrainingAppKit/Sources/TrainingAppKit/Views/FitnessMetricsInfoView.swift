import SwiftUI

/// A sheet explaining the four fitness metrics shown throughout the week view — Load, Fitness
/// (CTL), Fatigue (ATL), and Form (TSB) — reachable from `WeekView`'s toolbar and from tapping any
/// individual metric pill in the day list (MVP1-45). Purely informational: no state of its own
/// besides where it's scrolled, no actions besides dismissal.
struct FitnessMetricsInfoView: View {
    /// The metric to scroll to on appear — set when opened by tapping that metric's own pill in
    /// the day list, rather than the toolbar's general entry point, so the athlete lands on the
    /// explanation they actually asked for instead of always the top of the list.
    var focusedKind: TrainingMetricKind?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(TrainingMetricKind.allCases, id: \.self) { kind in
                    Section {
                        Text(kind.explanation)
                            .foregroundStyle(.secondary)
                    } header: {
                        // Plain, un-tinted icon+name — matching the day list's own pills
                        // (`MetricPillView`'s doc comment), which deliberately don't tint the icon
                        // per metric either: the icon shape and the name right next to it already
                        // disambiguate the four without needing a color association.
                        Label("\(kind.name) (\(kind.abbreviation))", systemImage: kind.icon)
                            // The header's own default styling already renders it as a small
                            // caption; without this the icon+name reads at that same tiny size
                            // instead of standing out as each section's own title.
                            .font(.headline)
                    }
                    .id(kind)
                }
                .onAppear {
                    guard let focusedKind else { return }
                    proxy.scrollTo(focusedKind, anchor: .top)
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
