import SwiftUI
import TrainingCore

/// The "Add Race" sheet (MVP2-17): name, date, and priority for a target race, then save. Own
/// `NavigationStack`/no explicit close button, matching `PlannedWorkoutSheet`'s convention.
struct RaceSheet: View {
    @Bindable var viewModel: RaceSheetViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingSaveError = false

    var body: some View {
        NavigationStack {
            Form {
                RaceFormFields(viewModel: viewModel)
            }
            .navigationTitle("Add Race")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Symbol-only, matching `PlannedWorkoutSheet`'s own toolbar (itself matching Apple
                // Health's sheet toolbars).
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
                            if await viewModel.save() {
                                dismiss()
                            } else if viewModel.saveError != nil {
                                isShowingSaveError = true
                            }
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save")
                    .disabled(!viewModel.canSave || viewModel.isSaving)
                }
            }
            .alert("Couldn't Save Race", isPresented: $isShowingSaveError, presenting: viewModel.saveError) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }
}

/// The name/date/priority `Form` fields `RaceSheet` shows — pulled out so `AddEntrySheet`
/// (MVP2-22) can embed the same fields below its planned-workout/race type picker, inside its own
/// `Form`/toolbar/save flow, without duplicating this content. Just one `Section`, unlike
/// `PlannedWorkoutFormFields`, since a race has no conditional sections of its own.
struct RaceFormFields: View {
    @Bindable var viewModel: RaceSheetViewModel

    var body: some View {
        Section {
            TextField("Name", text: $viewModel.name)
            // Lower-bounded so this can't be used to route around the same past-date rule
            // `DayActivitiesSection`'s "+" enforces at the entry point for planned
            // workouts — see `PlannedWorkoutSheetViewModel.minimumDate(asOf:)`'s own doc
            // comment.
            DatePicker("Date", selection: $viewModel.date, in: viewModel.minimumDate()..., displayedComponents: .date)
            Picker("Priority", selection: $viewModel.priority) {
                ForEach(RacePriority.allCases, id: \.self) { priority in
                    Text(priority.label).tag(priority)
                }
            }
        }
    }
}
