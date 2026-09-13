import Foundation

/// How many activities the import that just finished found overlap issues among (MVP1-63) — see
/// ``WeekViewModel/overlapImportSummary``.
public struct OverlapImportSummary: Equatable {
    public let activityCount: Int
}
