import Foundation

/// Something a runner is told about, in the words of `docs/design/watch-app.md` ("One signal per
/// meaning"). What each one sounds and feels like is WATCH-117's table; this says only when one fires.
public enum ZoneAlert: Sendable, Hashable {
    /// A new step began with its target.
    case stepStarted
    /// Under the target: speed up.
    case tooLow
    /// Over the target: slow down.
    case tooHigh
    /// Well under the target, or under it for long: a more urgent "speed up".
    case farBelow
    /// Well over the target, or over it for long: a more urgent "slow down".
    case farAbove
    /// Back in the target zone after being out of it.
    case backInZone
}

/// Decides when the heart rate against a step's target is worth an alert (WATCH-106). A pure value:
/// feed it the step's start and each heart-rate reading with its time, and it returns the alerts.
///
/// - The reading is **smoothed** (a mean over ``Settings/smoothingWindow``), so one noisy sample
///   doesn't alert.
/// - A **hysteresis** margin keeps a reading hovering on a bound from chattering: the heart rate
///   leaves the zone only when it is ``Settings/hysteresis`` beyond a bound, and is back in as soon
///   as it is within the bounds.
/// - An alert fires at the **start** of a step, and when the heart rate **enters** the zone from
///   outside it (not when a step starts inside it).
/// - When the gap to the zone is more than the zone's width, or the heart rate will close it within
///   the arrival horizon, it stays **quiet while the heart rate is moving fast enough** toward the
///   target (the slope rule), as at the start of a hard step after an easy one.
/// - While out of the zone it **repeats**, more often the longer it lasts, and as the far variant
///   when well out or out for long.
public struct ZoneAlertEngine: Sendable {
    /// The thresholds. They start as proposed defaults and are tuned in real runs.
    public struct Settings: Sendable, Hashable {
        /// How far back readings are averaged, in seconds.
        public var smoothingWindow: TimeInterval = 8
        /// How far past a bound the smoothed heart rate must be to count as out of the zone, in bpm.
        public var hysteresis: Double = 3
        /// The rise (or fall) per 10 s that counts as "getting there" for the slope rule, in bpm.
        public var slopeThreshold: Double = 3
        /// How far back the slope is measured, in seconds.
        public var slopeWindow: TimeInterval = 10
        /// A gap that the heart rate, at its current speed toward the zone, closes within this many
        /// seconds is treated like a wide one for the slope rule.
        public var arrivalHorizon: TimeInterval = 20
        /// How long after a step starts that out-of-zone alerts are held back, so the step's own
        /// alert is heard first, in seconds.
        public var startGrace: TimeInterval = 8
        /// Seconds between repeats while out of the zone, until ``escalationAfter``.
        public var repeatInterval: TimeInterval = 20
        /// Seconds out of the zone after which repeats come every ``fastRepeatInterval``.
        public var escalationAfter: TimeInterval = 60
        /// Seconds between repeats once escalated.
        public var fastRepeatInterval: TimeInterval = 10
        /// How far beyond a bound the smoothed heart rate is for the far alert, in bpm.
        public var farMargin: Double = 10
        /// Seconds out of the zone after which every alert is the far one.
        public var farAfter: TimeInterval = 90

        public init() {}
    }

    private enum Status { case unknown, inside, outside }

    private let settings: Settings
    private var target: StepHeartRateTarget?
    private var samples: [(time: TimeInterval, bpm: Double)] = []
    private var stepStart: TimeInterval = 0
    private var status = Status.unknown
    private var outsideSince: TimeInterval?
    private var lastAlert: TimeInterval?

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// A new step begins at `time` (any steady clock, in seconds; the readings use the same one).
    ///
    /// - Parameters:
    ///   - target: The step's heart-rate target, or `nil` when it has none (no alerts then).
    ///   - time: When the step started.
    /// - Returns: ``ZoneAlert/stepStarted``.
    public mutating func beginStep(target: StepHeartRateTarget?, at time: TimeInterval) -> ZoneAlert {
        self.target = target
        stepStart = time
        status = .unknown
        outsideSince = nil
        lastAlert = nil
        // The old step's readings say nothing about the new target's slope.
        samples.removeAll()
        return .stepStarted
    }

    /// Changes the target of the current step without announcing it, for when the athlete's zones
    /// arrive or change in the middle of a step.
    public mutating func updateTarget(_ target: StepHeartRateTarget?) {
        guard target != self.target else { return }
        self.target = target
        status = .unknown
        outsideSince = nil
    }

    /// Forgets the readings, for when the run was paused: they are too old to say where the heart
    /// rate is going, and what happened while paused isn't the runner's pace.
    public mutating func pause() {
        samples.removeAll()
        status = .unknown
        outsideSince = nil
    }

    /// Takes a heart-rate reading.
    ///
    /// - Parameters:
    ///   - bpm: The reading in beats per minute.
    ///   - time: When it was taken, on the clock given to ``beginStep(target:at:)``.
    /// - Returns: The alert to give now, if any.
    public mutating func add(heartRate bpm: Double, at time: TimeInterval) -> ZoneAlert? {
        samples.append((time, bpm))
        let keep = max(settings.smoothingWindow, settings.slopeWindow)
        samples.removeAll { time - $0.time > keep }
        guard let target, let smoothed = smoothedHeartRate(at: time) else { return nil }

        let bounds = target.bpm
        let margin = settings.hysteresis
        let inside: Bool
        switch status {
        case .outside:
            // Back in only within the bounds themselves; the margin is the dead band.
            inside = smoothed >= bounds.lowerBound && smoothed <= bounds.upperBound
        case .inside, .unknown:
            inside = smoothed >= bounds.lowerBound - margin && smoothed <= bounds.upperBound + margin
        }

        if inside {
            defer { status = .inside; outsideSince = nil }
            guard status == .outside else { return nil }
            lastAlert = time
            return .backInZone
        }

        if status != .outside {
            status = .outside
            outsideSince = time
        }
        guard time - stepStart >= settings.startGrace else { return nil }
        let below = smoothed < bounds.lowerBound
        let gap = below ? bounds.lowerBound - smoothed : smoothed - bounds.upperBound
        let width = bounds.upperBound - bounds.lowerBound
        // Quiet while closing in fast enough: a gap wider than the zone, or one the heart rate will
        // close within the arrival horizon at this speed (so the last stretch before the zone is not
        // answered with "speed up" either).
        if let speed = speedToward(below: below, at: time), speed >= settings.slopeThreshold,
           gap > width || gap / speed * 10 <= settings.arrivalHorizon { return nil }

        let outFor = time - (outsideSince ?? time)
        let interval = outFor >= settings.escalationAfter ? settings.fastRepeatInterval : settings.repeatInterval
        if let lastAlert, time - lastAlert < interval { return nil }
        lastAlert = time
        let far = gap >= settings.farMargin || outFor >= settings.farAfter
        switch (below, far) {
        case (true, false): return .tooLow
        case (true, true): return .farBelow
        case (false, false): return .tooHigh
        case (false, true): return .farAbove
        }
    }

    /// The mean of the readings in the smoothing window, or `nil` without any.
    private func smoothedHeartRate(at time: TimeInterval) -> Double? {
        let recent = samples.filter { time - $0.time <= settings.smoothingWindow }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.bpm } / Double(recent.count)
    }

    /// How fast the heart rate is changing toward the target, in bpm per 10 s (a least-squares line
    /// over the slope window); negative when moving away. `nil` without a few readings spread over
    /// a few seconds, when the heart rate is not known to be moving and the alert goes ahead.
    private func speedToward(below: Bool, at time: TimeInterval) -> Double? {
        let recent = samples.filter { time - $0.time <= settings.slopeWindow }
        guard recent.count >= 3, let first = recent.first, time - first.time >= settings.slopeWindow / 2 else { return nil }
        let n = Double(recent.count)
        let meanT = recent.reduce(0) { $0 + $1.time } / n
        let meanB = recent.reduce(0) { $0 + $1.bpm } / n
        let covariance = recent.reduce(0) { $0 + ($1.time - meanT) * ($1.bpm - meanB) }
        let variance = recent.reduce(0) { $0 + ($1.time - meanT) * ($1.time - meanT) }
        guard variance > 0 else { return nil }
        let perTenSeconds = covariance / variance * 10
        return below ? perTenSeconds : -perTenSeconds
    }
}
