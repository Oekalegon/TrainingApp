import SwiftUI
import TrainingCore

/// Calendar (MVP2-123, MVP2-132, design doc §2.3): the week's first day and the time zone, which the
/// app buckets days and weeks by. Both can be changed. Each applies to all history, so changing one
/// regroups every day and week and recalculates the fitness history once; the footer says so. Below
/// them come the Running Availability sections (MVP5-105), where the athlete sets when they can run.
struct CalendarSettingsView: View {
    let viewModel: AthleteViewModel
    let microCycleViewModel: MicroCycleViewModel
    @State private var isShowingError = false

    var body: some View {
        List {
            Section {
                Picker("Week Starts On", selection: Binding(
                    get: { viewModel.athlete.weekStartsOn },
                    set: { weekday in
                        Task {
                            if await !microCycleViewModel.setWeekStartsOn(weekday) { isShowingError = true }
                        }
                    }
                )) {
                    ForEach(Weekday.allCases, id: \.self) { weekday in
                        Text(weekday.displayName).tag(weekday)
                    }
                }
                NavigationLink {
                    TimeZonePickerView(selected: viewModel.athlete.timeZone) { timeZone in
                        await microCycleViewModel.setTimeZone(timeZone)
                    }
                } label: {
                    LabeledContent("Time Zone", value: viewModel.athlete.timeZone.identifier)
                }
            } footer: {
                Text("These apply to all of your history. Changing either regroups your days and weeks and recalculates your fitness history.")
            }

            RunningAvailabilitySections(viewModel: viewModel, microCycleViewModel: microCycleViewModel)

            AthleteRunTypesSections(weekStart: viewModel.athlete.weekStartsOn)
        }
        .navigationTitle(AthleteRoute.calendar.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Couldn't Save", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }
}
