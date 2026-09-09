import SwiftUI
import TrainingCore

/// Background for every un-highlighted pill/badge on the day list's timeline — `WeekdayPillView`'s
/// own pill and each `MetricPillView`'s label, so they read as one consistent pill style rather
/// than two independently-tuned ones.
private let unhighlightedPillBackground = Color.secondary.opacity(0.12)

/// Renders one day's row in the week view's day list (design doc §2.1, MVP1-39/MVP1-40/MVP1-41): a
/// weekday pill marking its place on the list's vertical timeline, that day's Load/Fitness/
/// Fatigue/Form pills, and — sitting in the timeline between this pill and the next day's — that
/// day's completed and planned activities as cards, planned ones rendered visibly distinct.
///
/// Unlike the flat row list MVP1-20 introduced, every day in the displayed week gets a row here,
/// whether or not it has activities: the weekday pill is what makes the list read as a timeline of
/// the whole week, not just a list of things that happened. A day with neither activities nor
/// plans still renders its pill, just with an empty content column beside it — no "rest day" text,
/// since the empty space next to a pill already reads as "nothing that day".
///
/// Deliberately holds no local `@State`: `WeekView` recreates the scroll view a given week's rows
/// live in (via `.id(...)` on that week's first date) whenever the displayed week changes, so a
/// swipe resets scroll position instead of leaking it into the next week — any local state added
/// here (an expand/collapse toggle, say) would be silently reset by the same mechanism. If this
/// type ever needs its own state, that interaction needs accounting for first.
struct DayActivitiesSection: View {
    let date: Date
    /// Whether `date` is today, in the athlete's calendar — highlights the weekday pill.
    let isToday: Bool
    /// Whether to draw the timeline connector below this row's pill — `false` for the last day in
    /// the list, so the vertical line doesn't dangle past the final pill.
    let showsConnector: Bool
    /// This day's CTL/ATL/TSB, shown as pills beside the weekday pill (MVP1-40) — `nil` before
    /// the first load, in which case no pill row renders (rather than a row of placeholder zeros).
    let metrics: FitnessMetrics?
    let activities: [Activity]
    let plans: [PlannedActivity]
    let workoutName: (PlannedActivity) -> String?
    /// An activity's training load (TRIMP) — the card's headline number (MVP1-41). `nil` when
    /// `WeekViewModel.trainingLoad(for:)` couldn't score it, in which case the card omits the
    /// number rather than showing a misleading "0".
    let trainingLoad: (Activity) -> Double?
    /// The athlete's timezone — every date here is formatted with this, not the device's default,
    /// so the dates/times shown agree with how `WeekViewModel` grouped them into this day in the
    /// first place.
    let timeZone: TimeZone
    /// Called when a completed activity's row is tapped — `WeekView` presents it in a detail
    /// sheet, not a navigation push, so this hands back the tapped `Activity` rather than this
    /// view building a `NavigationLink` itself.
    let onSelectActivity: (Activity) -> Void

    /// Hour + minute only — shown beside each activity card on the timeline, in the same column
    /// the weekday pill sits in above it (MVP1-41; the pill itself already carries the day).
    private static func timeFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = timeZone
        return format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                WeekdayPillView(date: date, isToday: isToday, timeZone: timeZone)
                    .frame(width: WeekdayPillView.columnWidth)
                if let metrics {
                    DayMetricsPillRow(metrics: metrics, showsOnlyForm: activities.isEmpty)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            ForEach(activities) { activity in
                HStack(alignment: .top, spacing: 12) {
                    // `.top` plus this label's own top padding matching the card's — deterministic,
                    // not reliant on SwiftUI's baseline-guide propagation through the card's own
                    // padding/background/Button wrapping (same reasoning as the weekday-pill/
                    // metrics-row alignment above).
                    Text(activity.start, format: Self.timeFormat(timeZone: timeZone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: WeekdayPillView.columnWidth)
                        .padding(.top, ActivityCard.contentPadding)
                    ActivityCard(
                        activity: activity,
                        trainingLoad: trainingLoad(activity),
                        onSelect: { onSelectActivity(activity) }
                    )
                }
            }
            ForEach(plans) { plan in
                HStack(alignment: .top, spacing: 12) {
                    // No time shown here — a `PlannedActivity` only carries a calendar day, not a
                    // time of day — but the column still needs to hold its width so the card below
                    // starts at the same x as the activity cards above it.
                    Color.clear.frame(width: WeekdayPillView.columnWidth)
                    PlannedActivityCard(plan: plan, workoutName: workoutName(plan))
                }
            }
        }
        .padding(.bottom, 20)
        // The continuous timeline line, drawn once behind the whole day rather than per row: a
        // per-row line (as MVP1-39 used, back when this view had only one row) can't span multiple
        // sibling `HStack`s the way a single background can. It's drawn behind the weekday pill
        // too, but the pill's own opaque fill covers that portion, so the visible effect — the
        // line starting right where the pill ends — is unchanged.
        .background(alignment: .topLeading) {
            if showsConnector {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, WeekdayPillView.columnWidth / 2 - 1)
            }
        }
    }
}

/// A weekday + day-of-month badge marking one day's position on the day list's vertical timeline
/// (MVP1-39). Highlighted when it's today, so "today" reads at a glance while scrolling.
struct WeekdayPillView: View {
    let date: Date
    let isToday: Bool
    let timeZone: TimeZone

    /// Width of the timeline column this pill sits in — not measured from the pill's actual
    /// rendered width (which hugs its text via padding), just a fixed value comfortably wider
    /// than "Wed 9" at this font size, so the connector line below it (drawn by
    /// `DayActivitiesSection`, in a column of this same width) stays centered under it.
    /// `minimumScaleFactor` on the pill's text is the real safety net if a locale's weekday
    /// abbreviation or a two-digit day ever needs more room than this affords.
    static let columnWidth: CGFloat = 60

    /// Weekday abbreviation + day-of-month, e.g. "Mon 9" — kept as one `Text` (rather than two
    /// stacked) so it fits on a single line at a small enough size to still read clearly inside
    /// the pill.
    private static func format(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        format.timeZone = timeZone
        return format
    }

    var body: some View {
        Text(date, format: Self.format(timeZone: timeZone))
            .font(.system(size: 11, weight: .regular, design: .default))
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isToday ? Color.white : Color.primary)
            .background {
                Capsule().fill(isToday ? Color.accentColor : unhighlightedPillBackground)
            }
            // This pill is deliberately fixed-size (it's a small badge, not body text), so it
            // doesn't scale with the rest of the row at larger accessibility text sizes — capped
            // rather than left unbounded, so a maxed-out Dynamic Type setting can't blow the
            // pill's small footprint out to something that no longer reads as a compact badge.
            .dynamicTypeSize(.large)
    }
}

/// Load/CTL/ATL/TSB shown as compact value+icon pills beside a weekday row (design doc §2.1,
/// MVP1-40) — each metric's `TrainingMetricKind` icon rather than the raw abbreviations, matching
/// how `FitnessChartView`'s legend pairs the same icons with each series' name.
private struct DayMetricsPillRow: View {
    let metrics: FitnessMetrics
    /// `true` on a day with no completed activities — Load/Fitness/Fatigue describe that day's
    /// training input, which has nothing to say on a day nothing happened, so only Form (TSB, a
    /// trend that moves whether or not the athlete trained that day) is worth showing.
    let showsOnlyForm: Bool

    /// Extra spacing between Load and Fitness, on top of ``metricSpacing`` — Load is that day's
    /// raw load, a different kind of number from the three smoothed CTL/ATL/TSB series that
    /// follow it, so the wider gap reads as "one metric, then a separate group of three" rather
    /// than four equally-related values.
    private static let loadGroupSpacing: CGFloat = 24
    private static let metricSpacing: CGFloat = 15

    /// Load/CTL/ATL are unsigned — no sign shown. TSB is a balance that reads meaningfully as
    /// positive ("fresh") or negative ("fatigued"), so it always shows its sign.
    private static let unsignedFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    private static let signedFormat = FloatingPointFormatStyle<Double>.number
        .sign(strategy: .always()).precision(.fractionLength(0))

    var body: some View {
        HStack(spacing: 0) {
            if !showsOnlyForm {
                MetricPillView(kind: .load, value: metrics.load.formatted(Self.unsignedFormat))
                Spacer().frame(width: Self.loadGroupSpacing)
                MetricPillView(kind: .fitness, value: metrics.ctl.formatted(Self.unsignedFormat))
                Spacer().frame(width: Self.metricSpacing)
                MetricPillView(kind: .fatigue, value: metrics.atl.formatted(Self.unsignedFormat))
                Spacer().frame(width: Self.metricSpacing)
            }
            MetricPillView(kind: .form, value: metrics.tsb.formatted(Self.signedFormat))
        }
    }
}

/// One metric's plain value followed by its icon pill, e.g. "42" then a "battery.100" pill — only
/// the icon sits in a pill (grey, matching `WeekdayPillView`'s own). The icon is plain `.primary`,
/// not tinted per metric — matching `FitnessChartView`'s legend (which pairs the same icon with
/// its series color) would need the value's own color scale threaded down here for no real gain,
/// since the icon shape alone already disambiguates Load/Fitness/Fatigue/Form at this size. The
/// value carries no pill/background at all, so it doesn't compete visually with the icon.
private struct MetricPillView: View {
    let kind: TrainingMetricKind
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .foregroundStyle(.primary)
            Image(systemName: kind.icon)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(unhighlightedPillBackground)
                }
        }
        .font(.system(size: 11, weight: .regular, design: .default))
        // Same reasoning as `WeekdayPillView`: the icon pill is a small fixed-size badge, capped
        // rather than unbounded, so it stays compact even at large accessibility text sizes.
        .dynamicTypeSize(.large)
        // Without this, VoiceOver reads the icon's own SF Symbol name ("battery 100 percent")
        // instead of what it actually represents here — combining the two elements into one and
        // giving it an explicit label makes this read as "Fitness, 42" instead of two
        // disconnected fragments ("42", then "battery 100 percent").
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.name), \(value)")
    }
}

/// Corner radius shared by `ActivityCard` and `PlannedActivityCard` (design doc §2.1, MVP1-41),
/// so a completed activity's filled card and a planned one's outlined card read as the same shape
/// language sitting in the timeline between weekday rows, distinguished by fill/border rather than
/// by silhouette.
private let timelineCardCornerRadius: CGFloat = 12

/// A completed activity, rendered as a filled card in the timeline between weekday rows (design
/// doc §2.1, MVP1-41) rather than a plain list row — tapping it presents `ActivityDetailView` in a
/// sheet (see `WeekView`'s `.sheet(item: $selectedActivity)`), so this is a plain `Button` rather
/// than a `NavigationLink(value:)`/`navigationDestination` push.
///
/// Headline line: icon, sport name, and — trailing-aligned, same font as the name but secondary —
/// the activity's Load (TRIMP), the single most important number here. Second line (endurance
/// sports only): duration, distance, and climb (if over 50m), smaller and secondary, indented to
/// align with the name above it rather than the icon. The time of day isn't shown in the card at
/// all — `DayActivitiesSection` shows it on the timeline instead, aligned with this headline line.
private struct ActivityCard: View {
    let activity: Activity
    /// This activity's TRIMP, from `WeekViewModel.trainingLoad(for:)` — `nil` when it couldn't be
    /// computed, in which case the headline line just omits the number.
    let trainingLoad: Double?
    let onSelect: () -> Void

    /// Matches `DayActivitiesSection`'s time label's top padding, so the label and this card's
    /// headline line land at the same y (see that view's own note on why — deterministic matched
    /// offsets, not `.firstTextBaseline`, given this card's own padding/background/Button nesting).
    static let contentPadding: CGFloat = 12
    /// Fixed so the icon's actual glyph width (which varies per sport) doesn't change where the
    /// second line's indent lands — the second line aligns to this width plus `iconSpacing`, not
    /// to the icon's own measured size.
    private static let iconWidth: CGFloat = 22
    private static let iconSpacing: CGFloat = 8

    private static let loadFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
    private static let measurementFormat = Measurement<UnitLength>.FormatStyle.measurement(width: .abbreviated)

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Self.iconSpacing) {
                    Image(systemName: activity.sport.symbolName)
                        .foregroundStyle(.primary)
                        .frame(width: Self.iconWidth)
                    Text(activity.sport.displayName)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let trainingLoad {
                        Text(trainingLoad.formatted(Self.loadFormat))
                            .foregroundStyle(.secondary)
                    }
                }
                if activity.sport.isEndurance {
                    Text(secondLineText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, Self.iconWidth + Self.iconSpacing)
                }
            }
            .padding(Self.contentPadding)
            .background {
                RoundedRectangle(cornerRadius: timelineCardCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            }
            .contentShape(RoundedRectangle(cornerRadius: timelineCardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "1:30:00 · 8 km" (plus "· 120 m" when the climb exceeds 50m) — duration always shown as
    /// H:MM:SS, distance/climb omitted entirely (not shown as "0 km"/"0 m") when the source
    /// doesn't report one.
    private var secondLineText: String {
        var parts = [Duration.seconds(activity.duration).formatted(.time(pattern: .hourMinuteSecond))]
        if let distanceMeters = activity.distanceMeters {
            parts.append(Measurement(value: distanceMeters, unit: UnitLength.meters).formatted(Self.measurementFormat))
        }
        if let gainMeters = activity.elevation?.gainMeters, gainMeters > 50 {
            parts.append(Measurement(value: gainMeters, unit: UnitLength.meters).formatted(Self.measurementFormat))
        }
        return parts.joined(separator: " · ")
    }
}

/// A planned activity that hasn't been reconciled to a completed one yet, rendered as a dashed,
/// unfilled outline — same card shape as `ActivityCard`, but the absent fill and dashed border are
/// what keep it reading as "not done yet" at a glance (design doc §2.1) rather than a second kind
/// of completed activity. One already matched to a completed activity (`completedActivityID !=
/// nil`) is skipped: the completed activity's own card above already represents it.
private struct PlannedActivityCard: View {
    let plan: PlannedActivity
    let workoutName: String?

    var body: some View {
        if plan.completedActivityID == nil {
            HStack {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                Text(workoutName ?? "Planned workout")
                Spacer()
            }
            .padding(12)
            .foregroundStyle(.secondary)
            .background {
                RoundedRectangle(cornerRadius: timelineCardCornerRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(dash: [4, 3]))
            }
        }
    }
}
