import SwiftUI
import TrainingCore

/// The name/date/priority `Form` fields for adding a race (MVP2-17) — embedded by `AddEntrySheet`
/// below its planned-workout/race type picker. There's no standalone wrapper `View` around this
/// (unlike `PlannedWorkoutFormFields`/`PlannedWorkoutSheet`): nothing edits an existing race yet
/// (`RaceSheetViewModel` only creates new ones), so `AddEntrySheet` is currently the only place
/// these fields are ever shown — add a wrapper back if/when an edit-race entry point needs one.
/// Just one `Section`, unlike `PlannedWorkoutFormFields`, since a race has no conditional sections
/// of its own.
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
