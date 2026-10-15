import Foundation

/// What the athlete has already said about max heart rate suggestions (MVP2-56), so the week view
/// doesn't ask the same question twice.
///
/// A seam rather than `UserDefaults` directly, so `WeekViewModel`'s tests can use an in-memory
/// record. The app uses ``UserDefaultsMaxHeartRatePromptHistory``.
@MainActor
public protocol MaxHeartRatePromptHistory: AnyObject {
    /// Activities whose suggestion the athlete declined. They're never suggested again; a later,
    /// different activity that beats the max still is.
    var declinedActivityIDs: Set<UUID> { get set }
    /// Whether the one-time scan of the last 12 months of activities has completed.
    var hasScannedHistory: Bool { get set }
}
