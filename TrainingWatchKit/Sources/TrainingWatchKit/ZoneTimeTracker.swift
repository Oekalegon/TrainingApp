import Foundation

/// The time a run has spent in each zone (WATCH-132), for the zone histogram: zone 0 is below zone 1.
/// Each reading gives the time since the one before it to the zone that one was in, since the heart
/// rate held until the next reading; a gap longer than ``maximumGap`` (a lost sensor) counts only that long.
struct ZoneTimeTracker: Sendable {
    /// The longest time one reading is taken to hold.
    static let maximumGap: TimeInterval = 10

    /// Seconds in zones 0 to 5.
    private(set) var seconds = [Double](repeating: 0, count: 6)
    private var last: (zone: Int, elapsed: TimeInterval)?
    /// When the zone of the latest reading was entered: the reading that first fell in it.
    private var enteredAt: TimeInterval?

    /// Adds a reading in `zone` (0 to 5) at `elapsed` seconds into the run, with pauses left out.
    mutating func add(zone: Int, atElapsed elapsed: TimeInterval) {
        let zone = min(max(zone, 0), 5)
        if let last, elapsed > last.elapsed {
            seconds[last.zone] += min(elapsed - last.elapsed, Self.maximumGap)
        }
        if last?.zone != zone { enteredAt = elapsed }
        last = (zone, elapsed)
    }

    /// The seconds spent in `zone` (0 to 5).
    func seconds(inZone zone: Int) -> Double { seconds[min(max(zone, 0), 5)] }

    /// The seconds from when the latest reading's zone was entered to `elapsed`, or `nil` before any reading.
    func secondsSinceEntering(atElapsed elapsed: TimeInterval) -> Double? {
        enteredAt.map { max(elapsed - $0, 0) }
    }

    /// Forgets the run before.
    mutating func reset() { self = ZoneTimeTracker() }

    /// The share of the measured time each zone holds (0 to 5), or `nil` before any time was measured.
    var fractions: [Double]? {
        let total = seconds.reduce(0, +)
        return total > 0 ? seconds.map { $0 / total } : nil
    }
}
