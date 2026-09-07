import SwiftUI
import TrainingCore

/// One day's row group in the week view's day list: a date header, its completed activities, and
/// its planned activities — planned ones rendered visibly distinct (design doc §2.1).
struct DayActivitiesSection: View {
    let day: Date
    let activities: [Activity]
    let plans: [PlannedActivity]
    let workoutName: (PlannedActivity) -> String?

    fileprivate static let headerFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
    fileprivate static let timeFormat = Date.FormatStyle.dateTime.hour().minute()

    var body: some View {
        Section(day.formatted(Self.headerFormat)) {
            if activities.isEmpty && plans.isEmpty {
                Text("Rest day")
                    .foregroundStyle(.secondary)
            }
            ForEach(activities) { activity in
                ActivityRow(activity: activity)
            }
            ForEach(plans, id: \.id) { plan in
                PlannedActivityRow(plan: plan, workoutName: workoutName(plan))
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack {
            Image(systemName: activity.sport.symbolName)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(activity.sport.displayName)
                Text(activity.start, format: DayActivitiesSection.timeFormat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Duration.seconds(activity.duration).formatted(.units(allowed: [.hours, .minutes])))
                .foregroundStyle(.secondary)
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
