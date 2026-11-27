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
            HStack(alignment: .top, spacing: 12) {
                preview(template.items)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title).foregroundStyle(.primary)
                        .font(.subheadline.weight(.semibold)).padding(.bottom, 2)
                    WatchScreenItemBullets(items: template.items)
                    if template.isOnlyInWorkouts {
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
