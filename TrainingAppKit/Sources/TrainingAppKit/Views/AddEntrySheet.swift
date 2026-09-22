import SwiftUI
import TrainingCore

/// The day row's "add" sheet (MVP2-15, MVP2-17, MVP2-22): a segmented picker choosing between a
/// planned workout and a race, defaulting to planned workout (by far the more common of the two),
/// with that type's fields shown below and one shared save action. Replaces an earlier
/// `confirmationDialog` in front of two separate sheets — picking wrong there cost a whole extra
/// tap to back out of, for a choice that's the wrong default most of the time anyway; a picker the
/// athlete can glance past (or flip once, rarely) is cheaper.
///
/// Owns both `PlannedWorkoutSheetViewModel` and `RaceSheetViewModel` for the same day up front,
/// each keeping its own edited state independently as the picker flips between them — switching
/// tabs after typing a race name and back doesn't lose it. Neither view model is told about the
/// other; only whichever one is selected when the toolbar's Save is tapped actually persists
/// anything.
struct AddEntrySheet: View {
    /// Which set of fields is shown — `Identifiable`/`CaseIterable` purely for the `Picker`
    /// below, not because either view model needs to know about it.
    enum Kind: String, CaseIterable, Identifiable {
        case plannedWorkout = "Planned Workout"
        case race = "Race"

        var id: Self { self }
    }

    let plannedWorkoutViewModel: PlannedWorkoutSheetViewModel
    let raceViewModel: RaceSheetViewModel
    /// Defaults to `.plannedWorkout` (MVP2-22's design choice): it's the far more common thing to
    /// add from a day row, so it should never cost an extra tap to reach.
    @State private var kind: Kind = .plannedWorkout
    @Environment(\.dismiss) private var dismiss
    /// The error to show in the save-error alert, or `nil` when it isn't presented — set from the
    /// *attempted* kind's own `saveError` right when its `save()` call resolves, rather than the
    /// alert re-reading `kind` (which is `@State`, so it can change while the save is still in
    /// flight — nothing here disables the picker during a save). An earlier version read
    /// `saveError`/the alert's title as computed properties switching on live `kind`: flipping the
    /// picker mid-save made a genuine failure on the tab that was actually saving silently
    /// disappear, since the alert ended up checking the *other*, never-attempted view model's
    /// `saveError` (always `nil`) instead.
    @State private var pendingAlert: SaveErrorAlert?

    private var canSave: Bool {
        switch kind {
        case .plannedWorkout: plannedWorkoutViewModel.canSave
        case .race: raceViewModel.canSave
        }
    }

    private var isSaving: Bool {
        switch kind {
        case .plannedWorkout: plannedWorkoutViewModel.isSaving
        case .race: raceViewModel.isSaving
        }
    }

    /// Runs whichever kind was selected *when this was called* (captured into `attemptedKind`
    /// before the first `await`, immune to the picker changing underneath it) and reports the
    /// outcome against that same kind, never whatever `kind` happens to be by the time this
    /// resolves.
    private func save() async -> Bool {
        let attemptedKind = kind
        let saved: Bool
        let error: String?
        switch attemptedKind {
        case .plannedWorkout:
            saved = await plannedWorkoutViewModel.save()
            error = plannedWorkoutViewModel.saveError
        case .race:
            saved = await raceViewModel.save()
            error = raceViewModel.saveError
        }
        if !saved, let error {
            pendingAlert = SaveErrorAlert(kind: attemptedKind, message: error)
        }
        return saved
    }

    var body: some View {
        NavigationStack {
            // The type picker sits above the `Form`, not as a row inside it -- a `Form` row
            // renders every control (this one included) inside its own inset grouped-list
            // background, which reads as "one more field to fill in" rather than what this
            // actually is: a switch for which set of fields the form below is currently showing.
            VStack(spacing: 0) {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                // Wider than the matching top inset, so the gap down to the list reads as
                // separation from it rather than the picker just being vertically centered in a
                // uniform padding band.
                .padding(.bottom, 20)
                // Belt-and-suspenders alongside `save()` capturing its own `attemptedKind`: this
                // keeps the athlete from starting to fill in the other tab while a save is
                // genuinely still running, rather than just making that harmless if they do.
                .disabled(isSaving)

                Form {
                    switch kind {
                    case .plannedWorkout:
                        PlannedWorkoutFormFields(viewModel: plannedWorkoutViewModel)
                    case .race:
                        RaceFormFields(viewModel: raceViewModel)
                    }
                }
            }
            .navigationTitle(kind == .plannedWorkout ? "Planned Workout" : "Add Race")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Symbol-only, matching `PlannedWorkoutSheet`'s own toolbar.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await save() {
                                dismiss()
                            }
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save")
                    .disabled(!canSave || isSaving)
                }
            }
            .alert(
                pendingAlert?.title ?? "Couldn't Save",
                isPresented: Binding(
                    get: { pendingAlert != nil },
                    set: { if !$0 { pendingAlert = nil } }
                ),
                presenting: pendingAlert
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
        }
    }
}

/// `AddEntrySheet.pendingAlert`'s value: which kind's save failed (for the alert's title) and the
/// message to show, fixed at the moment `save()` resolved rather than re-derived from `kind`
/// (which may have moved on by the time the athlete sees this).
private struct SaveErrorAlert: Identifiable, Equatable {
    let kind: AddEntrySheet.Kind
    let message: String

    var id: String { message }

    var title: String {
        switch kind {
        case .plannedWorkout: "Couldn't Save Workout"
        case .race: "Couldn't Save Race"
        }
    }
}
