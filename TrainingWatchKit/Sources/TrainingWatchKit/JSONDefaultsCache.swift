import Foundation

/// Keeps one `Codable` value in `UserDefaults` as JSON: the watch's copy of what the phone sent,
/// so a run can start with the phone out of reach (the watch app has to work on its own during a run).
struct JSONDefaultsCache<Value: Codable & Sendable>: Sendable {
    private let key: String

    // `UserDefaults` is thread-safe but not `Sendable`; the cache only reads and writes one key.
    private nonisolated(unsafe) let defaults: UserDefaults

    init(key: String, defaults: UserDefaults) {
        self.key = key
        self.defaults = defaults
    }

    /// The cached value, or `nil` when none was saved yet or it can't be read.
    func load() -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    /// Replaces the cached value.
    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
