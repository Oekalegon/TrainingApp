import SwiftUI
import TrainingCore
import TrainingWatchKit

/// Edits one run screen set (WATCH-134): its name, its screens (reorder, add, delete, the one the run opens
/// on) and, for the athlete's own sets, which workout templates run with it. The changes are made on a copy
/// (``RunScreenSetDraft``) and saved with Save, which refuses a set that can't be used and says why.
struct WatchScreenSetEditorView: View {
    /// Which set is being edited: the two built-in ones keep their names and can't be deleted.
    enum Kind { case freeRun, workout, custom }

    let screens: WatchScreenSetSync
    let model: TrainingModel
    @State var draft: RunScreenSetDraft
    let kind: Kind
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?

    init(screens: WatchScreenSetSync, model: TrainingModel, draft: RunScreenSetDraft, kind: Kind) {
        self.screens = screens
        self.model = model
        _draft = State(initialValue: draft)
        self.kind = kind
    }

    var body: some View {
        List {
            if kind == .custom {
                Section("Name") {
                    TextField("Name", text: $draft.name)
                }
            }
            Section {
                ForEach($draft.screens) { $screen in
                    NavigationLink {
                        WatchScreenItemsView(draft: $draft, screenID: screen.id)
                    } label: {
                        screenRow(screen)
                    }
                }
                .onDelete { draft.removeScreens(at: $0) }
                .onMove { draft.moveScreens(from: $0, to: $1) }
                Button("Add Screen", systemImage: "plus") { draft.addScreen() }
            } header: {
                Text("Screens")
            } footer: {
                Text("The crown turns through the screens, the first on top. A screen holds \(RunScreen.capacity) units of height.")
            }
            Section {
                Picker("Opens On", selection: Binding(
                    get: { draft.startScreen?.id ?? "" },
                    set: { draft.startScreenID = $0 })
                ) {
                    ForEach(Array(draft.screens.enumerated()), id: \.element.id) { index, screen in
                        Text("Screen \(index + 1)").tag(screen.id)
                    }
                }
            }
            if kind == .custom {
                Section {
                    NavigationLink("Workout Templates") {
                        WatchScreenTemplateLinksView(screens: screens, model: model, setID: draft.id)
                    }
                    .disabled(!screens.config.sets.contains { $0.id == draft.id })
                } footer: {
                    Text("Save the set first, then choose the templates that use it.")
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
        }
    }

    private var title: String {
        switch kind {
        case .freeRun, .workout: draft.name
        case .custom: draft.name.isEmpty ? "New Set" : draft.name
        }
    }

    private func screenRow(_ screen: RunScreen) -> some View {
        let number = (draft.screens.firstIndex { $0.id == screen.id } ?? 0) + 1
        return VStack(alignment: .leading, spacing: 2) {
            Text("Screen \(number)")
            Text(screen.items.map(\.title).joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Text("\(screen.units) of \(RunScreen.capacity) units").font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func save() {
        do {
            switch kind {
            case .freeRun: try screens.updateFreeRun(draft.set)
            case .workout: try screens.updateWorkout(draft.set)
            case .custom: try screens.save(draft.set)
            }
            dismiss()
        } catch let error as ScreenSetError {
            errorText = Self.message(for: error)
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// What to tell the athlete about a set that can't be saved.
    static func message(for error: ScreenSetError) -> String {
        switch error {
        case .emptyName: "Give the set a name."
        case .noScreens: "A set needs at least one screen."
        case .emptyScreen: "A screen needs at least one item. Add one or delete the screen."
        case .overCapacity: "A screen holds at most \(RunScreen.capacity) units. Remove an item."
        case .duplicateScreenID: "Two screens have the same identifier."
        case .reservedID: "That identifier belongs to a built-in set."
        }
    }
}
