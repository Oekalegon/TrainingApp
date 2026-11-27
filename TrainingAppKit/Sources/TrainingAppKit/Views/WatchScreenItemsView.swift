import SwiftUI
import TrainingWatchKit

/// The items of one run screen (WATCH-134): reorder them, delete them, add more while there is room. The
/// last item sits at the bottom of the watch's screen, where the eye goes first, and a smaller watch drops
/// the first items of a full screen.
struct WatchScreenItemsView: View {
    @Binding var draft: RunScreenSetDraft
    let screenID: String
    @State private var isAdding = false
    /// The group of the item added last to this screen: the picker opens on it, as the next item is likely related
    /// (altitude, then grade). A screen that is just started has none, and the picker opens on all the groups.
    @State private var lastGroupID: String?
    /// The picker's navigation: the group it opens on, if any.
    @State private var pickerPath: [String] = []
    @State private var previewWatch = PreviewWatch.large
    @State private var previewsWorkout = true

    /// Whether the screen has all the room the watch chosen in the preview offers (6 units on the Ultra, 5 at 41 mm).
    private var isFull: Bool { draft.units(of: screenID) >= previewWatch.fittingUnits }

    /// The screen's name; an empty field is no name.
    private var nameBinding: Binding<String> {
        Binding(
            get: { screen?.name ?? "" },
            set: { text in
                guard let index = draft.screens.firstIndex(where: { $0.id == screenID }) else { return }
                draft.screens[index].name = text.isEmpty ? nil : text
            })
    }

    private var screen: RunScreen? { draft.screens.first { $0.id == screenID } }

    var body: some View {
        List {
            Section {
                TextField("Name (optional)", text: nameBinding)
            } header: {
                Text("Name")
            } footer: {
                Text("Shown in the list of screens; the watch doesn't show it.")
            }
            if let screen { previewSection(for: screen) }
            Section {
                ForEach(Array((screen?.items ?? []).enumerated()), id: \.offset) { _, item in
                    Label {
                        Text(item.title)
                    } icon: {
                        Image(systemName: item.systemImage).accessibilityHidden(true)
                    }
                    .labelStyle(TopAlignedLabelStyle())
                    .accessibilityElement(children: .combine)
                }
                .onDelete { draft.removeItems(at: $0, from: screenID) }
                .onMove { draft.moveItems(from: $0, to: $1, in: screenID) }
                // Not offered once the screen is full for the watch chosen in the preview.
                if !isFull {
                    Button("Add Item", systemImage: "plus") {
                    // Only a group that still exists: an id that matches none would push an empty page.
                        pickerPath = lastGroupID.flatMap { id in
                            RunScreenItemCatalogue.browsableGroups.contains { $0.id == id } ? [id] : nil
                        } ?? []
                        isAdding = true
                    }
                }
            } header: {
                Text("Top to Bottom")
            } footer: {
                Text(
                    (isFull ? "This screen is full (\(previewWatch.title)): remove an item to add another. " : "")
                        + "The last item is at the bottom of the watch's screen."
                        + (draft.isOnlyInWorkouts(screenID)
                            ? " This screen has an item for planned workouts, so a free run leaves the whole screen out." : ""))
            }
        }
        .navigationTitle("Screen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton() } }
        #endif
        .sheet(isPresented: $isAdding) {
            NavigationStack(path: $pickerPath) {
                WatchScreenItemPickerView(
                    draft: $draft, screenID: screenID, lastGroupID: $lastGroupID, onAdded: { isAdding = false })
            }
        }
    }

    /// The screen as the watch draws it, with sample values, and what to preview it on.
    private func previewSection(for screen: RunScreen) -> some View {
        Section {
            WatchScreenPreview(screen: screen, isWorkout: previewsWorkout, watch: previewWatch)
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            Picker("Watch", selection: $previewWatch) {
                ForEach(PreviewWatch.allCases) { Text($0.title).tag($0) }
            }
            Picker("Run", selection: $previewsWorkout) {
                Text("Planned Workout").tag(true)
                Text("Free Run").tag(false)
            }
        } header: {
            Text("Preview")
        } footer: {
            Text("Sample values. Other watches are drawn at 41 mm: a full screen loses its first item there, and a wide row has less room. A 45 mm watch fits the same as the Ultra. A free run leaves out a screen with an item for planned workouts.")
        }
    }
}
