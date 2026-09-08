import SwiftUI
import TrainingCore

/// Renders one day's rows in the week view's day list: its completed activities and its planned
/// activities — planned ones rendered visibly distinct (design doc §2.1).
///
/// Contributes nothing at all for a day with neither (MVP1-20): no section header, no "rest day"
/// placeholder row, so a week with only a couple of activities doesn't fill the list with empty
/// scaffolding for the other five days. Each surviving row shows its own date/time, since there's
/// no per-day header left to carry that context.
///
/// Deliberately holds no local `@State`: `WeekView` recreates the scroll view a given week's rows
/// live in (via `.id(...)` on that week's first date) whenever the displayed week changes, so a
/// swipe resets scroll position instead of leaking it into the next week — any local state added
/// here (an expand/collapse toggle, say) would be silently reset by the same mechanism. If this
/// type ever needs its own state, that interaction needs accounting for first.
struct DayActivitiesSection: View {
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

    /// Weekday + day + month, no time — used for planned activities, which only carry a calendar
    /// day (`PlannedActivity.date`), not a time of day.
    fileprivate static func dateFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        format.timeZone = timeZone
        return format
    }

    /// `dateFormat` plus hour/minute — used for completed activities, which have a real start time.
    fileprivate static func dateTimeFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .hour().minute()
        format.timeZone = timeZone
        return format
    }

    var body: some View {
        ForEach(activities) { activity in
            ActivityRow(activity: activity, timeZone: timeZone, onSelect: { onSelectActivity(activity) })
        }
        ForEach(plans) { plan in
            PlannedActivityRow(plan: plan, workoutName: workoutName(plan), timeZone: timeZone)
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
                    Text(activity.start, format: DayActivitiesSection.dateTimeFormat(timeZone: timeZone))
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
    let timeZone: TimeZone

    var body: some View {
        if plan.completedActivityID == nil {
            HStack {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(workoutName ?? "Planned workout")
                    Text(plan.date, format: DayActivitiesSection.dateFormat(timeZone: timeZone))
                        .font(.caption)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .foregroundStyle(.secondary)
        }
    }
}
