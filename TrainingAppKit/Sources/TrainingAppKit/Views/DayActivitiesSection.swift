import SwiftUI
import TrainingCore

/// Background for every un-highlighted pill/badge on the day list's timeline — `WeekdayPillView`'s
/// own pill and each `MetricPillView`'s label, so they read as one consistent pill style rather
/// than two independently-tuned ones. Also the timeline connector's own line color, so the line
/// reads as the same visual element as the pills sitting on it rather than an unrelated grey.
///
/// `Color.primary.opacity(_:)`, not a fixed grey: `.primary` is already black in light mode and
/// white in dark mode, so this overlay is "slightly darker than whatever's behind it" in light
/// mode and "slightly lighter" in dark mode for free, without a separate dark-mode-reversed value
/// to keep in sync. Not `private`: `WeekView` reuses it for the trailing filler segment that
/// extends the timeline past the last day down to the bottom of the week view.
let unhighlightedPillBackground = Color.primary.opacity(0.06)

/// The week view's own background — a light (dark in dark mode) grey, distinct from the plain
/// system background so `unhighlightedPillBackground` above reads as "recessed" relative to it and
/// `ActivityCard`'s own background reads as "elevated". Also used as an opaque backing layer behind
/// the weekday pill and each activity's time label, so the timeline's line (drawn behind everything
/// as one continuous background) is fully hidden where a pill or time label sits on it, rather than
/// showing through. Not `private`: `WeekView` sets it as the day list's actual background too.
#if os(iOS)
let weekViewBackground = Color(.systemGroupedBackground)
#else
// This view only ever ships on iOS; the fallback exists purely so TrainingAppKit (built for both
// iOS and macOS, per Package.swift) still compiles on macOS, e.g. for host-side tooling/tests.
let weekViewBackground = Color(white: 0.93)
#endif

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
    /// Whether to draw the timeline connector below this row's pill. `WeekView` passes `true` for
    /// every day, including the last, and appends its own trailing filler segment after the last
    /// day so the line continues past it to the bottom of the week view rather than stopping right
    /// at the final pill — this parameter exists so a caller that doesn't want that (a future
    /// non-`WeekView` use of this type, say) still can.
    let showsConnector: Bool
    /// This day's CTL/ATL/TSB, shown as pills beside the weekday pill (MVP1-40) — `nil` before
    /// the first load, in which case no pill row renders (rather than a row of placeholder zeros).
    let metrics: FitnessMetrics?
    let activities: [Activity]
    /// This day's plans not yet matched to a completed activity — see `WeekViewModel.pendingPlans(on:)`.
    let plans: [PlannedActivity]
    /// Everything an activity's card shows beyond the activity itself — TRIMP, overlap badge,
    /// intensity, the linked plan's expected values — see `WeekViewModel.activityCardContent(for:)`.
    let activityCard: (Activity) -> WeekViewModel.ActivityCardContent
    /// Everything a planned activity's card shows beyond the plan itself — its summary (MVP2-37),
    /// intensity, and whether it was missed — see `WeekViewModel.plannedCardContent(for:asOf:)`.
    let plannedCard: (PlannedActivity) -> WeekViewModel.PlannedCardContent
    /// The athlete's timezone — every date here is formatted with this, not the device's default,
    /// so the dates/times shown agree with how `WeekViewModel` grouped them into this day in the
    /// first place.
    let timeZone: TimeZone
    /// Called when a completed activity's row is tapped — `WeekView` presents it in a detail
    /// sheet, not a navigation push, so this hands back the tapped `Activity` rather than this
    /// view building a `NavigationLink` itself.
    let onSelectActivity: (Activity) -> Void
    /// Called when a planned activity's card is tapped (MVP2-38) — `WeekView` presents the
    /// planned-workout detail sheet, the same hand-back-the-value pattern as `onSelectActivity`.
    let onSelectPlan: (PlannedActivity) -> Void
    /// Called when one of this row's Load/Fitness/Fatigue/Form pills is tapped (MVP1-45) —
    /// `WeekView` opens the fitness metrics detail view showing just that metric's explanation.
    let onSelectMetric: (TrainingMetricKind) -> Void
    /// Whether the "add" button below is enabled — `false` for a day in the past (MVP2-15):
    /// planning a workout or race for a day that's already happened doesn't make sense, but the
    /// button itself still shows (rather than disappearing) since a past day is also where a
    /// future "log an activity that wasn't auto-imported" entry point would belong.
    let canAddWorkout: Bool
    /// Called when this day's "add" button is tapped (MVP2-15, MVP2-17, MVP2-22) — `WeekView`
    /// presents `AddEntrySheet` defaulted to `date`, which offers the planned-workout/race choice
    /// itself via its own type picker rather than this button needing a dialog of its own.
    let onAddEntry: () -> Void

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
                    DayMetricsPillRow(metrics: metrics, showsOnlyForm: activities.isEmpty, onSelectMetric: onSelectMetric)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Spacer()
                }
                Button(action: onAddEntry) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canAddWorkout)
                .opacity(canAddWorkout ? 1 : 0.35)
                .accessibilityLabel("Add")
            }

            ForEach(activities) { activity in
                // Tighter spacing than the weekday-pill/metrics row above: the time label and its
                // card are one paired unit on the timeline, not two independent elements, so they
                // should read closer together than that row's pill-vs-metrics pairing does.
                HStack(alignment: .top, spacing: 4) {
                    // `.top` plus this label's own top padding matching the card's — deterministic,
                    // not reliant on SwiftUI's baseline-guide propagation through the card's own
                    // padding/background/Button wrapping (same reasoning as the weekday-pill/
                    // metrics-row alignment above).
                    Text(activity.start, format: Self.timeFormat(timeZone: timeZone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 1)
                        .padding(.horizontal, 4)
                        // Opaque, so the timeline line behind it (see `showsConnector`'s
                        // `.background` below) is fully interrupted here rather than showing
                        // through the label — same reasoning as `WeekdayPillView`'s own backing.
                        .background(weekViewBackground)
                        .frame(width: WeekdayPillView.columnWidth)
                        .padding(.top, TimelineCardStyle.contentPadding)
                    ActivityCard(
                        activity: activity,
                        content: activityCard(activity),
                        onSelect: { onSelectActivity(activity) }
                    )
                }
            }
            // `plans` is `WeekViewModel.pendingPlans(on:)` — already minus plans a completed
            // activity's card above represents, so no empty row is laid out for those.
            ForEach(plans) { plan in
                HStack(alignment: .top, spacing: 4) {
                    // No time shown here — a `PlannedActivity` only carries a calendar day, not a
                    // time of day — but the column still needs to hold its width so the card below
                    // starts at the same x as the activity cards above it.
                    Color.clear.frame(width: WeekdayPillView.columnWidth, height: 0)
                    PlannedActivityCard(
                        plan: plan,
                        content: plannedCard(plan),
                        onSelect: { onSelectPlan(plan) }
                    )
                }
            }
        }
        .padding(.bottom, 20)
        // The continuous timeline line, drawn once behind the whole day rather than per row: a
        // per-row line (as MVP1-39 used, back when this view had only one row) can't span multiple
        // sibling `HStack`s the way a single background can. It's drawn behind the weekday pill and
        // every time label too, but each of those has its own opaque `weekViewBackground` backing layer
        // (see `WeekdayPillView` and the time label below) that fully covers the line where it
        // passes underneath, rather than letting the line's translucent color show through/blend
        // with theirs.
        .background(alignment: .topLeading) {
            if showsConnector {
                Rectangle()
                    .fill(unhighlightedPillBackground)
                    .frame(width: WeekdayPillView.connectorLineWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, WeekdayPillView.connectorLineLeadingPadding)
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

    /// Width of the timeline connector line (`DayActivitiesSection`'s own connector and
    /// `WeekView`'s trailing filler that extends it past the last day both draw a line this wide).
    static let connectorLineWidth: CGFloat = 2
    /// Leading inset that centers a `connectorLineWidth`-wide line under this pill's column — the
    /// single source both connector-drawing call sites use, so the two segments can't drift apart
    /// and stop lining up if `columnWidth`/`connectorLineWidth` ever change.
    static let connectorLineLeadingPadding = columnWidth / 2 - connectorLineWidth / 2

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
                // Opaque `weekViewBackground` first, so the timeline line drawn behind this pill (see
                // `DayActivitiesSection`'s `showsConnector` background) is fully hidden rather than
                // showing through — `unhighlightedPillBackground` alone is translucent (12%
                // opacity) and wouldn't block it on its own. `isToday`'s solid `accentColor` would
                // already fully cover the line without this, but it's applied unconditionally so
                // this doesn't silently break if that color ever becomes translucent too.
                Capsule().fill(weekViewBackground)
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
    /// Called with the tapped pill's metric (MVP1-45).
    let onSelectMetric: (TrainingMetricKind) -> Void

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
                MetricPillView(kind: .load, value: metrics.load.formatted(Self.unsignedFormat), onSelect: onSelectMetric)
                Spacer().frame(width: Self.loadGroupSpacing)
                MetricPillView(kind: .fitness, value: metrics.ctl.formatted(Self.unsignedFormat), onSelect: onSelectMetric)
                Spacer().frame(width: Self.metricSpacing)
                MetricPillView(kind: .fatigue, value: metrics.atl.formatted(Self.unsignedFormat), onSelect: onSelectMetric)
                Spacer().frame(width: Self.metricSpacing)
            }
            MetricPillView(kind: .form, value: metrics.tsb.formatted(Self.signedFormat), onSelect: onSelectMetric)
        }
    }
}

/// One metric's plain value followed by its icon pill, e.g. "42" then a "battery.100" pill — only
/// the icon sits in a pill (grey, matching `WeekdayPillView`'s own). The icon is plain `.primary`,
/// not tinted per metric — matching `FitnessChartView`'s legend (which pairs the same icon with
/// its series color) would need the value's own color scale threaded down here for no real gain,
/// since the icon shape alone already disambiguates Load/Fitness/Fatigue/Form at this size. The
/// value carries no pill/background at all, so it doesn't compete visually with the icon. Tapping
/// anywhere on the pill (MVP1-45) opens the fitness metrics detail view for just this metric.
private struct MetricPillView: View {
    let kind: TrainingMetricKind
    let value: String
    let onSelect: (TrainingMetricKind) -> Void

    var body: some View {
        Button {
            onSelect(kind)
        } label: {
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
        }
        // Plain, not the default button chrome (tint color, press-state dimming beyond what a
        // small pill needs) — this is a small inline value/icon, not a call-to-action button.
        .buttonStyle(.plain)
        // Without this, VoiceOver reads the icon's own SF Symbol name ("battery 100 percent")
        // instead of what it actually represents here — combining the two elements into one and
        // giving it an explicit label makes this read as "Fitness, 42" instead of two
        // disconnected fragments ("42", then "battery 100 percent").
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.name), \(value)")
        .accessibilityHint("Opens an explanation of \(kind.name)")
    }
}
