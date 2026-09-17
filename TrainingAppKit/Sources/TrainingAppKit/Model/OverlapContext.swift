import Foundation
import TrainingCore

/// A specific overlap pairing for one activity, surfaced in the activity detail sheet (MVP1-63) —
/// see ``WeekViewModel/overlapContext(for:)``.
public struct OverlapContext: Hashable {
    /// What to do about this pair — see ``OverlapRecommendation``.
    public let recommendation: OverlapRecommendation
    /// The other activity in the pair (not the one whose detail sheet this is showing).
    public let otherActivity: Activity
}
