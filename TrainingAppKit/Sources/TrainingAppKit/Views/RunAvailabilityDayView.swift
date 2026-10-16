import SwiftUI
import TrainingCore

/// One weekday of Running Availability (MVP5-105, MVP5-112), opened from the list of weekdays. Three sections, the choices
/// being selectable list rows except the number of runs:
///
/// 1. The weekday (large) with a short explanation, the switch "Can run on <weekday>" and, for an available day with
///    more than one part, the maximum number of runs: a compact segmented control (1 up to the selected parts) at
///    the trailing edge of the title's row, with its explanation below.
/// 2. The parts of the day (morning, afternoon, evening), any combination. Switching the last one off switches
///    the day off; switching the day on selects all three.
/// 3. The run types wanted that day, several allowed, each with a short description. A type picked for some days stays off the
///    others; types no day picks can go on any running day.
///
/// A change shows at once and saves in the background; when the save fails it is taken back and an alert says so
/// (see ``RunAvailabilityEditor``): here while this screen is open, on the list once it has been left.
struct RunAvailabilityDayView: View {
    let editor: RunAvailabilityEditor
    let weekday: Weekday
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The width of one segment of the runs control; scales with the text size.
    @ScaledMetric(relativeTo: .body) private var segmentWidth = 56

    var body: some View {
        @Bindable var editor = editor
        let shown = editor.shown
        let available = shown.isAvailable(on: weekday)
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weekday.displayName).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text("Say whether you could run on a \(weekday.displayName), when, and what kind of runs you want.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Toggle("Can run on \(weekday.displayName)", isOn: Binding(
                    get: { shown.isAvailable(on: weekday) },
                    set: { _ in Task { await editor.toggleDay(weekday) } }
                ))
                // One part implies one run, so there is nothing to choose.
                let maxRuns = shown.maxRuns(on: weekday)
                if available, maxRuns > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                            : AnyLayout(HStackLayout(spacing: 12))
                        layout {
                            Text("Maximum number of runs").font(.headline)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                            Picker("Maximum number of runs", selection: Binding(
                                get: { shown.runs(on: weekday) },
                                set: { count in Task { await editor.setRuns(count, on: weekday) } }
                            )) {
                                ForEach(1...maxRuns, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                        .accessibilityLabel("\(weekday.displayName) \(count) \(count == 1 ? "run" : "runs") at most")
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : CGFloat(maxRuns) * segmentWidth)
                        }
                        Text("The most runs you want this day, one in each part of the day. The plan decides the actual number.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if available {
                Section {
                    ForEach(DaySlot.allCases, id: \.self) { slot in
                        selectableRow(title: slot.displayName, selected: shown[weekday].contains(slot),
                                      label: "\(weekday.displayName) \(slot.displayName)") {
                            await editor.toggleSlot(slot, on: weekday)
                        }
                    }
                } header: {
                    Text("Time of day")
                } footer: {
                    Text("The parts of the day you could run in, any combination. Switching off the last one switches the day off.")
                }
                Section {
                    ForEach(RunType.allCases, id: \.self) { type in
                        selectableRow(title: type.displayName, detail: type.summary,
                                      selected: (shown.dayRunTypes[weekday] ?? []).contains(type),
                                      label: "\(type.displayName), \(weekday.displayName)") {
                            await editor.toggleRunType(type, on: weekday)
                        }
                    }
                    if !(shown.dayRunTypes[weekday] ?? []).isEmpty {
                        Button("Clear Run Types") { Task { await editor.clearRunTypes(on: weekday) } }
                    }
                } header: {
                    Text("Run types")
                } footer: {
                    Text("Pick the kinds of run you want on this day, or none to let the plan choose. A type you pick for some days stays off the others; types no day picks can go on any running day.")
                }
            }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { editor.isDayScreenShown = true }
        .onDisappear { editor.isDayScreenShown = false }
        .alert("Couldn't Save", isPresented: Binding(
            get: { editor.didFail && editor.isDayScreenShown }, set: { if !$0 { editor.didFail = false } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }

    /// A list row that can be selected: the title (and an optional description under it) with a check mark when
    /// selected. Speaks as a button with the selected trait; `single` marks a choice of one rather than a toggle.
    private func selectableRow(
        title: String, detail: String? = nil, selected: Bool, label: String,
        single: Bool = false, action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold).opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(detail ?? "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
