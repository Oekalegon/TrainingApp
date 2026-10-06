import SwiftUI
import TrainingCore

/// Heart Rate Zones (MVP2-123, MVP2-132, design doc §2.3): the zone settings in effect (resting and
/// maximum heart rate, lactate threshold, method) and a table of each zone's bpm range, then the
/// history of settings with the date each took effect. The athlete adds settings from a date with the
/// toolbar button (or by tapping a history row to change that entry), and swipes a row to delete it.
/// Maximum Heart Rate shows its value on the title's own row and where it came from (MVP2-56) on a
/// second row.
///
/// While Apple Health is connected, a switch decides whether the resting heart rate follows it; with
/// it on, the resting heart rate can't be edited. The maximum is never changed for the athlete: an
/// age estimate that differs is offered with a button, to accept.
struct HeartRateZonesView: View {
    let viewModel: AthleteViewModel
    let weekViewModel: WeekViewModel
    /// Whether Apple Health is connected, which shows the resting-heart-rate switch.
    let showsHealthKitSwitch: Bool
    /// The sheet being shown: a new entry or one from the history.
    @State private var editing: HeartRateSettingsDraft?
    @State private var isShowingError = false

    var body: some View {
        List {
            if showsHealthKitSwitch {
                Section {
                    Toggle("Resting Heart Rate from Apple Health", isOn: Binding(
                        get: { viewModel.athlete.usesHealthKitRestingHeartRate },
                        set: { isOn in
                            Task {
                                if await !weekViewModel.setUsesHealthKitRestingHeartRate(isOn) { isShowingError = true }
                            }
                        }
                    ))
                } footer: {
                    Text(viewModel.athlete.usesHealthKitRestingHeartRate
                        ? "Your resting heart rate follows Apple Health and can't be edited here."
                        : "Enter your own resting heart rate with the add button.")
                }
            }

            if let settings = viewModel.currentHeartRateZoneSettings {
                Section {
                    LabeledContent("Resting Heart Rate", value: "\(Int(settings.restingHeartRateBPM.rounded())) bpm")
                    LabeledContent {
                        Text("\(Int(settings.maxHeartRateBPM.rounded())) bpm")
                    } label: {
                        Text("Maximum Heart Rate")
                        // Where the value came from (MVP2-56): an age estimate is a guess, a
                        // workout-measured value is a floor on the real max.
                        if let source = viewModel.maxHeartRateSourceDescription {
                            Text(source)
                        }
                    }
                    if let lactateThreshold = settings.lactateThresholdHeartRateBPM {
                        LabeledContent("Lactate Threshold", value: "\(Int(lactateThreshold.rounded())) bpm")
                    }
                    LabeledContent("Method", value: settings.zoneMethod.displayName)
                }

                if let estimate = viewModel.offeredMaxHeartRateEstimate() {
                    Section {
                        Button("Use Age Estimate (\(Int(estimate)) bpm)") {
                            var draft = HeartRateSettingsDraft(prefilling: settings, effectiveDate: .now)
                            draft.maxHeartRate = Int(estimate)
                            Task { await save(draft, source: .formula) }
                        }
                    } footer: {
                        Text("Your age suggests a different maximum heart rate. It's only used if you accept it.")
                    }
                }

                // Each zone's own bpm range under the settings above (MVP1-71): a reference table
                // derived from them rather than a setting of its own, with the same colored dot as
                // the activity detail sheet's zone list (MVP1-70).
                if !viewModel.heartRateZoneRanges.isEmpty {
                    Section("Zones") {
                        ForEach(viewModel.heartRateZoneRanges) { zoneRange in
                            LabeledContent {
                                Text(bpmRangeText(zoneRange.bpmRange))
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(zoneRange.zone.color)
                                        .frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    Text("Zone \(zoneRange.zone.rawValue)")
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("No heart-rate zone settings on record yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("History") {
                ForEach(viewModel.heartRateHistory, id: \.effectiveDate) { entry in
                    Button {
                        editing = HeartRateSettingsDraft(
                            prefilling: entry, effectiveDate: AthleteViewModel.editingDate(for: entry.effectiveDate)
                        )
                    } label: {
                        LabeledContent {
                            Text("Resting \(Int(entry.restingHeartRateBPM.rounded())) · Max \(Int(entry.maxHeartRateBPM.rounded()))")
                        } label: {
                            Text(dateText(entry.effectiveDate))
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        if viewModel.heartRateHistory.count > 1 {
                            Button("Delete", role: .destructive) {
                                Task {
                                    if await !weekViewModel.removeHeartRateSettings(on: entry.effectiveDate) { isShowingError = true }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(AthleteRoute.heartRateZones.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Settings", systemImage: "plus") {
                    editing = HeartRateSettingsDraft(
                        prefilling: viewModel.currentHeartRateZoneSettings, effectiveDate: .now
                    )
                }
            }
        }
        .sheet(item: Binding(
            get: { editing.map(EditingDraft.init) },
            set: { editing = $0?.draft }
        )) { item in
            HeartRateSettingsSheet(
                draft: item.draft,
                isRestingLocked: showsHealthKitSwitch && viewModel.athlete.usesHealthKitRestingHeartRate
            ) { draft in
                await weekViewModel.recordHeartRateSettings(draft.settings())
            }
        }
        .alert("Couldn't Save", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }

    /// Records an accepted age estimate, as formula-sourced.
    private func save(_ draft: HeartRateSettingsDraft, source: MaxHeartRateSource) async {
        var settings = draft.settings()
        settings.maxHeartRateSource = source
        if await !weekViewModel.recordHeartRateSettings(settings) { isShowingError = true }
    }

    /// "120–133 bpm" — whole-number bpm on both ends, matching the other bpm figures here.
    private func bpmRangeText(_ range: ClosedRange<Double>) -> String {
        "\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) bpm"
    }

    private func dateText(_ date: Date) -> String {
        if date == .distantPast { return "Since the start" }
        return date.formatted(Date.FormatStyle(timeZone: viewModel.athlete.timeZone).day().month(.abbreviated).year())
    }

    /// Wraps a draft for `.sheet(item:)`, which needs an `Identifiable` item.
    private struct EditingDraft: Identifiable {
        let draft: HeartRateSettingsDraft
        var id: Date { draft.effectiveDate }
    }
}
