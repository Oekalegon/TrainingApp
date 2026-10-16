import SwiftUI
import TrainingCore

/// One weekday of Running Availability (MVP5-105, MVP5-112): whether the athlete can run that day, and for an
/// available day the parts of the day (any combination of morning, afternoon and evening), the maximum number
/// of runs (from 1 up to the selected parts) and the run types wanted. Switching the day on selects all
/// three parts; switching the last part off switches the day off. A change shows at once and saves in the
/// background; when the save fails it is taken back and an alert says so (see ``RunAvailabilityEditor``).
/// A run type picked for some days stays off the others, and types no day picks can go on any running day.
struct RunAvailabilityDayView: View {
    let editor: RunAvailabilityEditor
    let weekday: Weekday
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        @Bindable var editor = editor
        let shown = editor.shown
        List {
            Section {
                Toggle("Can run on \(weekday.displayName)", isOn: Binding(
                    get: { shown.isAvailable(on: weekday) },
                    set: { _ in Task { await editor.toggleDay(weekday) } }
                ))
            }
            if shown.isAvailable(on: weekday) {
                Section("Parts of the day") {
                    segmented(width: 230, DaySlot.allCases.map { slot in
                        Segment(title: slot.displayName, label: "\(weekday.displayName) \(slot.displayName)",
                                selected: shown[weekday].contains(slot)) {
                            await editor.toggleSlot(slot, on: weekday)
                        }
                    })
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // One part implies one run, so there is nothing to choose.
                let maxRuns = shown.maxRuns(on: weekday)
                if maxRuns > 1 {
                    Section {
                        HStack(spacing: 8) {
                            Text("Maximum number of runs")
                            Spacer()
                            segmented(width: CGFloat(maxRuns) * 37, (1...maxRuns).map { count in
                                Segment(title: "\(count)", label: "\(weekday.displayName) \(count) \(count == 1 ? "run" : "runs") at most",
                                        selected: shown.runs(on: weekday) == count) {
                                    await editor.setRuns(count, on: weekday)
                                }
                            }, singleSelection: true)
                        }
                    } footer: {
                        Text("The plan decides the actual number of runs.")
                    }
                }
                Section {
                    RunTypeChips(selected: shown.dayRunTypes[weekday] ?? [], dayName: weekday.displayName) { type in
                        Task { await editor.toggleRunType(type, on: weekday) }
                    }
                    if !(shown.dayRunTypes[weekday] ?? []).isEmpty {
                        Button("Clear Run Types") { Task { await editor.clearRunTypes(on: weekday) } }
                    }
                } header: {
                    Text("Run types")
                } footer: {
                    Text("A run type you pick for some days stays off the others; types no day picks can go on any running day.")
                }
            }
        }
        .navigationTitle(weekday.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
