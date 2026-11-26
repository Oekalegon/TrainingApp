import Foundation

/// A reading the watch collects during a run and a run screen can show (WATCH-135): the workout builder
/// delivers them, the recorder keeps their statistics (``RunQuantityTracker``).
public enum RunQuantity: String, Sendable, Codable, CaseIterable, Hashable {
    case heartRate
    /// Steps a minute, worked out from the step count (``CadenceEstimator``).
    case cadence
    /// Metres a second.
    case runningSpeed
    /// Metres.
    case strideLength
    /// Milliseconds.
    case groundContactTime
    /// Centimetres.
    case verticalOscillation
    /// Watts.
    case runningPower
    /// The pace from the GPS, kept as a speed in metres a second (so the average of the readings is the pace over the
    /// distance) and shown as a pace; the lowest speed is the slowest pace.
    case pace

    /// The name in the editor and for VoiceOver.
    public var title: String {
        switch self {
        case .heartRate: "Heart Rate"
        case .cadence: "Cadence"
        case .runningSpeed: "Speed"
        case .strideLength: "Stride Length"
        case .groundContactTime: "Ground Contact Time"
        case .verticalOscillation: "Vertical Oscillation"
        case .runningPower: "Power"
        case .pace: "Pace"
        }
    }

    /// How a value looks on the watch: the number and its unit in small capitals.
    /// - Parameters:
    ///   - value: The reading in the quantity's own unit (see the cases).
    ///   - metric: Kilometres and metres rather than miles and feet.
    public func display(_ value: Double, metric: Bool) -> (number: String, unit: String) {
        func format(_ value: Double, _ digits: Int) -> String {
            value.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
        }
        switch self {
        case .heartRate: return (format(value, 0), "BPM")
        case .cadence: return (format(value, 0), "SPM")
        case .runningSpeed: return metric ? (format(value * 3.6, 1), "KM/H") : (format(value * 2.236_936, 1), "MPH")
        case .strideLength: return metric ? (format(value, 2), "M") : (format(value * 3.280_84, 1), "FT")
        case .groundContactTime: return (format(value, 0), "MS")
        case .verticalOscillation: return metric ? (format(value, 1), "CM") : (format(value / 2.54, 1), "IN")
        case .runningPower: return (format(value, 0), "W")
        case .pace:
            let text = PaceText.markedText(secondsPerMeter: value > 0 ? 1 / value : nil, locale: metric ? Locale(identifier: "nl_NL") : Locale(identifier: "en_US"))
            return (text, PaceText.unit(metric ? Locale(identifier: "nl_NL") : Locale(identifier: "en_US")).uppercased())
        }
    }

    /// The unit as VoiceOver says it, in the same measure as ``display(_:metric:)``.
    public func spokenUnit(metric: Bool) -> String {
        switch self {
        case .heartRate: "beats per minute"
        case .cadence: "steps per minute"
        case .runningSpeed: metric ? "kilometres per hour" : "miles per hour"
        case .strideLength: metric ? "metres" : "feet"
        case .groundContactTime: "milliseconds"
        case .verticalOscillation: metric ? "centimetres" : "inches"
        case .runningPower: "watts"
        case .pace: metric ? "per kilometre" : "per mile"
        }
    }
}

/// What a run screen can say about a ``RunQuantity``.
public enum RunStatistic: String, Sendable, Codable, CaseIterable, Hashable {
    case current, average, minimum, maximum, median

    /// The word before the quantity's name in the editor; nothing for the current reading.
    public var prefix: String? {
        switch self {
        case .current: nil
        case .average: "Average"
        case .minimum: "Lowest"
        case .maximum: "Highest"
        case .median: "Median"
        }
    }

    /// The small caption on the watch.
    public var caption: String {
        switch self {
        case .current: ""
        case .average: "AVG"
        case .minimum: "MIN"
        case .maximum: "MAX"
        case .median: "MED"
        }
    }
}

/// The readings of one ``RunQuantity`` during a run, with their statistics. The average, lowest and highest
/// are over every reading; the median is over the last ``capacity``, so a long run's memory stays small.
public struct RunQuantityTracker: Sendable, Equatable {
    public static let capacity = 3600

    public private(set) var current: Double?
    public private(set) var minimum: Double?
    public private(set) var maximum: Double?
    private var sum = 0.0
    private var count = 0
    /// The last ``capacity`` readings in the order they came, to know which one to drop.
    private var window: [Double] = []
    /// The same readings in order of size, kept sorted as they come, so the median is read without sorting.
    private var sorted: [Double] = []

    public init() {}

    public var average: Double? { count == 0 ? nil : sum / Double(count) }

    public var median: Double? {
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    public mutating func add(_ value: Double) {
        current = value
        minimum = Swift.min(minimum ?? value, value)
        maximum = Swift.max(maximum ?? value, value)
        sum += value
        count += 1
        window.append(value)
        sorted.insert(value, at: lowerBound(of: value))
        if window.count > Self.capacity {
            let dropped = window.removeFirst()
            sorted.remove(at: lowerBound(of: dropped))
        }
    }

    /// Where `value` goes in (or is found in) ``sorted``: the first place that isn't smaller.
    private func lowerBound(of value: Double) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] < value { low = middle + 1 } else { high = middle }
        }
        return low
    }

    public func value(_ statistic: RunStatistic) -> Double? {
        switch statistic {
        case .current: current
        case .average: average
        case .minimum: minimum
        case .maximum: maximum
        case .median: median
        }
    }
}

/// Steps a minute from the step count's running total: the steps over the last `window` seconds. The readings
/// needn't come at even intervals: the steps are divided by the real time between the points.
public struct CadenceEstimator: Sendable {
    public static let window: TimeInterval = 20
    private var points: [(elapsed: TimeInterval, steps: Double)] = []

    public init() {}

    /// The total number of steps so far at `elapsed` seconds into the run (pauses left out); returns the
    /// cadence, or `nil` until there are 5 seconds to measure over.
    public mutating func add(totalSteps: Double, atElapsed elapsed: TimeInterval) -> Double? {
        points.append((elapsed, totalSteps))
        // Keep the newest point at least a window old, so the span is the window once it has passed.
        while points.count > 2, elapsed - points[1].elapsed >= Self.window { points.removeFirst() }
        guard let first = points.first, elapsed - first.elapsed >= 5 else { return nil }
        return (totalSteps - first.steps) / (elapsed - first.elapsed) * 60
    }
}

/// What stretch of the run a statistic is over (WATCH-135): all of it, or a step or a split (a kilometre or a
/// mile, as the region says), either the one being run or the one before.
public enum RunScope: String, Sendable, Codable, CaseIterable, Hashable {
    case run, step, lastStep, split, lastSplit

    /// Whether the scope exists only in a planned workout's steps.
    public var requiresSteps: Bool { self == .step || self == .lastStep }

    /// The words after the name in the editor; nothing for the whole run.
    public var suffix: String? {
        switch self {
        case .run: nil
        case .step: "This Step"
        case .lastStep: "Last Step"
        case .split: "This Split"
        case .lastSplit: "Last Split"
        }
    }

    /// The small caption on the watch; nothing for the whole run.
    public var caption: String? {
        switch self {
        case .run: nil
        case .step: "STEP"
        case .lastStep: "LAST STEP"
        case .split: "SPLIT"
        case .lastSplit: "LAST SPLIT"
        }
    }

    /// Whether a statistic means something in this scope: the latest reading is the same in every scope, so
    /// it is only offered for the whole run.
    public func offers(_ statistic: RunStatistic) -> Bool { self == .run || statistic != .current }
}

/// The statistics of every ``RunQuantity`` over the run, the current and the last step and the current and
/// the last split. The recorder gives each reading with the step and split it falls in, and a new step or
/// split makes the one before the "last".
public struct RunStatisticsBook: Sendable, Equatable {
    public private(set) var run: [RunQuantity: RunQuantityTracker] = [:]
    private var step: [RunQuantity: RunQuantityTracker] = [:]
    private var lastStep: [RunQuantity: RunQuantityTracker] = [:]
    private var split: [RunQuantity: RunQuantityTracker] = [:]
    private var lastSplit: [RunQuantity: RunQuantityTracker] = [:]
    private var stepKey: Int?
    private var splitKey: Int?

    public init() {}

    /// Notes which step and split the run is in, so a new one is seen as soon as it begins, not at the next reading
    /// of some quantity (a quantity that arrives every few seconds, or not in a short step at all, would otherwise
    /// let an older step stand as the "last" one). The recorder calls it at each step change and each split mark.
    /// - Parameters:
    ///   - stepKey: Which step the run is in (any number that changes with the step), or `nil` with no steps or
    ///     after the last, which makes the step that was being run the last step.
    ///   - splitKey: Which split the run is in: the distance divided by the split's length, rounded down.
    public mutating func advance(stepKey: Int?, splitKey: Int) {
        if stepKey != self.stepKey {
            if self.stepKey != nil { lastStep = step }
            step = [:]
            self.stepKey = stepKey
        }
        if splitKey != self.splitKey {
            if self.splitKey != nil { lastSplit = split }
            split = [:]
            self.splitKey = splitKey
        }
    }

    /// Adds a reading, to the run and to the step and the split it falls in (see ``advance(stepKey:splitKey:)``).
    public mutating func add(_ quantity: RunQuantity, _ value: Double, stepKey: Int?, splitKey: Int) {
        advance(stepKey: stepKey, splitKey: splitKey)
        if stepKey != nil { step[quantity, default: RunQuantityTracker()].add(value) }
        split[quantity, default: RunQuantityTracker()].add(value)
        run[quantity, default: RunQuantityTracker()].add(value)
    }

    /// The readings of `quantity` over `scope`, or `nil` when there are none.
    public func tracker(_ quantity: RunQuantity, _ scope: RunScope) -> RunQuantityTracker? {
        switch scope {
        case .run: run[quantity]
        case .step: step[quantity]
        case .lastStep: lastStep[quantity]
        case .split: split[quantity]
        case .lastSplit: lastSplit[quantity]
        }
    }
}

/// What a step or a split adds up (WATCH-135): the time it took, the distance run and the metres climbed.
public enum RunSpanKind: String, Sendable, Codable, CaseIterable, Hashable {
    case time, distance, climb

    public var title: String {
        switch self {
        case .time: "Time"
        case .distance: "Distance"
        case .climb: "Elevation Gain"
        }
    }
}

/// The time, distance and climb of the step and the split being run and of the ones before (WATCH-135). The
/// recorder tells it where the run is now and which step and split that is; it notices a new one and keeps the
/// finished one as the "last". It notices a step or split at the next reading, which can be a second late.
public struct RunSpans: Sendable, Equatable {
    /// Where the run is: its workout time (pauses left out), distance in metres and climb in metres.
    public struct Mark: Sendable, Equatable {
        public var elapsed: Double
        public var distance: Double
        public var climb: Double

        public init(elapsed: Double, distance: Double, climb: Double) {
            self.elapsed = elapsed
            self.distance = distance
            self.climb = climb
        }

        func since(_ start: Mark) -> Mark {
            Mark(elapsed: elapsed - start.elapsed, distance: distance - start.distance, climb: climb - start.climb)
        }

        func value(_ kind: RunSpanKind) -> Double {
            switch kind {
            case .time: elapsed
            case .distance: distance
            case .climb: climb
            }
        }
    }

    private var stepStart: Mark?
    private var splitStart: Mark?
    private var stepKey: Int?
    private var splitKey: Int?
    private var lastStep: Mark?
    private var lastSplit: Mark?

    public init() {}

    /// Notes where the run is, and the step (`nil` with no steps or after the last) and the split it is in.
    public mutating func update(_ now: Mark, stepKey: Int?, splitKey: Int) {
        if stepKey != self.stepKey {
            if let start = stepStart { lastStep = now.since(start) }
            stepStart = stepKey == nil ? nil : now
            self.stepKey = stepKey
        }
        if splitKey != self.splitKey {
            if let start = splitStart { lastSplit = now.since(start) }
            splitStart = now
            self.splitKey = splitKey
        }
    }

    /// The `kind` of the step or split in `scope` as of `now`, or `nil` for the whole run or when there is none.
    public func value(_ kind: RunSpanKind, _ scope: RunScope, now: Mark) -> Double? {
        switch scope {
        case .run: nil
        case .step: stepStart.map { now.since($0).value(kind) }
        case .split: splitStart.map { now.since($0).value(kind) }
        case .lastStep: lastStep?.value(kind)
        case .lastSplit: lastSplit?.value(kind)
        }
    }
}

extension RunStatistic {
    /// The word before the name for `quantity`: a pace's lowest speed is its slowest, the highest its fastest.
    public func prefix(for quantity: RunQuantity) -> String? {
        guard quantity == .pace else { return prefix }
        switch self {
        case .minimum: return "Slowest"
        case .maximum: return "Fastest"
        default: return prefix
        }
    }

    /// The caption on the watch for `quantity`.
    public func caption(for quantity: RunQuantity) -> String {
        guard quantity == .pace else { return caption }
        switch self {
        case .minimum: return "SLOW"
        case .maximum: return "FAST"
        default: return caption
        }
    }
}
