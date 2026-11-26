import SwiftUI
import TrainingWatchKit

/// One item of the catalogue in the picker (WATCH-134, WATCH-139): its name and what it shows, dimmed when it
/// doesn't fit what is left of the screen. Choosing it adds it to the screen.
struct WatchScreenItemRow: View {
    @Binding var draft: RunScreenSetDraft
    let screenID: String
    let item: RunScreenItem
    /// Called after the item was added, to close the picker.
    let onAdded: () -> Void

    var body: some View {
        let fits = draft.canAdd(item, to: screenID)
        Button {
            if draft.add(item, to: screenID) { onAdded() }
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
