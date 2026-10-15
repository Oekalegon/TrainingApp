import Foundation

/// A throwaway `UserDefaults` suite for one test, removed when the test's suite instance goes away,
/// so nothing a test writes (the Watch permission banner's dismissal, MVP2-117) leaks into another
/// test or into `UserDefaults.standard`.
///
/// Held as a stored property of a test suite: Swift Testing makes a new suite instance for every
/// test, so each test gets its own suite and it's cleaned up when that test finishes.
final class ScratchDefaults {
    let defaults: UserDefaults
    private let suiteName: String

    init() {
        suiteName = "TrainingAppKitTests.\(UUID().uuidString)"
        // Only `nil` for the global domain or the app's own bundle id, which a UUID name never is.
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
