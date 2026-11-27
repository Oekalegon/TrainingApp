import SwiftUI
import TrainingCore
import TrainingWatchKit

/// Edits one run screen set (WATCH-134): its name, its screens (reorder, add, delete, the one the run opens
/// on) and, for the athlete's own sets, which workout templates run with it. The changes are made on a copy
/// (``RunScreenSetDraft``) and saved with Save, which refuses a set that can't be used and says why. It is pushed
/// on the navigation stack: going back without Save drops the changes.
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
    /// What the draft was when the editor opened, or when it was last saved: going back with a different draft asks first.
    @State private var baseline: RunScreenSetDraft
    @State private var confirmingDiscard = false

    init(screens: WatchScreenSetSync, model: TrainingModel, draft: RunScreenSetDraft, kind: Kind) {
        self.screens = screens
        self.model = model
        _draft = State(initialValue: draft)
        _baseline = State(initialValue: draft)
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
                Text("The crown turns through the screens, the first on top. The run opens on the first screen.")
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
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(problem != nil) }
            if hasUnsavedChanges {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { confirmingDiscard = true }
                }
            }
        }
        // With changes the system back button (and the swipe back) would drop them silently: Cancel asks first.
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .sheet(isPresented: $isAddingScreen) {
            NavigationStack {
                WatchStandardScreenPickerView(draft: $draft, userScreens: ScreenLibrary.userScreens(in: screens.config))
            }
        }
    }

    /// Whether the draft differs from what it was when the editor opened or was last saved.
    private var hasUnsavedChanges: Bool { draft != baseline }

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
        // The preview and the metrics start at the top of the row; the metrics are a bulleted list.
        return HStack(alignment: .top, spacing: 12) {
            // A small preview of the screen with sample values; the list beside it says the same in words.
            WatchScreenPreview(screen: screen, isWorkout: true, watch: .large, scale: 0.3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let name = draft.displayName(of: screen.id) {
                    Text(name).font(.subheadline.weight(.semibold)).padding(.bottom, 2)
                }
                WatchScreenItemBullets(items: screen.items)
            }
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
            baseline = draft
            if !isFirstSave { dismiss() }
        } catch let error as ScreenSetError {
            errorText = error.userMessage
        } catch {
            errorText = error.localizedDescription
        }
    }
}
