import SwiftUI
import TrainingCore
import TrainingWatchKit

/// Which workout templates run with a set of run screens (WATCH-134): a check mark for each template that is
/// linked to the set. A template can be linked to one set; choosing one that another set has moves it.
struct WatchScreenTemplateLinksView: View {
    let screens: WatchScreenSetSync
    let model: TrainingModel
    let setID: String
    @State private var errorText: String?

    private var builtInIDs: Set<UUID> { Set(BuiltInWorkoutTemplates.all.map(\.id)) }

    var body: some View {
        List {
            ForEach(model.libraryTemplates) { template in
                let isCustom = !builtInIDs.contains(template.id)
                let current = screens.linkedSetID(for: template, isCustom: isCustom)
                Button {
                    toggle(template, isCustom: isCustom, current: current)
                } label: {
                    HStack {
                        Text(template.name).foregroundStyle(.primary)
                        Spacer()
                        if current == setID {
                            Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                        } else if current != nil {
                            Text("Other set").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                // Plain, so the name keeps the list's colour and not the button's blue tint.
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityAddTraits(current == setID ? .isSelected : [])
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Workout Templates")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func toggle(_ template: WorkoutTemplate, isCustom: Bool, current: String?) {
        let new: String? = current == setID ? nil : setID
        Task {
            do {
                try await screens.link(template, isCustom: isCustom, to: new, model: model)
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
