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
        case .join: "May be one session split in two"
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
    /// Everything the card shows beyond the activity itself — TRIMP, overlap badge, intensity tint and
    /// the linked plan's expected values — from `WeekViewModel.activityCardContent(for:)`.
    let content: WeekViewModel.ActivityCardContent
    let onSelect: () -> Void

    /// The headline line omits the number entirely when this is `nil` (couldn't be computed) or
    /// rounds to `0` (nothing worth showing).
    private var trainingLoad: Double? { content.trainingLoad }
    /// `nil` when the activity isn't part of any overlap worth flagging, in which case no badge shows.
    private var overlapWarning: OverlapRecommendation? { content.overlapWarning }
    /// Shown as a subdued background tint; `nil` leaves the plain card.
    private var intensity: IntensityAssessment? { content.intensity }
    /// The linked plan's expected values: its TRIMP follows the actual TRIMP after a slash, and its
    /// duration and distance sit in a tertiary colour directly below the actual ones.
    private var planned: WeekViewModel.LinkedPlanExpectation? { content.planned }

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
                    if actualLoad != nil || plannedLoad != nil {
                        HStack(spacing: 2) {
                            Image(systemName: TrainingMetricKind.load.icon)
                            loadText
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(loadAccessibilityLabel)
                    }
                }
                .font(.subheadline)
                if activity.sport.isEndurance {
                    secondLineText
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, TimelineCardStyle.iconWidth + TimelineCardStyle.iconSpacing)
                    if let plannedExtentText {
                        plannedExtentText
                            .font(.caption.monospacedDigit())
                            .padding(.leading, TimelineCardStyle.iconWidth + TimelineCardStyle.iconSpacing)
                            .accessibilityLabel(plannedExtentAccessibilityLabel)
                    }
                }
            }
            .padding(TimelineCardStyle.contentPadding)
            .background {
                RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                    .fill(TimelineCardStyle.background)
                if let intensity {
                    RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous)
                        .fill(intensity.tint)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: TimelineCardStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        // The tint is visual only; say what it means.
        .accessibilityValue(intensity?.accessibilityDescription ?? "")
    }

    /// "1:30:00   8 km   🏔120 m" — duration always shown as H:MM:SS, distance/climb omitted
    /// entirely (not shown as "0 km"/"0 m") when the source doesn't report one. No separator
    /// character between parts, just extra spacing (rather than a single plain space) to visually
    /// group each part's own text/icon without implying they're one continuous phrase; climb alone
    /// also gets a leading mountain icon (via `Text(Image(...))` concatenation) to set it apart
    /// from the plain duration/distance numbers next to it.
    private static let partSpacing = "   "

    private var durationString: String {
        TimelineCardStyle.durationText(activity.duration)
    }

    /// The actual TRIMP, or `nil` when it couldn't be scored or rounds to nothing — the same rule as
    /// the headline's original number.
    private var actualLoad: Double? {
        guard let trainingLoad, trainingLoad.rounded() > 0 else { return nil }
        return trainingLoad
    }

    /// The linked plan's expected TRIMP, under the same rounds-to-nothing rule.
    private var plannedLoad: Double? {
        guard let load = planned?.load, load.rounded() > 0 else { return nil }
        return load
    }

    /// "85 / 90": the actual TRIMP, then the expected one after a slash in a tertiary colour (a dash
    /// stands in for an actual that couldn't be scored). Each piece carries its own monospaced
    /// digits so the pair reads as one figure.
    private var loadText: Text {
        let format = TimelineCardStyle.loadFormat
        let actual = Text(actualLoad?.formatted(format) ?? "–").monospacedDigit()
        guard let plannedLoad else { return actual }
        // Interpolating styled `Text`s rather than `+`, which is deprecated on the iOS 26 SDK.
        let expected = Text(" / \(plannedLoad.formatted(format))").monospacedDigit().foregroundStyle(.tertiary)
        return Text("\(actual)\(expected)")
    }

    private var loadAccessibilityLabel: String {
        let format = TimelineCardStyle.loadFormat
        var label = actualLoad.map { "Load \($0.formatted(format))" } ?? "Load not scored"
        if let plannedLoad {
            label += ", planned \(plannedLoad.formatted(format))"
        }
        return label
    }

    /// The linked plan's expected duration and distance — both, whichever the workout is defined
    /// by (the other is projected from the athlete's pace) — in the same "duration   distance"
    /// layout as `secondLineText`, so each lands directly under the actual value it compares with.
    /// Monospaced digits keep a duration's width equal to the actual duration's, which is what
    /// lines the distance column up.
    private var plannedExtentText: Text? {
        let duration = planned?.duration.map(TimelineCardStyle.durationText)
        let distance = planned?.distanceMeters.map { TimelineCardStyle.distanceText(meters: $0) }
        switch (duration, distance) {
        case (let duration?, let distance?):
            return Text("\(duration)\(Self.partSpacing)\(distance)").foregroundStyle(.tertiary)
        case (let duration?, nil):
            return Text(duration).foregroundStyle(.tertiary)
        case (nil, let distance?):
            return Text(distance).foregroundStyle(.tertiary)
        case (nil, nil):
            return nil
        }
    }

    private var plannedExtentAccessibilityLabel: String {
        var parts: [String] = []
        if let duration = planned?.duration {
            parts.append("duration " + TimelineCardStyle.spokenDuration(duration))
        }
        if let distance = planned?.distanceMeters {
            parts.append("distance " + TimelineCardStyle.spokenDistance(meters: distance))
        }
        return "Planned " + parts.joined(separator: ", ")
    }

    private var secondLineText: Text {
        var text = Text(durationString)
        if let distanceMeters = activity.distanceMeters {
            let distanceString = TimelineCardStyle.distanceText(meters: distanceMeters)
            text = Text("\(text)\(Self.partSpacing)\(distanceString)")
        }
        if let gainMeters = activity.elevation?.gainMeters, gainMeters > 50 {
            let gainString = TimelineCardStyle.distanceText(meters: gainMeters)
            text = Text("\(text)\(Self.partSpacing)\(Image(systemName: "mountain.2")) \(gainString)")
        }
        return text
    }
}
