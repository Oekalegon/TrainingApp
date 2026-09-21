import Foundation
import TrainingCore

/// What the activity detail sheet needs to show and change an activity's link to a planned workout
/// (MVP2-42) — see ``WeekViewModel/planLinkContext(for:)``.
public struct PlanLinkContext: Equatable {
    /// One planned workout the activity is, or could be, linked to.
    public struct PlanOption: Identifiable, Equatable {
        /// The plan's id — what ``WeekViewModel/linkActivity(_:toPlan:asOf:)`` takes.
        public let id: UUID
        /// The workout's name, or the sport's when the workout has none or is no longer in the library.
        public let title: String
        /// The workout's headline figure (duration or distance), if known.
        public let extent: WeekViewModel.PlannedCardSummary.Extent?
    }

    /// The plan this activity currently completes, if any.
    public let linkedPlan: PlanOption?
    /// Whether the automatic match had a close runner-up, so the athlete should confirm or correct it
    /// (``TrainingModel/planMatchAmbiguities``).
    public let isAmbiguous: Bool
    /// The other plans the activity could be linked to: same day, not already completed by another
    /// activity. Never includes ``linkedPlan``.
    public let candidates: [PlanOption]
}
