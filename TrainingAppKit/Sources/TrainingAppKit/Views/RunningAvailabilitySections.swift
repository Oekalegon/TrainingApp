import SwiftUI
import TrainingCore

/// Running Availability (MVP5-105, MVP5 design doc §4), the sections the Calendar screen shows below
/// the week start and time zone: the weekdays the athlete can run, and for each selected day the
/// slots, morning and afternoon / evening. It is the athlete's own setting, kept on the profile and
/// reused by every new plan, so it's set once here rather than per plan.
///
/// Days are listed from the athlete's week start. Tapping a day selects it with both slots, which
/// then show as toggles directly under it; switching off both slots, or tapping the day again,
/// clears it. A change shows at once and saves in the background; when the save fails it is taken
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
                .accessibilityHint("Shows morning and afternoon options")
                // A selected day expands in place to its slots.
                if shown.isAvailable(on: weekday) {
                    ForEach(DaySlot.allCases, id: \.self) { slot in
                        Toggle(slot.displayName, isOn: Binding(
                            get: { shown[weekday].contains(slot) },
                            set: { _ in Task { await editor.toggleSlot(slot, on: weekday) } }
                        ))
                        .padding(.leading, 20)
                        .font(.subheadline)
                        .accessibilityLabel("\(weekday.displayName) \(slot.displayName)")
                    }
                }
            }
        } header: {
            Text("Running Availability")
        } footer: {
            Text("The days you can run. Plans are built from these, so you only set them once.")
        }
        .alert("Couldn't Save", isPresented: $editor.didFail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }
}
