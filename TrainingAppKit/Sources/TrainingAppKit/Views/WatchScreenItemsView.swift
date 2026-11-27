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

    private var screen: RunScreen? { draft.screens.first { $0.id == screenID } }

    var body: some View {
        List {
            if let screen { previewSection(for: screen) }
            Section {
                ForEach(Array((screen?.items ?? []).enumerated()), id: \.offset) { _, item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text("\(item.height) \(item.height == 1 ? "unit" : "units")").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.systemImage).accessibilityHidden(true)
                    }
                    .labelStyle(TopAlignedLabelStyle())
                    .accessibilityElement(children: .combine)
                }
                .onDelete { draft.removeItems(at: $0, from: screenID) }
                .onMove { draft.moveItems(from: $0, to: $1, in: screenID) }
                Button("Add Item", systemImage: "plus") {
                    // Only a group that still exists: an id that matches none would push an empty page.
                    pickerPath = lastGroupID.flatMap { id in
                        RunScreenItemCatalogue.browsableGroups.contains { $0.id == id } ? [id] : nil
                    } ?? []
                    isAdding = true
                }
                    .disabled(draft.units(of: screenID) >= RunScreen.capacity)
            } header: {
                Text("Top to Bottom")
            } footer: {
                Text(
                    "\(draft.units(of: screenID)) of \(RunScreen.capacity) units used. The last item is at the bottom of the watch's screen."
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
            Text("Sample values. A smaller watch drops the first items of a full screen, and a free run leaves out a screen with an item for planned workouts.")
        }
    }
}
