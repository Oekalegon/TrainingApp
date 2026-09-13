import SwiftUI
import TrainingCore

/// The activity detail screen (design doc §2.2): text/stat rows only — no map/route, no
/// cadence/elevation charts in MVP 1.
struct ActivityDetailView: View {
    let viewModel: ActivityDetailViewModel
    /// Runs `WeekViewModel.resolveOverlap(deleting:)` for the given activity id and dismisses this
    /// sheet (MVP1-63) — `WeekView` supplies this; whichever side of `viewModel.overlapContext`
    /// the athlete picks to delete, the sheet closes afterward since whatever's currently shown
    /// (this activity, or its overlap context naming the other one) may no longer be accurate.
    let onResolveOverlap: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private var dateFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).hour().minute()
        format.timeZone = viewModel.timeZone
        return format
    }

    var body: some View {
        List {
            if let overlapContext = viewModel.overlapContext {
                Section("Overlap") {
                    OverlapSectionContent(
                        thisActivity: viewModel.activity,
                        context: overlapContext,
                        timeZone: viewModel.timeZone,
                        onResolve: { id in
                            onResolveOverlap(id)
                            dismiss()
                        }
                    )
                }
            }

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

/// The "Overlap" section's content in `ActivityDetailView` (MVP1-63) — a plain-language
/// description of the issue plus resolution buttons, both driven by `context.recommendation`.
/// Split out from `ActivityDetailView.body` since a `switch` over all four recommendation types
/// reads more clearly as its own small view than inline in that `List`.
private struct OverlapSectionContent: View {
    /// The activity whose own detail sheet this section is inside — as distinct from
    /// `context.otherActivity`, the other side of the pair.
    let thisActivity: Activity
    let context: OverlapContext
    let timeZone: TimeZone
    /// Called with the id of whichever activity (`thisActivity` or `context.otherActivity`) the
    /// athlete picked to delete.
    let onResolve: (UUID) -> Void

    private static func timeFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = timeZone
        return format
    }

    /// "Cycling at 14:32" — names the other side of the pair for the section's description text.
    private var otherActivityDescription: Text {
        let time = Text(context.otherActivity.start, format: Self.timeFormat(timeZone: timeZone))
        return Text("\(context.otherActivity.sport.displayName) at \(time)")
    }

    var body: some View {
        switch context.recommendation {
        case .duplicate(_, let remove):
            Text("This looks like a duplicate of \(otherActivityDescription).")
                .foregroundStyle(.secondary)
            // `remove` already names the correct side regardless of whether `thisActivity` is the
            // one to keep or the one to remove — a single, pre-decided action, unlike
            // `.merge`/`.conflict` below, which need the athlete to pick.
            Button("Remove Duplicate", role: .destructive) {
                onResolve(remove)
            }
        case .merge:
            Text("This overlaps \(otherActivityDescription), but the data differs — pick which one to keep.")
                .foregroundStyle(.secondary)
            resolutionButtons
        case .conflict:
            Text(
                "This overlaps \(otherActivityDescription) — they likely describe the same session. Pick which one actually happened."
            )
            .foregroundStyle(.secondary)
            resolutionButtons
        case .possibleMultisport:
            Text(
                "This is close to \(otherActivityDescription) — likely a separate leg of the same multisport session. No action needed."
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resolutionButtons: some View {
        Button("Keep This, Delete Other") {
            onResolve(context.otherActivity.id)
        }
        Button("Keep Other, Delete This", role: .destructive) {
            onResolve(thisActivity.id)
        }
    }
}
