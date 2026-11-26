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
    @State private var isAddingScreen = false

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
                Button("Add Screen", systemImage: "plus") { isAddingScreen = true }
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
                        Text("Screen \(index + 1): \(screen.items.map(\.title).joined(separator: ", "))").tag(screen.id)
                    }
                }
            }
            if kind == .custom {
                Section {
                    NavigationLink("Workout Templates") {
                        WatchScreenTemplateLinksView(screens: screens, model: model, setID: draft.id)
                    }
                    .disabled(!isSaved)
                } footer: {
                    Text(isSaved
                        ? "Choose the workout templates that run with this set."
                        : "Save the set first, then choose the templates that use it.")
                }
            }
            if let message = errorText ?? problem?.userMessage {
                Section {
                    Text(message).foregroundStyle(problem == .emptyName && errorText == nil ? Color.secondary : Color.red)
                }
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton() } }
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(isSaved ? "Close" : "Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(problem != nil) }
        }
        .sheet(isPresented: $isAddingScreen) {
            NavigationStack { WatchStandardScreenPickerView(draft: $draft) }
        }
    }

    /// Whether the set is already one of the athlete's saved sets (a new one is, after its first Save).
    private var isSaved: Bool { screens.config.sets.contains { $0.id == draft.id } }

    /// What keeps the set from being saved now, shown under the list as the athlete edits.
    private var problem: ScreenSetError? { draft.validationError(checksName: kind == .custom) }

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
        // A new set stays open after its first Save, so templates can be linked to it at once.
        let isFirstSave = kind == .custom && !isSaved
        do {
            switch kind {
            case .freeRun: try screens.updateFreeRun(draft.set)
            case .workout: try screens.updateWorkout(draft.set)
            case .custom: try screens.save(draft.set)
            }
            errorText = nil
            if !isFirstSave { dismiss() }
        } catch let error as ScreenSetError {
            errorText = error.userMessage
        } catch {
            errorText = error.localizedDescription
        }
    }
}
