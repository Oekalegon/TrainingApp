import Foundation

/// The athlete's current pace, from the distance of the last few seconds of the run (the standard
/// metrics screen). The watch's own distance readings come in jumps, so the pace is taken over a
/// window long enough to smooth them and short enough to follow a change of speed.
///
/// Times are the workout's elapsed time (paused time left out), so a pause doesn't count as standing
/// still and doesn't need a reset.
public struct PaceWindow: Equatable, Sendable {
    /// How many seconds of the run the current pace looks back over.
    public static let length: TimeInterval = 20
    /// The least time the window must cover before it gives a pace, so a first reading isn't one.
    public static let minimumSpan: TimeInterval = 5
    /// Slower than this (about 55 minutes per kilometre) is standing still, and has no pace.
    public static let minimumSpeed = 0.3

    private var samples: [(time: TimeInterval, meters: Double)] = []

    public init() {}

    public static func == (lhs: PaceWindow, rhs: PaceWindow) -> Bool {
        lhs.samples.count == rhs.samples.count
            && zip(lhs.samples, rhs.samples).allSatisfy { $0.time == $1.time && $0.meters == $1.meters }
    }

    /// Adds the total distance so far, read at `elapsed` seconds into the run.
    public mutating func add(meters: Double, at elapsed: TimeInterval) {
        // A reading from before the last one is out of order: the run started again.
        if let last = samples.last, elapsed < last.time { samples = [] }
        samples.append((elapsed, meters))
        // Keep one reading from before the window, so the window's start has a distance to measure from.
        while samples.count > 2, samples[1].time <= elapsed - Self.length { samples.removeFirst() }
    }

    /// Forgets everything: a new run.
    public mutating func reset() { samples = [] }

    /// The pace in seconds per metre over the last ``length`` seconds up to `elapsed`, or `nil`
    /// when there isn't a window yet or the athlete is standing still. Measured up to `elapsed` and
    /// not up to the last reading, so a stop shows as a slowing pace and then none.
    public func secondsPerMeter(at elapsed: TimeInterval) -> Double? {
        guard let latest = samples.last else { return nil }
        let start = elapsed - Self.length
        // The last reading at or before the start of the window, else the first one there is.
        let anchor = samples.last(where: { $0.time <= start }) ?? samples[0]
        let span = elapsed - anchor.time
        guard span >= Self.minimumSpan else { return nil }
        let meters = latest.meters - anchor.meters
        guard meters / span >= Self.minimumSpeed else { return nil }
        return span / meters
    }
}

/// Pace as the standard metrics screen writes it.
public enum PaceText {
    /// Whether pace is per kilometre (metric regions) or per mile (the US and the UK).
    public static func usesKilometres(_ locale: Locale = .current) -> Bool {
        locale.measurementSystem == .metric
    }

    /// The unit pace is given per: "/km" or "/mi".
    public static func unit(_ locale: Locale = .current) -> String {
        usesKilometres(locale) ? "/km" : "/mi"
    }

    /// Pace as minutes and seconds per kilometre or mile, such as "5:32", or "--" for no pace. A pace
    /// of an hour or more per unit (walking slowly) is "--" too: it has no place on a run screen.
    ///
    /// - Parameters:
    ///   - secondsPerMeter: The pace, or `nil` when it isn't known.
    ///   - locale: Decides between kilometres and miles.
    public static func text(secondsPerMeter: Double?, locale: Locale = .current) -> String {
        guard let secondsPerMeter, secondsPerMeter.isFinite, secondsPerMeter > 0 else { return "--" }
        let perUnit = secondsPerMeter * (usesKilometres(locale) ? 1000 : 1609.344)
        let total = Int(perUnit.rounded())
        guard total < 3600 else { return "--" }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The average pace of the run so far, in seconds per metre, or `nil` before it has gone far
    /// enough to mean anything (50 m).
    public static func averageSecondsPerMeter(elapsed: TimeInterval, meters: Double) -> Double? {
        meters >= 50 && elapsed > 0 ? elapsed / meters : nil
    }
}
