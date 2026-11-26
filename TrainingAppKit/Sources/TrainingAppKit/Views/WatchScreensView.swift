import SwiftUI
import TrainingCore
import TrainingWatchKit

/// Apple Watch ▸ Run Screens (WATCH-134): the screens the watch shows during a run. The sets for a free run
/// and for a workout are always there and can be changed; the athlete's own sets are for particular
/// workout templates, such as a sprint session and a long run. Changes go to the watch at once.
struct WatchScreensView: View {
    let screens: WatchScreenSetSync
    let model: TrainingModel
    @State private var editing: Editing?
    @State private var confirmingReset = false

    /// A set being edited and whether it is one of the two built-in ones (which keep their names).
    private struct Editing: Identifiable {
        let id = UUID()
        let draft: RunScreenSetDraft
        let kind: WatchScreenSetEditorView.Kind
    }

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
                Button("Add Set", systemImage: "plus") {
                    editing = Editing(
                        draft: RunScreenSetDraft(WatchScreenSetSync.newSet(named: "")), kind: .custom)
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
        .sheet(item: $editing) { editing in
            NavigationStack {
                WatchScreenSetEditorView(screens: screens, model: model, draft: editing.draft, kind: editing.kind)
            }
        }
        .confirmationDialog("Reset the run screens?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { screens.resetToDefaults() }
        } message: {
            Text("Your own sets and their links to workout templates are removed.")
        }
    }

    private func row(_ set: RunScreenSet, kind: WatchScreenSetEditorView.Kind) -> some View {
        Button {
            editing = Editing(draft: RunScreenSetDraft(set), kind: kind)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).foregroundStyle(.primary)
                Text(set.screens.count == 1 ? "1 screen" : "\(set.screens.count) screens")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(set.name), \(set.screens.count) screens")
    }
}
