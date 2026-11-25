import Foundation

/// What can explain a run's drain and is known when it starts (WATCH-119). Few on purpose: each factor
/// splits the few runs there are, so only those that matter and that the watch can read itself are kept.
/// The outdoor temperature isn't one: the watch can't read it, and the weather HealthKit adds to a
/// workout comes after the run.
public struct BatteryDrainFactors: Codable, Sendable, Hashable {
    /// Whether the watch was in Low Power Mode, which dims the display and slows its work.
    public var lowPowerMode: Bool
    /// Whether cues may sound from the watch's speaker, not only through earbuds.
    public var speakerSound: Bool

    public init(lowPowerMode: Bool = false, speakerSound: Bool = false) {
        self.lowPowerMode = lowPowerMode
        self.speakerSound = speakerSound
    }
}

/// How much to trust a drain estimate.
public enum BatteryDrainConfidence: Int, Comparable, Sendable {
    /// Few runs, or runs that differ a lot, or none like this one.
    case low
    case medium
    case high

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The battery drain of the athlete's own earlier runs and what could explain it, kept on the watch
/// (WATCH-119): the next run's forecast starts from the median of the runs like it (the same factors),
/// or of all runs while too few are alike. Pure, so it is tested without a run.
public struct BatteryDrainHistory: Codable, Sendable, Hashable {
    /// One finished run.
    public struct Run: Codable, Sendable, Hashable {
        /// Its drain per hour, as a share of the full charge.
        public let drainPerHour: Double
        public let factors: BatteryDrainFactors
    }

    /// A starting drain and how far to trust it.
    public struct Estimate: Sendable, Hashable {
        public let drainPerHour: Double
        public let confidence: BatteryDrainConfidence
    }

    /// How many runs are kept; older ones fall away, since the drain changes with the watch's age and settings.
    public static let capacity = 10
    /// How many runs it takes before the history is trusted over the typical rate.
    public static let minimumRuns = 2
    /// How long a run has to be for its drain to count, in seconds.
    public static let minimumDuration: TimeInterval = 15 * 60

    /// The kept runs, oldest first.
    public private(set) var runs: [Run] = []

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

    /// Keeps a finished run, if its readings give a drain.
    public mutating func add(readings: [BatteryForecast.Reading], factors: BatteryDrainFactors = BatteryDrainFactors()) {
        guard let drain = Self.drain(of: readings) else { return }
        runs = Array((runs + [Run(drainPerHour: drain, factors: factors)]).suffix(Self.capacity))
    }

    /// The drain to start a run with these factors from: the median of earlier runs with the same
    /// factors, or of all runs while fewer than ``minimumRuns`` are alike (never better than low
    /// confidence then); `nil` while there are too few runs at all.
    public func estimate(for factors: BatteryDrainFactors) -> Estimate? {
        let alike = runs.filter { $0.factors == factors }
        let used = alike.count >= Self.minimumRuns ? alike : runs
        guard used.count >= Self.minimumRuns else { return nil }
        let drains = used.map(\.drainPerHour).sorted()
        let middle = drains.count / 2
        let median = drains.count % 2 == 1 ? drains[middle] : (drains[middle - 1] + drains[middle]) / 2
        let spread = median > 0 ? (drains[drains.count - 1] - drains[0]) / median : 1
        var confidence: BatteryDrainConfidence =
            used.count >= 5 && spread < 0.3 ? .high : used.count >= 3 && spread < 0.6 ? .medium : .low
        if alike.count < Self.minimumRuns { confidence = .low }
        return Estimate(drainPerHour: median, confidence: confidence)
    }
}

/// Keeps the ``BatteryDrainHistory`` in the watch's `UserDefaults`.
public struct BatteryDrainStore: Sendable {
    private let cache: JSONDefaultsCache<BatteryDrainHistory>

    public init(defaults: UserDefaults = .standard) {
        cache = JSONDefaultsCache(key: "batteryDrain.v2", defaults: defaults)
    }

    /// The kept history, empty when there is none yet.
    public func load() -> BatteryDrainHistory { cache.load() ?? BatteryDrainHistory() }

    /// Adds a finished run to the history.
    public func record(readings: [BatteryForecast.Reading], factors: BatteryDrainFactors) {
        var history = load()
        history.add(readings: readings, factors: factors)
        cache.save(history)
    }
}
