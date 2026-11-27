import SwiftUI
import TrainingWatchKit

/// Picks the start of a new run screen (WATCH-137): a blank one with the total time, one of the athlete's own screens
/// (those already in their sets) or one of the ready-made screens (``StandardScreens``), which can then be changed like
/// any other. The search looks through the own and the standard screens at once, by the screen's name and by the names
/// of the items on it. A screen with an item for planned workouts says so, since a free run leaves it out.
struct WatchStandardScreenPickerView: View {
    @Binding var draft: RunScreenSetDraft
    /// The athlete's own screens that can be added again (``ScreenLibrary/userScreens(in:)``).
    let userScreens: [RunScreen]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var ownMatches: [RunScreen] {
        userScreens.filter { ScreenLibrary.matches(name: $0.name, items: $0.items, query: query) }
    }

    private var standardMatches: [StandardScreens.Template] {
        StandardScreens.all.filter { ScreenLibrary.matches(name: $0.title, items: $0.items, query: query) }
    }

    var body: some View {
        List {
            if !isSearching {
                Section {
                    Button {
                        draft.addScreen()
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            preview([.metric(.totalTime)])
                            Text("Blank Screen")
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                } footer: {
                    Text("Starts with the total time; add the items yourself.")
                }
            }
            if !ownMatches.isEmpty {
                Section("My Screens") {
                    ForEach(ownMatches) { screen in
                        optionRow(title: screen.name, items: screen.items, isOnlyInWorkouts: screen.requiresSteps) {
                            draft.addScreen(copying: screen)
                        }
                    }
                }
            }
            if !standardMatches.isEmpty {
                Section("Standard Screens") {
                    ForEach(standardMatches) { template in
                        optionRow(title: template.title, items: template.items, isOnlyInWorkouts: template.isOnlyInWorkouts) {
                            draft.addScreen(from: template)
                        }
                    }
                }
            }
            if isSearching && ownMatches.isEmpty && standardMatches.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Add Screen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $query, prompt: "Screen or Metric")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    /// One screen to add: its preview and, beside it, its name (when it has one) and its items as a bulleted list.
    private func optionRow(title: String?, items: [RunScreenItem], isOnlyInWorkouts: Bool, add: @escaping () -> Void) -> some View {
        Button {
            add()
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                preview(items)
                VStack(alignment: .leading, spacing: 2) {
                    if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(title).foregroundStyle(.primary).font(.subheadline.weight(.semibold)).padding(.bottom, 2)
                    }
                    WatchScreenItemBullets(items: items)
                    if isOnlyInWorkouts {
                        Text("Planned workouts only.").font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                    }
                }
            }
        }
        // Plain, so the texts keep the list's colours and not the button's blue tint.
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// A small preview of a screen with these items, as in the editor's list of screens.
    private func preview(_ items: [RunScreenItem]) -> some View {
        WatchScreenPreview(screen: RunScreen(id: "preview", items: items), isWorkout: true, watch: .large, scale: 0.3)
            .accessibilityHidden(true)
    }
}
