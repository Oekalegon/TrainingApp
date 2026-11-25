import SwiftUI
import TrainingWatchKit

/// The items of one run screen (WATCH-134): reorder them, delete them, add more while there is room. The
/// last item sits at the bottom of the watch's screen, where the eye goes first, and a smaller watch drops
/// the first items of a full screen.
struct WatchScreenItemsView: View {
    @Binding var draft: RunScreenSetDraft
    let screenID: String
    @State private var isAdding = false

    private var screen: RunScreen? { draft.screens.first { $0.id == screenID } }

    var body: some View {
        List {
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
                    .accessibilityElement(children: .combine)
                }
                .onDelete { draft.removeItems(at: $0, from: screenID) }
                .onMove { draft.moveItems(from: $0, to: $1, in: screenID) }
                Button("Add Item", systemImage: "plus") { isAdding = true }
                    .disabled(draft.units(of: screenID) >= RunScreen.capacity)
            } header: {
                Text("Top to Bottom")
            } footer: {
                Text("\(draft.units(of: screenID)) of \(RunScreen.capacity) units used. The last item is at the bottom of the watch's screen.")
            }
        }
        .navigationTitle("Screen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        #endif
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                WatchScreenItemPickerView(draft: $draft, screenID: screenID)
            }
        }
    }
}
