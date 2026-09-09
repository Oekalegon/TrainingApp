import SwiftUI
import TrainingCore

/// Renders one day's row in the week view's day list (design doc §2.1, MVP1-39): a weekday pill
/// marking its place on the list's vertical timeline, and — beside it — that day's completed and
/// planned activities, planned ones rendered visibly distinct.
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
    let activities: [Activity]
    let plans: [PlannedActivity]
    let workoutName: (PlannedActivity) -> String?
    /// The athlete's timezone — every date here is formatted with this, not the device's default,
    /// so the dates/times shown agree with how `WeekViewModel` grouped them into this day in the
    /// first place.
    let timeZone: TimeZone
    /// Called when a completed activity's row is tapped — `WeekView` presents it in a detail
    /// sheet, not a navigation push, so this hands back the tapped `Activity` rather than this
    /// view building a `NavigationLink` itself.
    let onSelectActivity: (Activity) -> Void

    /// Hour + minute only — the weekday pill already carries the day, so completed activities'
    /// rows only need their time of day.
    fileprivate static func timeFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = timeZone
        return format
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                WeekdayPillView(date: date, isToday: isToday, timeZone: timeZone)
                if showsConnector {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: WeekdayPillView.columnWidth)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(activities) { activity in
                    ActivityRow(activity: activity, timeZone: timeZone, onSelect: { onSelectActivity(activity) })
                }
                ForEach(plans) { plan in
                    PlannedActivityRow(plan: plan, workoutName: workoutName(plan))
                }
            }
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A weekday + day-of-month badge marking one day's position on the day list's vertical timeline
/// (MVP1-39). Highlighted when it's today, so "today" reads at a glance while scrolling.
struct WeekdayPillView: View {
    let date: Date
    let isToday: Bool
    let timeZone: TimeZone

    /// Width of the timeline column this pill sits in — wide enough for the pill's longest
    /// content ("Wed 9" etc.) plus breathing room, so the connector line below it (drawn by
    /// `DayActivitiesSection`, in a column of this same width) stays centered under it.
    static let columnWidth: CGFloat = 60
    private static let height: CGFloat = 24

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
            .font(.system(size: 9))
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .foregroundStyle(isToday ? Color.white : Color.primary)
            .background {
                Capsule().fill(isToday ? Color.accentColor : Color.secondary.opacity(0.12))
            }
    }
}

/// A completed activity — tapping it presents `ActivityDetailView` in a sheet (see `WeekView`'s
/// `.sheet(item: $selectedActivity)`), so this is a plain `Button` rather than a
/// `NavigationLink(value:)`/`navigationDestination` push.
private struct ActivityRow: View {
    let activity: Activity
    let timeZone: TimeZone
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: activity.sport.symbolName)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(activity.sport.displayName)
                        .foregroundStyle(.primary)
                    Text(activity.start, format: DayActivitiesSection.timeFormat(timeZone: timeZone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Duration.seconds(activity.duration).formatted(.units(allowed: [.hours, .minutes])))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A planned activity that hasn't been reconciled to a completed one yet — shown muted/outlined
/// to read clearly as "not done" at a glance. One already matched to a completed activity
/// (`completedActivityID != nil`) is skipped: the completed activity above already represents it.
private struct PlannedActivityRow: View {
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
            .padding(.vertical, 8)
            .foregroundStyle(.secondary)
        }
    }
}
