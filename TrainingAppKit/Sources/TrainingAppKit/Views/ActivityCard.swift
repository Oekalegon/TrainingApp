import SwiftUI
import TrainingCore

/// VoiceOver/tooltip text for `ActivityCard`'s overlap-warning badge (MVP1-63) — mirrors what
/// `ActivityOverlapChecker`'s own doc comments say to do about each case, condensed to a phrase
/// short enough to read as one badge's label rather than a full sentence.
extension OverlapRecommendation {
    var warningLabel: String {
        switch self {
        case .duplicate: "Possible duplicate activity"
        case .merge: "Overlaps another activity with different data"
        case .conflict: "Overlaps another activity"
        case .possibleMultisport: "Close to another activity"
        }
    }
}

/// A completed activity, rendered as a filled card in the timeline between weekday rows (design
/// doc §2.1, MVP1-41) rather than a plain list row — tapping it presents `ActivityDetailView` in a
/// sheet (see `WeekView`'s `.sheet(item: $selectedActivity)`), so this is a plain `Button` rather
/// than a `NavigationLink(value:)`/`navigationDestination` push.
///
/// Headline line: icon, sport name, and — trailing-aligned, same font as the name but secondary —
/// a bolt icon plus the activity's Load (TRIMP), the single most important number here. Second
/// line (endurance sports only): duration, distance, and climb (if over 50m, marked with a
/// mountain icon), smaller and secondary, indented to align with the name above it rather than the
/// icon. The time of day isn't shown in the card at all — `DayActivitiesSection` shows it on the
/// timeline instead, aligned with this headline line.
struct ActivityCard: View {
    let activity: Activity
    /// This activity's TRIMP, from `WeekViewModel.trainingLoad(for:)` — the headline line omits
    /// the number entirely when this is `nil` (couldn't be computed) or rounds to `0` (nothing
    /// worth showing).
    let trainingLoad: Double?
    /// This activity's overlap issue, from `WeekViewModel.overlapWarning(for:)` (MVP1-63) — `nil`
    /// when it isn't part of any overlap worth flagging, in which case no badge shows.
    let overlapWarning: OverlapRecommendation?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TimelineCardStyle.iconSpacing) {
                    Image(systemName: activity.sport.symbolName)
                        .foregroundStyle(.primary)
                        .frame(width: TimelineCardStyle.iconWidth)
                    Text(activity.sport.displayName)
                        .foregroundStyle(.primary)
                    if let overlapWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(overlapWarning.warningLabel)
                    }
                    Spacer()
                    // Rounds first, then checks that against zero — `loadFormat` itself rounds to
                    // the nearest whole number, so a raw value like 0.3 is `> 0` but would still
                    // display as "0" if the raw (unrounded) value were what got checked here.
                    if let trainingLoad, trainingLoad.rounded() > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: TrainingMetricKind.load.icon)
                            Text(trainingLoad.formatted(TimelineCardStyle.loadFormat))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                if activity.sport.isEndurance {
                    secondLineText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, TimelineCardStyle.iconWidth + TimelineCardStyle.iconSpacing)
                }
            }
            .padding(TimelineCardStyle.contentPadding)
            .background {
                RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                    .fill(TimelineCardStyle.background)
            }
            .contentShape(RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "1:30:00   8 km   🏔120 m" — duration always shown as H:MM:SS, distance/climb omitted
    /// entirely (not shown as "0 km"/"0 m") when the source doesn't report one. No separator
    /// character between parts, just extra spacing (rather than a single plain space) to visually
    /// group each part's own text/icon without implying they're one continuous phrase; climb alone
    /// also gets a leading mountain icon (via `Text(Image(...))` concatenation) to set it apart
    /// from the plain duration/distance numbers next to it.
    private static let partSpacing = "   "

    private var secondLineText: Text {
        let durationString = Duration.seconds(activity.duration).formatted(.time(pattern: .hourMinuteSecond))
        var text = Text(durationString)
        if let distanceMeters = activity.distanceMeters {
            let distanceString = Measurement(value: distanceMeters, unit: UnitLength.meters).formatted(TimelineCardStyle.measurementFormat)
            text = Text("\(text)\(Self.partSpacing)\(distanceString)")
        }
        if let gainMeters = activity.elevation?.gainMeters, gainMeters > 50 {
            let gainString = Measurement(value: gainMeters, unit: UnitLength.meters).formatted(TimelineCardStyle.measurementFormat)
            text = Text("\(text)\(Self.partSpacing)\(Image(systemName: "mountain.2")) \(gainString)")
        }
        return text
    }
}
