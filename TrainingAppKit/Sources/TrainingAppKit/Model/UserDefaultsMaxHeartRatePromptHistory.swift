import Foundation

/// ``MaxHeartRatePromptHistory`` stored in `UserDefaults`.
///
/// Local to this device, not synced through CloudKit: on a new device the history scan runs again,
/// but a declined activity can only come back if its peak still beats the current max.
@MainActor
public final class UserDefaultsMaxHeartRatePromptHistory: MaxHeartRatePromptHistory {
    private static let declinedKey = "maxHeartRate.declinedActivityIDs"
    private static let scannedKey = "maxHeartRate.hasScannedHistory"
    private let defaults: UserDefaults

    /// Creates a history backed by `defaults`.
    ///
    /// - Parameter defaults: Where to store the history; defaults to `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var declinedActivityIDs: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Self.declinedKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { defaults.set(newValue.map(\.uuidString).sorted(), forKey: Self.declinedKey) }
    }

    public var hasScannedHistory: Bool {
        get { defaults.bool(forKey: Self.scannedKey) }
        set { defaults.set(newValue, forKey: Self.scannedKey) }
    }
}
