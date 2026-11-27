import Foundation
import Observation

/// One value a run screen can show (WATCH-109). The raw value is what travels between the phone and
/// the watch, so it never changes and is never reused.
public enum RunMetric: String, Sendable, Codable, CaseIterable, Hashable {
    case totalTime, distance, heartRate, currentPace, averagePace
    // Added with the catalogue (WATCH-135). Older sets never hold them.
    /// The mean heart rate of the run so far.
    case averageHeartRate
    /// The highest heart rate of the run so far.
    case maxHeartRate
    /// The altitude from the GPS.
    case altitude
    /// The metres climbed so far.
    case elevationGain
    /// The slope of the last stretch, in percent.
    case grade
    /// The time left in the planned workout; only with steps.
    case timeRemaining
    /// The time of day the planned workout should end at; only with steps.
    case finishTime
    /// Which step it is, "3/8", or the interval of a repeated block; only with steps.
    case stepNumber
    /// The time since the current step began; only with steps.
    case stepTime
    /// The distance since the current step began; only with steps.
    case stepDistance
    /// The time the run has spent in the heart-rate zone it is in now.
    case timeInZone
    /// The time since the heart rate came into the zone it is in now.
    case timeSinceZoneEntry

    /// The five metrics the standard screens have always shown, in their order.
    public static let standard: [RunMetric] = [.totalTime, .distance, .heartRate, .currentPace, .averagePace]

    /// Whether the metric means something only in a planned workout's steps.
    public var requiresSteps: Bool { self == .timeRemaining || self == .finishTime || self == .stepNumber || self == .stepTime || self == .stepDistance }
}

/// A widget a run screen can hold (WATCH-132): something taller or richer than a metric's value.
public enum RunWidget: String, Sendable, Codable, CaseIterable, Hashable {
    /// The zones on one line with the heart rate's place (`ZoneDialBar`); height 2.
    case zoneBar
    /// The battery's charge and forecast with its bar; height 1.
    case battery
    /// The step's time or distance left, with which step it is; only for a planned workout; height 1.
    case stepCountdown
    /// The time spent in each zone so far, as bars; height 2.
    case zoneHistogram
    /// The pace against the step's pace target, drawn like the zone bar; only for a planned workout, and only
    /// while the step has a pace target (WATCH-135); height 2.
    case paceBar

    /// The height in units.
    public var height: Int {
        switch self {
        case .zoneBar, .zoneHistogram, .paceBar: 2
        case .battery, .stepCountdown: 1
        }
    }

    /// Whether the widget means something only in a planned workout's steps.
    public var requiresSteps: Bool { self == .stepCountdown || self == .paceBar }
}

/// One thing on a run screen: a metric or a widget. Each has a ``height`` in units, and a screen holds
/// ``RunScreen/capacity`` of them.
public enum RunScreenItem: Sendable, Hashable, Codable {
    case metric(RunMetric)
    case widget(RunWidget)
    /// A reading the watch collects, with one of its statistics (WATCH-135).
    case measure(RunQuantity, RunStatistic, RunScope)
    /// What a step or a split adds up: its time, distance or climb (WATCH-135).
    case span(RunSpanKind, RunScope)

    /// The height in units: a plain metric is 1, which is a row of the standard screen.
    public var height: Int {
        switch self {
        case .metric: 1
        case .widget(let widget): widget.height
        case .measure, .span: 1
        }
    }

    /// Whether the item means something only in a planned workout's steps.
    public var requiresSteps: Bool {
        switch self {
        case .widget(let widget): widget.requiresSteps
        case .metric(let metric): metric.requiresSteps
        case .measure(_, _, let scope), .span(_, let scope): scope.requiresSteps
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, id }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        switch try container.decode(String.self, forKey: .kind) {
        case "metric":
            guard let metric = RunMetric(rawValue: id) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "unknown metric")
            }
            self = .metric(metric)
        case "widget":
            guard let widget = RunWidget(rawValue: id) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "unknown widget")
            }
            self = .widget(widget)
        case "measure":
            // "cadence.average" is over the whole run; "cadence.average.step" names the scope.
            let parts = id.split(separator: ".").map(String.init)
            guard (2...3).contains(parts.count), let quantity = RunQuantity(rawValue: parts[0]),
                  let statistic = RunStatistic(rawValue: parts[1]),
                  let scope = parts.count == 3 ? RunScope(rawValue: parts[2]) : RunScope.run else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "unknown measure")
            }
            self = .measure(quantity, statistic, scope)
        case "span":
            let parts = id.split(separator: ".").map(String.init)
            guard parts.count == 2, let kind = RunSpanKind(rawValue: parts[0]), let scope = RunScope(rawValue: parts[1]), scope != .run else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "unknown span")
            }
            self = .span(kind, scope)
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
        case .widget(let widget):
            try container.encode("widget", forKey: .kind)
            try container.encode(widget.rawValue, forKey: .id)
        case .measure(let quantity, let statistic, let scope):
            try container.encode("measure", forKey: .kind)
            let name = "\(quantity.rawValue).\(statistic.rawValue)"
            try container.encode(scope == .run ? name : name + ".\(scope.rawValue)", forKey: .id)
        case .span(let kind, let scope):
            try container.encode("span", forKey: .kind)
            try container.encode("\(kind.rawValue).\(scope.rawValue)", forKey: .id)
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
    /// A name the athlete gave the screen, shown in the phone's list of screens; nil when there is none. The watch
    /// doesn't show it.
    public var name: String?

    public init(id: String, items: [RunScreenItem], name: String? = nil) {
        self.id = id
        self.items = items
        self.name = name
    }

    /// Whether a screen means something only in a planned workout's steps: it has a step widget. Left
    /// out of a run with no steps (a free run, or a workout whose steps are used up).
    public var requiresSteps: Bool { items.contains { $0.requiresSteps } }

    /// The items that fit `units`: the first ones are left out until they do, so the last, the most
    /// important, stay (a smaller watch has room for fewer rows than the 6 of ``capacity``).
    public func items(fittingUnits units: Int) -> [RunScreenItem] {
        var items = self.items
        while items.reduce(0, { $0 + $1.height }) > units, items.count > 1 { items.removeFirst() }
        return items
    }

    /// The units the items take.
    public var units: Int { items.reduce(0) { $0 + $1.height } }

    /// Whether the items fit the screen.
    public var fits: Bool { units <= Self.capacity }

    private enum CodingKeys: String, CodingKey { case id, items, name }

    /// An item the watch doesn't know (a phone newer than the watch) is dropped, and items past the
    /// capacity are cut from the top, so a set from a newer phone can't break a run.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let items = try container.decode([Lossy<RunScreenItem>].self, forKey: .items).compactMap(\.value)
        self.items = Self.fitted(items)
        name = try container.decodeIfPresent(String.self, forKey: .name)
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
        var seen = Set<String>()
        // A screen with no items left, or an id already used, is dropped: the id is the screen's tag in the stack.
        screens = try container.decode([Lossy<RunScreen>].self, forKey: .screens).compactMap(\.value)
            .filter { !$0.items.isEmpty && seen.insert($0.id).inserted }
        startScreenID = try container.decodeIfPresent(String.self, forKey: .startScreenID)
    }

    /// Today's standard screen: all five metrics.
    public static let freeRunDefault = RunScreenSet(
        id: "default.freeRun", name: "Free run",
        screens: [RunScreen(id: "standard", items: RunMetric.standard.map(RunScreenItem.metric))])

    /// The default for a workout: the zone dial first (WATCH-118), which is the step's countdown, the heart rate,
    /// the zone bar, the total time and the battery, and then the standard screen.
    public static let workoutDefault = RunScreenSet(
        id: "default.workout", name: "Workout",
        screens: [
            RunScreen(id: "dial", items: [
                .widget(.stepCountdown), .metric(.heartRate), .widget(.zoneBar), .metric(.totalTime), .widget(.battery),
            ]),
            RunScreen(id: "standard", items: RunMetric.standard.map(RunScreenItem.metric)),
        ])
}

/// What the phone sends: the set for a free run and the set for a workout. Sets linked to workout
/// templates are added by WATCH-133.
///
/// A set is kept by value, defaults included, so a default that changes in a later version doesn't
/// reach a watch that cached the old one. The phone's sender (WATCH-134) should send "use the built-in"
/// for a default instead of the set itself.
public struct RunScreenConfig: Sendable, Hashable, Codable {
    public var freeRun: RunScreenSet
    public var workout: RunScreenSet
    /// The athlete's other sets (WATCH-133), which a planned workout names by id (``WatchPlannedWorkout/screenSetID``).
    public var sets: [RunScreenSet]

    public init(freeRun: RunScreenSet = .freeRunDefault, workout: RunScreenSet = .workoutDefault, sets: [RunScreenSet] = []) {
        self.freeRun = freeRun
        self.workout = workout
        self.sets = sets
    }

    /// The set a planned workout runs with: the one it names, or the workout default when it names none
    /// or one the watch doesn't have (a set deleted on the phone, or not sent yet).
    public func set(withID id: String?) -> RunScreenSet {
        id.flatMap { id in sets.first { $0.id == id } } ?? workout
    }

    public static let `default` = RunScreenConfig()

    private enum CodingKeys: String, CodingKey { case freeRun, workout, sets }

    /// A set that is missing or empty after decoding is the default one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        freeRun = Self.usable((try? container.decodeIfPresent(RunScreenSet.self, forKey: .freeRun)) ?? nil, or: .freeRunDefault)
        workout = Self.usable((try? container.decodeIfPresent(RunScreenSet.self, forKey: .workout)) ?? nil, or: .workoutDefault)
        // An unreadable or empty set is left out and a repeated id keeps the first, as for screens.
        var seen = Set<String>()
        sets = ((try? container.decodeIfPresent([Lossy<RunScreenSet>].self, forKey: .sets)) ?? nil ?? [])
            .compactMap(\.value).filter { !$0.screens.isEmpty && seen.insert($0.id).inserted }
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

    /// The set for a run: the planned workout's own (WATCH-133), the workout default when it names none,
    /// or the free run's for a run with no plan.
    public func set(for plan: WatchPlannedWorkout?) -> RunScreenSet {
        guard let plan else { return config.freeRun }
        return config.set(withID: plan.screenSetID)
    }

    public func update(_ config: RunScreenConfig) {
        guard config != self.config else { return }
        self.config = config
        cache.save(config)
    }
}

/// Which data screen of a run is showing, and when it moves by itself (WATCH-109, WATCH-132): a run
/// opens on the set's start screen (the zone dial of a planned workout, by default) and the screens
/// that need a workout's steps are left out of a run that has none, so the run moves off one when the
/// steps are used up, and onto the start screen when they begin, unless the athlete has turned to a
/// screen of their own since.
public struct RunScreenSelection: Sendable, Equatable {
    public let set: RunScreenSet
    /// The id of the screen showing.
    public private(set) var current: String
    private var athleteMoved = false

    public init(set: RunScreenSet, hasSteps: Bool) {
        self.set = set
        current = ""
        current = openingScreen(hasSteps: hasSteps)
    }

    /// The screens to show: all of them, or those that need no steps when the run has none.
    public func screens(hasSteps: Bool) -> [RunScreen] {
        hasSteps ? set.screens : set.screens.filter { !$0.requiresSteps }
    }

    /// The athlete turned to a screen.
    public mutating func select(_ id: String) {
        guard id != current else { return }
        current = id
        athleteMoved = true
    }

    /// The steps started or were used up.
    public mutating func stepsChanged(hasSteps: Bool) {
        if hasSteps, !athleteMoved {
            current = openingScreen(hasSteps: true)
        } else if !screens(hasSteps: hasSteps).contains(where: { $0.id == current }) {
            current = openingScreen(hasSteps: hasSteps)
        }
    }

    /// The start screen when it can show, otherwise the first screen that can.
    private func openingScreen(hasSteps: Bool) -> String {
        let shown = screens(hasSteps: hasSteps)
        let start = set.screens.indices.contains(set.startIndex) ? set.screens[set.startIndex].id : nil
        if let start, shown.contains(where: { $0.id == start }) { return start }
        return shown.first?.id ?? start ?? ""
    }
}
