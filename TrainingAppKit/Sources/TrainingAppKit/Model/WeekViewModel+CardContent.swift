import Foundation
import TrainingCore

/// Everything a day-list card shows, bundled per card so `DayActivitiesSection` takes one closure
/// per card kind rather than one per fact.
extension WeekViewModel {
    /// What a completed activity's card shows beyond the activity itself.
    public struct ActivityCardContent: Equatable {
        /// The activity's TRIMP — the headline number (MVP1-41); `nil` when no calculator could score
        /// it, in which case the card omits the number rather than showing a misleading "0".
        public let trainingLoad: Double?
        /// The activity's overlap issue, if any (MVP1-63), shown as a warning badge.
        public let overlapWarning: OverlapRecommendation?
        /// The activity's intensity (MVP2-43), shown as a subdued background tint.
        public let intensity: IntensityAssessment?
        /// What the plan the activity is linked to expected, shown beside and under the actual values.
        public let planned: LinkedPlanExpectation?
    }

    /// What a planned activity's card shows beyond the plan itself.
    public struct PlannedCardContent: Equatable {
        /// The name, sport, expected load and duration or distance (MVP2-37).
        public let summary: PlannedCardSummary
        /// The workout's intended intensity (MVP2-43), shown as the colour of the card's ring marker.
        public let intensity: IntensityAssessment?
        /// Whether the plan's day has passed without a completed activity matching it: drawn as an
        /// outlined card with secondary text and no expected load — planned but didn't happen.
        public let isMissed: Bool
        /// Whether the plan is on the Apple Watch, or why its workout can't go there (MVP2-119);
        /// `nil` for neither, and always `nil` on a missed plan.
        public let watchStatus: PlannedWatchStatus?
    }

    /// A planned card's Apple Watch status (MVP2-119).
    public enum PlannedWatchStatus: Equatable {
        /// The Watch sync put the plan on the Watch: a small Watch mark on the card.
        case onWatch
        /// The plan's workout can't go on the Watch, with the reason, e.g. "Apple Watch doesn't
        /// support this alert for cycling.": a warning line on the card.
        case unsupported(reason: String)
    }

    /// The card content for a completed `activity`.
    public func activityCardContent(for activity: Activity) -> ActivityCardContent {
        ActivityCardContent(
            trainingLoad: trainingLoad(for: activity),
            overlapWarning: overlapWarning(for: activity),
            intensity: intensity(for: activity),
            planned: linkedPlanExpectation(for: activity)
        )
    }

    /// The card content for a planned activity, with `today` deciding whether it was missed.
    public func plannedCardContent(for plan: PlannedActivity, asOf today: Date = .now) -> PlannedCardContent {
        let isMissed = plan.completedActivityID == nil && isPast(plan.date, asOf: today)
        return PlannedCardContent(
            summary: plannedCardSummary(for: plan),
            intensity: intensity(for: plan),
            isMissed: isMissed,
            watchStatus: isMissed ? nil : watchStatus(for: plan)
        )
    }

    /// `plan`'s Apple Watch status (MVP2-119), from what the last Watch sync found: a warning when
    /// its workout can't go on the Watch, else the mark when the sync sent it. `nil` without a sync
    /// or while the athlete has turned sending off (MVP2-118), since the Watch doesn't matter then.
    ///
    /// Two dictionary and set lookups, cheap enough for the card closures the week swipe calls on
    /// every frame; reading the sync's observed properties redraws the cards after each sync.
    func watchStatus(for plan: PlannedActivity) -> PlannedWatchStatus? {
        guard let watchSync, watchSync.isEnabled else { return nil }
        if let reason = watchSync.unsupportedWorkouts[plan.workoutID] {
            return .unsupported(reason: reason)
        }
        return watchSync.sentPlanIDs.contains(plan.id) ? .onWatch : nil
    }
}
