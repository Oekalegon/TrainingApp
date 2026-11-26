import SwiftUI
import TrainingWatchKit

/// Picks an item for a run screen (WATCH-134): the groups by main metric, each in parts by scope (the whole
/// run, this step and so on), searchable by name. An item that is taller than what is left on the screen is
/// shown dimmed and can't be chosen.
struct WatchScreenItemPickerView: View {
    @Binding var draft: RunScreenSetDraft
    let screenID: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(RunScreenItemCatalogue.groups(matching: query)) { group in
                ForEach(group.sections) { part in
                    Section(Self.header(of: part, in: group)) {
                        ForEach(part.items, id: \.self) { item in
                            row(for: item)
                        }
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

    /// The header of a part: the group's name, and after it the scope's name when the part has one.
    private static func header(of part: RunScreenItemCatalogue.Group.Section, in group: RunScreenItemCatalogue.Group) -> String {
        guard let title = part.title else { return group.title }
        return "\(group.title), \(title)"
    }

    private func row(for item: RunScreenItem) -> some View {
        let fits = draft.canAdd(item, to: screenID)
        return Button {
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
