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

/// Decides when a reading against a step's target range is worth an alert (WATCH-106). A pure
/// value: feed it the step's start and each reading with its time, and it returns the alerts.
///
/// The readings are in one unit where **higher means harder**: bpm for heart rate, and speed (not
/// pace, which runs the other way) for the pace targets of MVP8-101. How the signal behaves differs,
/// since heart rate lags the effort by tens of seconds and pace follows it at once, so every number
/// lives in a ``Settings`` preset per signal (``Settings/heartRate``, ``Settings/pace``).
///
/// - The reading is **smoothed** (a mean over ``Settings/smoothingWindow``), so one noisy sample
///   doesn't alert.
/// - A **hysteresis** margin, a fraction of the target's width, keeps a reading hovering on a bound
///   from chattering: the signal leaves the target only when it is that far beyond a bound, and is
///   back in as soon as it is within the bounds.
/// - An alert fires at the **start** of a step, and when the signal **enters** the target from
///   outside it (not when a step starts inside it).
/// - With a ``Settings/slopeThreshold`` (heart rate), when the gap to the target is more than its
///   width, or will be closed within the arrival horizon, it stays **quiet while the signal is
///   moving fast enough** toward it, as at the start of a hard step after an easy one. Pace has no
///   such rule: it can change at once, so being far off says nothing about where it is going.
/// - While out of the target it **repeats**, more often the longer it lasts, and as the far
///   variant when well out or out for long.
public struct ZoneAlertEngine: Sendable {
    /// The thresholds of one signal. They start as proposed defaults and are tuned in real runs.
    public struct Settings: Sendable, Hashable {
        /// How far back readings are averaged, in seconds.
        public var smoothingWindow: TimeInterval
        /// The margin past a bound that counts as out of the target, as a fraction of its width.
        public var hysteresisFraction: Double
        /// The least margin, in the signal's unit, for a narrow target.
        public var hysteresisFloor: Double
        /// How far beyond a bound the smoothed signal is for the far alert, as a fraction of the
        /// target's width.
        public var farFraction: Double
        /// The least distance for the far alert, in the signal's unit.
        public var farFloor: Double
        /// The change per 10 s toward the target that counts as "getting there" for the slope rule,
        /// in the signal's unit; `nil` for a signal with no slope rule.
        public var slopeThreshold: Double?
        /// How far back the slope is measured, in seconds.
        public var slopeWindow: TimeInterval
        /// A gap that the signal, at its current speed toward the target, closes within this many
        /// seconds is treated like a wide one for the slope rule.
        public var arrivalHorizon: TimeInterval
        /// How long after a step starts (and after a resume) that out-of-target alerts are held
        /// back, so the step's own alert is heard first and the first readings settle, in seconds.
        public var startGrace: TimeInterval
        /// How long the signal must have been out of the target before the first alert, in seconds.
        public var minimumOutside: TimeInterval
        /// Seconds between repeats while out of the target, until ``escalationAfter``.
        public var repeatInterval: TimeInterval
        /// Seconds out of the target after which repeats come every ``fastRepeatInterval``.
        public var escalationAfter: TimeInterval
        /// Seconds between repeats once escalated.
        public var fastRepeatInterval: TimeInterval
        /// Seconds out of the target after which every alert is the far one.
        public var farAfter: TimeInterval

        /// Heart rate in bpm: slow to respond, little noise, so a long smoothing window, a small
        /// margin, a slope rule for the climb at a step's start, and patient repeats.
        public static let heartRate = Settings(
            smoothingWindow: 8, hysteresisFraction: 0.1, hysteresisFloor: 1, farFraction: 0.75, farFloor: 5,
            slopeThreshold: 3, slopeWindow: 10, arrivalHorizon: 20, startGrace: 8, minimumOutside: 0,
            repeatInterval: 20, escalationAfter: 60, fastRepeatInterval: 10, farAfter: 90)

        /// Speed in m/s, for the pace targets to come (MVP8-101): noisy GPS but an immediate response,
        /// so a wider margin, a short wait out of the target before alerting, no slope rule and quick
        /// repeats. Placeholder values, not tuned on any run yet.
        public static let pace = Settings(
            smoothingWindow: 10, hysteresisFraction: 0.15, hysteresisFloor: 0.1, farFraction: 1.5, farFloor: 0.5,
            slopeThreshold: nil, slopeWindow: 10, arrivalHorizon: 0, startGrace: 5, minimumOutside: 4,
            repeatInterval: 10, escalationAfter: 30, fastRepeatInterval: 6, farAfter: 45)
    }

    private enum Status { case unknown, inside, outside }

    private let settings: Settings
    private var target: ClosedRange<Double>?
    private var samples: [(time: TimeInterval, value: Double)] = []
    private var stepStart: TimeInterval = 0
    private var status = Status.unknown
    private var outsideSince: TimeInterval?
    private var lastAlert: TimeInterval?
    /// Set by ``pause()``: the first reading afterwards starts a new hold.
    private var holdPending = false
    private var holdUntil: TimeInterval = -.infinity

    public init(settings: Settings = .heartRate) {
        self.settings = settings
    }

    /// A new step begins at `time` (any steady clock, in seconds; the readings use the same one).
    ///
    /// - Parameters:
    ///   - target: The step's target range, or `nil` when it has none (no alerts then).
    ///   - time: When the step started.
    /// - Returns: ``ZoneAlert/stepStarted``.
    public mutating func beginStep(target: ClosedRange<Double>?, at time: TimeInterval) -> ZoneAlert {
        self.target = target
        stepStart = time
        status = .unknown
        outsideSince = nil
        lastAlert = nil
        holdPending = false
        holdUntil = -.infinity
        // The old step's readings say nothing about the new target's slope.
        samples.removeAll()
        return .stepStarted
    }

    /// Changes the target of the current step without announcing it, for when the athlete's zones
    /// arrive or change in the middle of a step.
    public mutating func updateTarget(_ target: ClosedRange<Double>?) {
        guard target != self.target else { return }
        self.target = target
        status = .unknown
        outsideSince = nil
    }

    /// Forgets the readings, for when the run was paused: they are too old to say where the signal
    /// is going, and what happened while paused isn't the runner's effort. The first readings after
    /// the resume are held back for the ``Settings/startGrace``, so a lone reading can't alert.
    public mutating func pause() {
        samples.removeAll()
        status = .unknown
        outsideSince = nil
        holdPending = true
    }

    /// Takes a reading.
    ///
    /// - Parameters:
    ///   - value: The reading, in the unit the target is in.
    ///   - time: When it was taken, on the clock given to ``beginStep(target:at:)``.
    /// - Returns: The alert to give now, if any.
    public mutating func add(_ value: Double, at time: TimeInterval) -> ZoneAlert? {
        if holdPending {
            holdPending = false
            holdUntil = time + settings.startGrace
        }
        samples.append((time, value))
        let keep = max(settings.smoothingWindow, settings.slopeWindow)
        samples.removeAll { time - $0.time > keep }
        guard let bounds = target, let smoothed = smoothedValue(at: time) else { return nil }

        let width = bounds.upperBound - bounds.lowerBound
        let margin = max(width * settings.hysteresisFraction, settings.hysteresisFloor)
        let inside: Bool
        switch status {
        case .outside:
            // Back in only within the bounds themselves; the margin is the dead band.
            inside = bounds.contains(smoothed)
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
        let outFor = time - (outsideSince ?? time)
        guard time - stepStart >= settings.startGrace, time >= holdUntil, outFor >= settings.minimumOutside else {
            return nil
        }
        let below = smoothed < bounds.lowerBound
        let gap = below ? bounds.lowerBound - smoothed : smoothed - bounds.upperBound
        // Quiet while closing in fast enough: a gap wider than the target, or one the signal will
        // close within the arrival horizon at this speed (so the last stretch before the target is
        // not answered with "speed up" either).
        if let threshold = settings.slopeThreshold, let speed = speedToward(below: below, at: time),
           speed >= threshold, gap > width || gap / speed * 10 <= settings.arrivalHorizon { return nil }

        let interval = outFor >= settings.escalationAfter ? settings.fastRepeatInterval : settings.repeatInterval
        if let lastAlert, time - lastAlert < interval { return nil }
        lastAlert = time
        let far = gap >= max(width * settings.farFraction, settings.farFloor) || outFor >= settings.farAfter
        switch (below, far) {
        case (true, false): return .tooLow
        case (true, true): return .farBelow
        case (false, false): return .tooHigh
        case (false, true): return .farAbove
        }
    }

    /// The mean of the readings in the smoothing window, or `nil` without any.
    private func smoothedValue(at time: TimeInterval) -> Double? {
        let recent = samples.filter { time - $0.time <= settings.smoothingWindow }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.value } / Double(recent.count)
    }

    /// How fast the signal is changing toward the target, per 10 s (a least-squares line over the
    /// slope window); negative when moving away. `nil` without a few readings spread over a few
    /// seconds, when the signal is not known to be moving and the alert goes ahead.
    private func speedToward(below: Bool, at time: TimeInterval) -> Double? {
        let recent = samples.filter { time - $0.time <= settings.slopeWindow }
        guard recent.count >= 3, let first = recent.first, time - first.time >= settings.slopeWindow / 2 else { return nil }
        let n = Double(recent.count)
        let meanT = recent.reduce(0) { $0 + $1.time } / n
        let meanV = recent.reduce(0) { $0 + $1.value } / n
        let covariance = recent.reduce(0) { $0 + ($1.time - meanT) * ($1.value - meanV) }
        let variance = recent.reduce(0) { $0 + ($1.time - meanT) * ($1.time - meanT) }
        guard variance > 0 else { return nil }
        let perTenSeconds = covariance / variance * 10
        return below ? perTenSeconds : -perTenSeconds
    }
}
