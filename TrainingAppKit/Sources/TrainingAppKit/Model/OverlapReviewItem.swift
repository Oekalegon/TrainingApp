import Foundation
import TrainingCore

/// One row in the overlap-review sheet the import summary banner opens onto (MVP1-63) — see
/// ``WeekViewModel/overlapReviewItems``.
public struct OverlapReviewItem: Identifiable, Hashable {
    public var id: UUID { activity.id }
    public let activity: Activity
    public let recommendation: OverlapRecommendation
    /// The row's headline (MVP2-152), as ``WeekViewModel/activityTitle(for:)`` gives it.
    public let title: String
}
