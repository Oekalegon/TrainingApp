import SwiftUI
import TrainingCore

/// Running Availability (MVP5-105, MVP5 design doc §4), the sections the Calendar screen shows below
/// the week start and time zone: the weekdays the athlete can run, and for each selected day, optionally,
/// when: any combination of morning, afternoon and evening (all three by default). It is the athlete's own setting, kept on the profile and
/// reused by every new plan, so it's set once here rather than per plan.
///
/// Days are listed from the athlete's week start. Switching a day on selects all three parts of
/// the day, and three chips directly under it switch each part on or off; switching the last part off switches the day off. A change shows at once and saves in the background; when the save fails it is taken
/// back and an alert says so (see ``RunAvailabilityEditor``). Meant to sit inside a `List`.
struct RunningAvailabilitySections: View {
    let viewModel: AthleteViewModel
    @State private var editor: RunAvailabilityEditor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                // One row per day, so the choice sits under the day's switch without a divider.
                VStack(spacing: 10) {
                    Toggle(weekday.displayName, isOn: Binding(
                        get: { shown.isAvailable(on: weekday) },
                        set: { _ in Task { await editor.toggleDay(weekday) } }
                    ))
                    .accessibilityHint("A selected day can be limited to some parts of the day")
                    // A selected day expands in place to its parts of the day, each switched on or off.
                    if shown.isAvailable(on: weekday) {
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                        layout {
                            ForEach(DaySlot.allCases, id: \.self) { slot in
                                chip(slot.displayName, label: "\(weekday.displayName) \(slot.displayName)", selected: shown[weekday].contains(slot)) {
                                    await editor.toggleSlot(slot, on: weekday)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Running Availability")
        } footer: {
            Text("The days you can run, and for each one which of morning, afternoon and evening. The parts you pick are when you could run; how many runs a day gets is not set here yet. Plans are built from these, so you only set them once.")
        }
        .alert("Couldn't Save", isPresented: $editor.didFail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }

    /// One part of the day as a toggle chip, filled when selected.
    private func chip(_ title: String, label: String, selected: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .background(selected ? Color.accentColor : Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
