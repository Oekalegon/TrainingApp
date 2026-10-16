import SwiftUI
import TrainingCore

/// Running Availability (MVP5-105, MVP5 design doc §4), the sections the Calendar screen shows below
/// the week start and time zone: the weekdays the athlete can run, and for each selected day, optionally,
/// when: any combination of morning, afternoon and evening (all three by default), and the maximum
/// number of runs (MVP5-132, 1 by default), both as compact segmented controls. It is the athlete's
/// own setting, kept on the profile and reused by every new plan, so it's set once here rather than
/// per plan.
///
/// Days are listed from the athlete's week start. Switching a day on selects all three parts of
/// the day, and a segmented control directly under it switches each part on or off (any
/// combination). A second one, 1 / 2 / 3, sets the maximum number of runs that day (the plan decides
/// the actual number): from 1 up to the number of selected parts, since the generator puts each run
/// in its own part, and hidden with one part, which implies one run. TrainingKit keeps a higher stored
/// number when parts are switched off and reads it capped; switching a day off resets it to 1.
/// Switching the last part off switches the day off. A change shows at
/// once and saves in the background; when the save fails it is taken
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
                    // A selected day expands in place to two compact segmented controls, narrower than
                    // the day's switch: the parts of the day (any combination) and the number of runs.
                    if shown.isAvailable(on: weekday) {
                        let runs = shown.runs(on: weekday)
                        let maxRuns = shown.maxRuns(on: weekday)
                        VStack(alignment: .trailing, spacing: 6) {
                            segmented(width: 230, DaySlot.allCases.map { slot in
                                Segment(title: slot.displayName, label: "\(weekday.displayName) \(slot.displayName)",
                                        selected: shown[weekday].contains(slot)) {
                                    await editor.toggleSlot(slot, on: weekday)
                                }
                            })
                            // One part implies one run, so there is nothing to choose.
                            if maxRuns > 1 {
                                HStack(spacing: 8) {
                                    Text("Maximum number of runs").font(.footnote).foregroundStyle(.secondary)
                                        .lineLimit(2).multilineTextAlignment(.trailing)
                                    segmented(width: CGFloat(maxRuns) * 37, (1...maxRuns).map { count in
                                        Segment(title: "\(count)", label: "\(weekday.displayName) \(count) \(count == 1 ? "run" : "runs") at most",
                                                selected: runs == count) {
                                            await editor.setRuns(count, on: weekday)
                                        }
                                    }, singleSelection: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Running Availability")
        } footer: {
            Text("The days you can run, and for each one the parts of the day you could run in, and the most runs a day. Plans are built from these, so you only set them once.")
        }
        .alert("Couldn't Save", isPresented: $editor.didFail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }

    /// One segment of a ``segmented(width:_:)`` control.
    private struct Segment {
        let title: String
        let label: String
        let selected: Bool
        let action: () async -> Void
    }

    /// A row of joined segments in one rounded container, a selected one filled. Several can be
    /// selected at once (the parts of the day) or one (the number of runs). Stacks vertically at accessibility Dynamic Type sizes.
    private func segmented(width: CGFloat, _ segments: [Segment], singleSelection: Bool = false) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                Button {
                    Task { await segment.action() }
                } label: {
                    Text(segment.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(segment.selected ? Color.white : Color.accentColor)
                        .background(segment.selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .accessibilityLabel(segment.label)
                .accessibilityAddTraits(singleSelection ? (segment.selected ? .isSelected : []) : (segment.selected ? [.isSelected, .isToggle] : .isToggle))
            }
        }
        .padding(2)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : width)
    }
}
