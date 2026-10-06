import SwiftUI
import TrainingCore

/// Heart Rate Zones (MVP2-123, design doc §2.3): the zone settings in effect (resting and maximum
/// heart rate, lactate threshold, method) and a table of each zone's bpm range. Maximum Heart Rate
/// shows its value on the title's own row and where it came from (MVP2-56) on a second row.
struct HeartRateZonesView: View {
    let viewModel: AthleteViewModel

    var body: some View {
        List {
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
        }
        .navigationTitle(AthleteRoute.heartRateZones.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// "120–133 bpm" — whole-number bpm on both ends, matching the other bpm figures here.
    private func bpmRangeText(_ range: ClosedRange<Double>) -> String {
        "\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) bpm"
    }
}
