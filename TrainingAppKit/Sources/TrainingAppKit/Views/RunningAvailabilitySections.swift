import SwiftUI
import TrainingCore

/// Running Availability (MVP5-105, MVP5 design doc §4), the sections the Calendar screen shows below
/// the week start and time zone: the weekdays the athlete can run, and for each selected day, optionally,
/// when: any time (the default), only the morning, or only the afternoon / evening. It is the athlete's own setting, kept on the profile and
/// reused by every new plan, so it's set once here rather than per plan.
///
/// Days are listed from the athlete's week start. Tapping a day selects it for any time of day, and
/// a segmented control directly under it narrows it to one slot; tapping the day again clears it. A change shows at once and saves in the background; when the save fails it is taken
/// back and an alert says so (see ``RunAvailabilityEditor``). Meant to sit inside a `List`.
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
                Toggle(weekday.displayName, isOn: Binding(
                    get: { shown.isAvailable(on: weekday) },
                    set: { _ in Task { await editor.toggleDay(weekday) } }
                ))
                .accessibilityHint("Selected days can be narrowed to morning or afternoon and evening")
                // A selected day expands in place to an optional choice of when: any time unless
                // the athlete narrows it to the morning or the afternoon / evening.
                if shown.isAvailable(on: weekday) {
                    Picker("\(weekday.displayName) time", selection: Binding(
                        get: { shown.slotChoice(on: weekday) },
                        set: { choice in Task { await editor.setSlots(choice, on: weekday) } }
                    )) {
                        ForEach(SlotChoice.allCases, id: \.self) { choice in
                            Text(choice.shortName)
                                .accessibilityLabel(choice.displayName)
                                .tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .font(.footnote)
                }
            }
        } header: {
            Text("Running Availability")
        } footer: {
            Text("The days you can run, and for each one whether any time of day or only morning or afternoon / evening. Plans are built from these, so you only set them once.")
        }
        .alert("Couldn't Save", isPresented: $editor.didFail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }
}
