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
    @State private var isShowingSaveError = false

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

    private var saveError: String? {
        switch kind {
        case .plannedWorkout: plannedWorkoutViewModel.saveError
        case .race: raceViewModel.saveError
        }
    }

    private func save() async -> Bool {
        switch kind {
        case .plannedWorkout: await plannedWorkoutViewModel.save()
        case .race: await raceViewModel.save()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Deliberately outside any `Section`, matching `Form`'s own "no section" look for
                // a single control that isn't itself a list of fields — a `Section` header/footer
                // pair here would visually compete with `PlannedWorkoutFormFields`'/
                // `RaceFormFields`' own section below it for no reason.
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                switch kind {
                case .plannedWorkout:
                    PlannedWorkoutFormFields(viewModel: plannedWorkoutViewModel)
                case .race:
                    RaceFormFields(viewModel: raceViewModel)
                }
            }
            .navigationTitle(kind == .plannedWorkout ? "Planned Workout" : "Add Race")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Symbol-only, matching `PlannedWorkoutSheet`/`RaceSheet`'s own toolbars.
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
                            } else if saveError != nil {
                                isShowingSaveError = true
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
                kind == .plannedWorkout ? "Couldn't Save Workout" : "Couldn't Save Race",
                isPresented: $isShowingSaveError, presenting: saveError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }
}
