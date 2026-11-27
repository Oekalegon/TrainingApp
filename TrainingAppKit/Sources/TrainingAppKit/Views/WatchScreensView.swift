import SwiftUI
import TrainingCore
import TrainingWatchKit

/// Apple Watch ▸ Run Screens (WATCH-134): the screens the watch shows during a run. The sets for a free run
/// and for a workout are always there and can be changed; the athlete's own sets are for particular
/// workout templates, such as a sprint session and a long run. Changes go to the watch at once.
struct WatchScreensView: View {
    let screens: WatchScreenSetSync
    let model: TrainingModel
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                row(screens.config.freeRun, kind: .freeRun)
                row(screens.config.workout, kind: .workout)
            } header: {
                Text("Standard Sets")
            } footer: {
                Text("The free run set is used for a run with no plan. The workout set is used for a planned workout that has no set of its own.")
            }
            Section {
                ForEach(screens.config.sets) { set in
                    row(set, kind: .custom)
                }
                .onDelete { offsets in
                    for index in offsets { screens.deleteSet(id: screens.config.sets[index].id) }
                }
                NavigationLink {
                    editor(RunScreenSetDraft(WatchScreenSetSync.newSet(named: "")), kind: .custom)
                } label: {
                    Label("Add Set", systemImage: "plus")
                }
            } header: {
                Text("My Sets")
            } footer: {
                Text("Link a set to workout templates to run those workouts with its screens.")
            }
            Section {
                Button("Reset to Default Screens", role: .destructive) { confirmingReset = true }
            }
            if let error = screens.lastError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(AthleteRoute.watchScreens.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Reset the run screens?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { screens.resetToDefaults() }
        } message: {
            Text("Your own sets and their links to workout templates are removed.")
        }
    }

    /// The editor for a set, pushed on the navigation stack like the other settings pages.
    private func editor(_ draft: RunScreenSetDraft, kind: WatchScreenSetEditorView.Kind) -> some View {
        WatchScreenSetEditorView(screens: screens, model: model, draft: draft, kind: kind)
    }

    private func row(_ set: RunScreenSet, kind: WatchScreenSetEditorView.Kind) -> some View {
        NavigationLink {
            editor(RunScreenSetDraft(set), kind: kind)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name)
                Text(set.screens.count == 1 ? "1 screen" : "\(set.screens.count) screens")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(set.name), \(set.screens.count) screens")
    }
}
