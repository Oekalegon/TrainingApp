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
        /// The workout's intended intensity (MVP2-43), shown in the hatch stripes' colour.
        public let intensity: IntensityAssessment?
        /// Whether the plan's day has passed without a completed activity matching it: drawn as an
        /// outlined card with secondary text and no expected load — planned but didn't happen.
        public let isMissed: Bool
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
        PlannedCardContent(
            summary: plannedCardSummary(for: plan),
            intensity: intensity(for: plan),
            isMissed: plan.completedActivityID == nil && isPast(plan.date, asOf: today)
        )
    }
}
