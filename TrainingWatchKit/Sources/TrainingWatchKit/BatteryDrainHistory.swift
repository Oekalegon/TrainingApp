import Foundation

/// The battery drain of the athlete's own earlier runs, kept on the watch (WATCH-119): the next run's
/// forecast starts from their median instead of a typical rate. Pure, so it is tested without a run.
public struct BatteryDrainHistory: Codable, Sendable, Hashable {
    /// How many runs are kept; older ones fall away, since the drain changes with the watch's age and settings.
    public static let capacity = 10
    /// How many runs it takes before the history is trusted over the typical rate.
    public static let minimumRuns = 2
    /// How long a run has to be for its drain to count, in seconds.
    public static let minimumDuration: TimeInterval = 15 * 60

    /// The drain per hour of each kept run, as a share of the full charge, oldest first.
    public private(set) var drains: [Double] = []

    public init() {}

    /// The drain per hour of a run, from its battery readings; `nil` when the run was too short, the
    /// level did not drop by a step (so it says too little), or it rose (charging).
    ///
    /// - Parameter readings: The readings of the run, oldest first.
    public static func drain(of readings: [BatteryForecast.Reading]) -> Double? {
        guard let first = readings.first, let last = readings.last else { return nil }
        let span = last.time - first.time, drop = first.level - last.level
        guard span >= minimumDuration, drop >= 0.01 else { return nil }
        return drop / span * 3600
    }

    /// Keeps the drain of a finished run, if its readings give one.
    public mutating func add(readings: [BatteryForecast.Reading]) {
        guard let drain = Self.drain(of: readings) else { return }
        drains = Array((drains + [drain]).suffix(Self.capacity))
    }

    /// The median drain per hour of the kept runs, or `nil` while there are too few.
    public var typicalDrain: Double? {
        guard drains.count >= Self.minimumRuns else { return nil }
        let sorted = drains.sorted(), middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}

/// Keeps the ``BatteryDrainHistory`` in the watch's `UserDefaults`.
public struct BatteryDrainStore: Sendable {
    private let cache: JSONDefaultsCache<BatteryDrainHistory>

    public init(defaults: UserDefaults = .standard) {
        cache = JSONDefaultsCache(key: "batteryDrain.v1", defaults: defaults)
    }

    /// The kept history, empty when there is none yet.
    public func load() -> BatteryDrainHistory { cache.load() ?? BatteryDrainHistory() }

    /// Adds a finished run to the history.
    public func record(readings: [BatteryForecast.Reading]) {
        var history = load()
        history.add(readings: readings)
        cache.save(history)
    }
}
