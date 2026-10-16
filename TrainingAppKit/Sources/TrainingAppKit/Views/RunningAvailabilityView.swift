import SwiftUI
import TrainingCore

/// Running Availability (MVP5-105, MVP5 design doc §4): the weekdays the athlete can run, and for
/// each selected day the slots, morning and afternoon / evening. It is the athlete's own setting,
/// kept on the profile and reused by every new plan, so it's set once here rather than per plan.
///
/// Days are listed from the athlete's week start. Tapping a day selects it with both slots, which
/// then show as toggles under it in the same list; switching off both slots, or tapping the day again, clears it. A
/// change shows at once and saves in the background; when the save fails it is taken back and an
/// alert says so.
struct RunningAvailabilityView: View {
    let viewModel: AthleteViewModel
    let microCycleViewModel: MicroCycleViewModel
    /// The availability just chosen, shown while it saves so the toggles don't wait for the profile to reload.
    @State private var pending: RunAvailability?
    /// Counts the changes made, so the shown choice is given up only when the latest save is done.
    @State private var changeCount = 0
    @State private var isShowingError = false

    private var shown: RunAvailability { pending ?? viewModel.runAvailability }

    private func apply(_ change: (RunAvailability) -> RunAvailability) {
        let updated = change(shown)
        pending = updated
        changeCount += 1
        let current = changeCount
        Task {
            if await !microCycleViewModel.setRunAvailability(updated) { isShowingError = true }
            guard current == changeCount else { return }
            pending = nil
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(viewModel.runAvailabilityWeekdays, id: \.self) { weekday in
                    Toggle(weekday.displayName, isOn: Binding(
                        get: { shown.isAvailable(on: weekday) },
                        set: { _ in apply { $0.togglingDay(weekday) } }
                    ))
                    // A selected day expands in place to its slots.
                    if shown.isAvailable(on: weekday) {
                        ForEach(DaySlot.allCases, id: \.self) { slot in
                            Toggle(slot.displayName, isOn: Binding(
                                get: { shown[weekday].contains(slot) },
                                set: { _ in apply { $0.togglingSlot(slot, on: weekday) } }
                            ))
                            .padding(.leading, 20)
                            .font(.subheadline)
                            .accessibilityLabel("\(weekday.displayName) \(slot.displayName)")
                        }
                    }
                }
            } header: {
                Text("Days")
            } footer: {
                Text("The days you can run. Plans are built from these, so you only set them once.")
            }
        }
        .navigationTitle(AthleteRoute.runningAvailability.title)
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
