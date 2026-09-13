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

/// One row in the overlap-review sheet the import summary banner opens onto (MVP1-63) — see
/// ``WeekViewModel/overlapReviewItems``.
public struct OverlapReviewItem: Identifiable, Hashable {
    public var id: UUID { activity.id }
    public let activity: Activity
    public let recommendation: OverlapRecommendation
}

/// How many activities the import that just finished found overlap issues among (MVP1-63) — see
/// ``WeekViewModel/overlapImportSummary``.
public struct OverlapImportSummary: Equatable {
    public let activityCount: Int
}
