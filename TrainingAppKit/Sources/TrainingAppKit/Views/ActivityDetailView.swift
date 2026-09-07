import SwiftUI
import TrainingCore

/// The activity detail screen (design doc §2.2): text/stat rows only — no map/route, no
/// cadence/elevation charts in MVP 1.
struct ActivityDetailView: View {
    let viewModel: ActivityDetailViewModel

    private var dateFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).hour().minute()
        format.timeZone = viewModel.timeZone
        return format
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Start", value: viewModel.activity.start.formatted(dateFormat))
                LabeledContent("Duration", value: durationText)
                if let distanceMeters = viewModel.summary.distanceMeters {
                    LabeledContent("Distance", value: distanceText(distanceMeters))
                }
            }

            Section("Load") {
                if viewModel.summary.load.confidence > 0 {
                    LabeledContent("Training Load (TRIMP)", value: loadText)
                } else {
                    Text("Load could not be computed for this activity.")
                        .foregroundStyle(.secondary)
                }
            }

            if let averageHeartRateBPM = viewModel.summary.averageHeartRateBPM {
                Section("Heart Rate") {
                    LabeledContent("Average", value: "\(Int(averageHeartRateBPM.rounded())) bpm")
                }
            }

            if viewModel.summary.timeInZone.total > 0 {
                Section("Time in Zone") {
                    ForEach(1...5, id: \.self) { zone in
                        let seconds = viewModel.summary.timeInZone.seconds[zone] ?? 0
                        if seconds > 0 {
                            LabeledContent("Zone \(zone)", value: zoneText(seconds: seconds, zone: zone))
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.activity.sport.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var durationText: String {
        Duration.seconds(viewModel.summary.movingTime).formatted(.units(allowed: [.hours, .minutes, .seconds]))
    }

    private func distanceText(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated))
    }

    private var loadText: String {
        viewModel.summary.load.value.formatted(.number.precision(.fractionLength(0)))
    }

    private func zoneText(seconds: TimeInterval, zone: Int) -> String {
        let duration = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes]))
        let fraction = viewModel.summary.timeInZone.fraction(of: zone)
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        return "\(duration) (\(percent))"
    }
}
