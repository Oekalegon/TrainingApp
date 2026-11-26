import SwiftUI
import TrainingWatchKit

/// Picks the start of a new run screen (WATCH-137): a blank one with the total time, or one of the ready-made
/// screens (``StandardScreens``), which can then be changed like any other. A screen with an item for planned
/// workouts says so, since a free run leaves it out.
struct WatchStandardScreenPickerView: View {
    @Binding var draft: RunScreenSetDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    draft.addScreen()
                    dismiss()
                } label: {
                    Label("Blank Screen", systemImage: "square.dashed")
                }
            } footer: {
                Text("Starts with the total time; add the items yourself.")
            }
            Section("Standard Screens") {
                ForEach(StandardScreens.all) { template in
                    row(for: template)
                }
            }
        }
        .navigationTitle("Add Screen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func row(for template: StandardScreens.Template) -> some View {
        Button {
            draft.addScreen(from: template)
            dismiss()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title).foregroundStyle(.primary)
                    Text(template.detail).font(.caption).foregroundStyle(.secondary)
                    Text(template.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            } icon: {
                Image(systemName: template.systemImage).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
