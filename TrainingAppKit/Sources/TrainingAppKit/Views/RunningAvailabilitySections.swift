import SwiftUI
import TrainingCore

/// Running Availability (MVP5-105, MVP5 design doc §4), the section the Calendar screen shows below
/// the week start and time zone: one row per weekday, from the athlete's week start, with a summary line
/// ("Off", or the parts of the day, number of runs and run types). A row opens ``RunAvailabilityDayView``, where the
/// day is switched on and its parts of the day, maximum number of runs and run types (MVP5-112) are set. It is the
/// athlete's own setting, kept on the profile and reused by every new plan, so it's set once here rather than
/// per plan. Meant to sit inside a `List`.
struct RunningAvailabilitySections: View {
    let viewModel: AthleteViewModel
    @State private var editor: RunAvailabilityEditor

    init(viewModel: AthleteViewModel, microCycleViewModel: MicroCycleViewModel) {
        self.viewModel = viewModel
        _editor = State(initialValue: RunAvailabilityEditor(
            saved: { microCycleViewModel.athleteViewModel.runAvailability },
            save: { await microCycleViewModel.setRunAvailability($0) }
        ))
    }

    var body: some View {
        let shown = editor.shown
        Section {
            ForEach(viewModel.runAvailabilityWeekdays, id: \.self) { weekday in
                NavigationLink {
                    RunAvailabilityDayView(editor: editor, weekday: weekday)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weekday.displayName)
                        Text(shown.summary(on: weekday)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Running Availability")
        } footer: {
            Text("Choose a day to set when you could run, the most runs, and the run types you want. Plans are built from these, so you only set them once.")
        }
    }
}
