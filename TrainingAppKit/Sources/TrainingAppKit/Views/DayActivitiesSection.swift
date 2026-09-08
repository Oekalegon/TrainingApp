import SwiftUI
import TrainingCore

/// One day's row group in the week view's day list: a date header, its completed activities, and
/// its planned activities — planned ones rendered visibly distinct (design doc §2.1).
///
/// Deliberately holds no local `@State`: `WeekView` recreates the `List` a given week's rows live
/// in (via `.id(...)` on that week's first date) whenever the displayed week changes, so a swipe
/// resets scroll position instead of leaking it into the next week — any local state added here
/// (an expand/collapse toggle, say) would be silently reset by the same mechanism. If this type
/// ever needs its own state, that interaction needs accounting for first.
struct DayActivitiesSection: View {
    let day: Date
    let activities: [Activity]
    let plans: [PlannedActivity]
    let workoutName: (PlannedActivity) -> String?
    /// The athlete's timezone — every date here is formatted with this, not the device's default,
    /// so headers/times agree with how `WeekViewModel` grouped them into this day in the first
    /// place.
    let timeZone: TimeZone

    fileprivate static func headerFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        format.timeZone = timeZone
        return format
    }

    fileprivate static func timeFormat(timeZone: TimeZone) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = timeZone
        return format
    }

    var body: some View {
        Section(day.formatted(Self.headerFormat(timeZone: timeZone))) {
            if activities.isEmpty && plans.isEmpty {
                Text("Rest day")
                    .foregroundStyle(.secondary)
            }
            ForEach(activities) { activity in
                ActivityRow(activity: activity, timeZone: timeZone)
            }
            ForEach(plans) { plan in
                PlannedActivityRow(plan: plan, workoutName: workoutName(plan))
            }
        }
    }
}

/// A completed activity — a `NavigationLink(value:)` so `WeekView`'s `navigationDestination(for:)`
/// can push `ActivityDetailView` without this row needing to know how to build one itself.
private struct ActivityRow: View {
    let activity: Activity
    let timeZone: TimeZone

    var body: some View {
        NavigationLink(value: activity) {
            HStack {
                Image(systemName: activity.sport.symbolName)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(activity.sport.displayName)
                    Text(activity.start, format: DayActivitiesSection.timeFormat(timeZone: timeZone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Duration.seconds(activity.duration).formatted(.units(allowed: [.hours, .minutes])))
                    .foregroundStyle(.secondary)
            }
        }
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
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
