import Foundation
import Observation

/// One value a run screen can show (WATCH-109). The raw value is what travels between the phone and
/// the watch, so it stays stable.
public enum RunMetric: String, Sendable, Codable, CaseIterable, Hashable {
    case totalTime, distance, heartRate, currentPace, averagePace
}

/// One thing on a run screen: today a metric, later widgets such as the zone bar (WATCH-132). Each
/// has a ``height`` in units, and a screen holds ``RunScreen/capacity`` of them.
public enum RunScreenItem: Sendable, Hashable, Codable {
    case metric(RunMetric)

    /// The height in units: a plain metric is 1, which is a row of the standard screen.
    public var height: Int {
        switch self {
        case .metric: 1
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, id }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "metric":
            guard let metric = RunMetric(rawValue: try container.decode(String.self, forKey: .id)) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "unknown metric")
            }
            self = .metric(metric)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown item")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .metric(let metric):
            try container.encode("metric", forKey: .kind)
            try container.encode(metric.rawValue, forKey: .id)
        }
    }
}

/// A stack of items that fills one data screen of a run, drawn from the bottom up.
public struct RunScreen: Sendable, Hashable, Codable, Identifiable {
    /// The height of a screen in units: six rows fit an Ultra (five on the other watches, which drop
    /// the first item, so the most important one goes last).
    public static let capacity = 6

    public var id: String
    public var items: [RunScreenItem]

    public init(id: String, items: [RunScreenItem]) {
        self.id = id
        self.items = items
    }

    /// The metrics among the items, in order.
    public var metrics: [RunMetric] {
        items.compactMap { if case .metric(let metric) = $0 { metric } else { nil } }
    }

    /// The units the items take.
    public var units: Int { items.reduce(0) { $0 + $1.height } }

    /// Whether the items fit the screen.
    public var fits: Bool { units <= Self.capacity }

    private enum CodingKeys: String, CodingKey { case id, items }

    /// An item the watch doesn't know (a phone newer than the watch) is dropped, and items past the
    /// capacity are cut from the top, so a set from a newer phone can't break a run.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let items = try container.decode([Lossy<RunScreenItem>].self, forKey: .items).compactMap(\.value)
        self.items = Self.fitted(items)
    }

    /// `items` with the first ones left out until they fit.
    static func fitted(_ items: [RunScreenItem]) -> [RunScreenItem] {
        var items = items
        while items.reduce(0, { $0 + $1.height }) > capacity { items.removeFirst() }
        return items
    }
}

/// A named list of screens the crown turns through, and the one a run opens on.
public struct RunScreenSet: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var screens: [RunScreen]
    /// The id of the screen the run opens on; the first screen when `nil` or not in the set.
    public var startScreenID: String?

    public init(id: String, name: String, screens: [RunScreen], startScreenID: String? = nil) {
        self.id = id
        self.name = name
        self.screens = screens
        self.startScreenID = startScreenID
    }

    /// The index of the screen the run opens on.
    public var startIndex: Int {
        startScreenID.flatMap { id in screens.firstIndex { $0.id == id } } ?? 0
    }

    private enum CodingKeys: String, CodingKey { case id, name, screens, startScreenID }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        screens = try container.decode([Lossy<RunScreen>].self, forKey: .screens).compactMap(\.value).filter { !$0.items.isEmpty }
        startScreenID = try container.decodeIfPresent(String.self, forKey: .startScreenID)
    }

    /// Today's standard screen: all five metrics.
    public static let freeRunDefault = RunScreenSet(
        id: "default.freeRun", name: "Free run",
        screens: [RunScreen(id: "standard", items: RunMetric.allCases.map(RunScreenItem.metric))])

    /// The default for a workout. For now the same screen; the zone dial is added under it by the
    /// watch app until it is a set of widgets (WATCH-132).
    public static let workoutDefault = RunScreenSet(
        id: "default.workout", name: "Workout",
        screens: [RunScreen(id: "standard", items: RunMetric.allCases.map(RunScreenItem.metric))])
}

/// What the phone sends: the set for a free run and the set for a workout. Sets linked to workout
/// templates are added by WATCH-133.
public struct RunScreenConfig: Sendable, Hashable, Codable {
    public var freeRun: RunScreenSet
    public var workout: RunScreenSet

    public init(freeRun: RunScreenSet = .freeRunDefault, workout: RunScreenSet = .workoutDefault) {
        self.freeRun = freeRun
        self.workout = workout
    }

    public static let `default` = RunScreenConfig()

    private enum CodingKeys: String, CodingKey { case freeRun, workout }

    /// A set that is missing or empty after decoding is the default one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        freeRun = Self.usable((try? container.decodeIfPresent(RunScreenSet.self, forKey: .freeRun)) ?? nil, or: .freeRunDefault)
        workout = Self.usable((try? container.decodeIfPresent(RunScreenSet.self, forKey: .workout)) ?? nil, or: .workoutDefault)
    }

    private static func usable(_ set: RunScreenSet?, or fallback: RunScreenSet) -> RunScreenSet {
        guard let set, !set.screens.isEmpty else { return fallback }
        return set
    }
}

/// Decodes an element or yields `nil` for one that can't be read, so one bad element doesn't lose the array.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

/// Keeps the last screens the watch received, so a run can start with the phone out of reach.
public struct RunScreenCache: Sendable {
    private let cache: JSONDefaultsCache<RunScreenConfig>

    public init(defaults: UserDefaults = .standard) {
        cache = JSONDefaultsCache(key: "watchScreens.v1", defaults: defaults)
    }

    public func load() -> RunScreenConfig? { cache.load() }
    public func save(_ config: RunScreenConfig) { cache.save(config) }
}

/// The screens the watch app draws: from the cache at launch, updated as the phone sends new ones. A
/// change reaches the next run (the run's pages read the set when they are built).
@MainActor
@Observable
public final class RunScreenStore {
    public private(set) var config: RunScreenConfig
    private let cache: RunScreenCache

    public init(cache: RunScreenCache = RunScreenCache()) {
        self.cache = cache
        config = cache.load() ?? .default
    }

    /// The set for a run: a planned workout's or a free run's.
    public func set(forWorkout isWorkout: Bool) -> RunScreenSet {
        isWorkout ? config.workout : config.freeRun
    }

    public func update(_ config: RunScreenConfig) {
        guard config != self.config else { return }
        self.config = config
        cache.save(config)
    }
}
