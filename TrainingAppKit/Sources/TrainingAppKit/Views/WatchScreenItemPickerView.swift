import SwiftUI
import TrainingWatchKit

/// Picks an item for a run screen (WATCH-134): the groups by main metric, searchable by name. An item
/// that is taller than what is left on the screen is shown dimmed and can't be chosen.
struct WatchScreenItemPickerView: View {
    @Binding var draft: RunScreenSetDraft
    let screenID: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(RunScreenItemCatalogue.groups(matching: query)) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.self) { item in
                        let fits = draft.canAdd(item, to: screenID)
                        Button {
                            if draft.add(item, to: screenID) { dismiss() }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(fits ? item.detail : "Doesn't fit: \(item.height) units needed")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: item.systemImage).accessibilityHidden(true)
                            }
                        }
                        .disabled(!fits)
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Add Item")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }
}
