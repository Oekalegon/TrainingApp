import SwiftUI
import TrainingWatchKit

/// Picks an item for a run screen (WATCH-134, WATCH-139): the first level lists the groups by main metric ("Heart
/// Rate", "Cadence"…), each opening on its own list of items (``WatchScreenItemGroupView``), so the many items can be
/// browsed. With something typed in the search the groups give way to the items whose name matches. An item that is
/// taller than what is left on the screen is shown dimmed and can't be chosen.
struct WatchScreenItemPickerView: View {
    @Binding var draft: RunScreenSetDraft
    let screenID: String
    /// The group of the item added last, kept by the screen's list so the picker can open on it next time.
    @Binding var lastGroupID: String?
    /// Called after an item was added, to close the picker.
    let onAdded: () -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if isSearching {
                results
            } else {
                groups
            }
        }
        .searchable(text: $query)
        .navigationDestination(for: String.self) { id in
            if let group = RunScreenItemCatalogue.browsableGroups.first(where: { $0.id == id }) {
                WatchScreenItemGroupView(
                    draft: $draft, screenID: screenID, group: group, onAdded: { added(in: group.id) })
            }
        }
        .navigationTitle("Add Item")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The groups, each a row with how many items it holds that opens the group's items, and under them the items of
    /// the groups too small to open.
    @ViewBuilder
    private var groups: some View {
        Section {
            ForEach(RunScreenItemCatalogue.browsableGroups) { group in
                NavigationLink(value: group.id) {
                    LabeledContent(group.title, value: "\(group.items.count)")
                }
                .accessibilityValue("\(group.items.count) items")
            }
        } footer: {
            Text("Choose a group, or search for an item by name.")
        }
        Section("Other Items") {
            ForEach(RunScreenItemCatalogue.inlineItems, id: \.self) { item in
                // An item outside the groups: the next pick starts from all the groups again.
                WatchScreenItemRow(draft: $draft, screenID: screenID, item: item, onAdded: { added(in: nil) })
            }
        }
    }

    /// Remembers the group of the item that was added, and closes the picker.
    private func added(in groupID: String?) {
        lastGroupID = groupID
        onAdded()
    }

    /// The items that match what is typed, by group and scope.
    @ViewBuilder
    private var results: some View {
        let matching = RunScreenItemCatalogue.groups(matching: query)
        if matching.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        ForEach(matching) { group in
            ForEach(group.sections) { part in
                Section(Self.header(of: part, in: group)) {
                    ForEach(part.items, id: \.self) { item in
                        WatchScreenItemRow(draft: $draft, screenID: screenID, item: item, onAdded: { added(in: group.id) })
                    }
                }
            }
        }
    }

    /// The header of a part: the group's name, and after it the scope's name when the part has one.
    private static func header(of part: RunScreenItemCatalogue.Group.Section, in group: RunScreenItemCatalogue.Group) -> String {
        guard let title = part.title else { return group.title }
        return "\(group.title), \(title)"
    }
}
