import SwiftUI
import TrainingWatchKit

/// The items of one group of the catalogue (WATCH-139), in parts by scope (the whole run, this step and so on):
/// the second level of the picker, opened from the group's row.
struct WatchScreenItemGroupView: View {
    @Binding var draft: RunScreenSetDraft
    let screenID: String
    let group: RunScreenItemCatalogue.Group
    /// Called after an item was added, to close the picker (not just this view).
    let onAdded: () -> Void

    var body: some View {
        List {
            ForEach(group.sections) { part in
                Section(part.title ?? group.title) {
                    ForEach(part.items, id: \.self) { item in
                        WatchScreenItemRow(draft: $draft, screenID: screenID, item: item, onAdded: onAdded)
                    }
                }
            }
        }
        .navigationTitle(group.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
