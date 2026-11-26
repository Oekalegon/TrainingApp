import Foundation

/// Running statistics of a run for the run screens' catalogue (WATCH-135): the heart rate's average and
/// highest, the altitude, the climb so far and the grade of the last stretch. Pure, so it is tested without a
/// watch; `RunRecorder` feeds it the heart-rate readings and the GPS fixes.
public struct RunStatsTracker: Sendable, Equatable {
    /// The climb is counted only once the altitude has moved this far (metres) from the last counted point,
    /// so GPS noise doesn't add up to a climb.
    public static let climbThreshold = 3.0
    /// The grade is taken over at least this many metres (and at most twice as many).
    public static let gradeWindowMeters = 50.0

    private var heartRateSum = 0.0
    private var heartRateCount = 0
    /// The highest heart rate so far.
    public private(set) var maxHeartRate: Double?
    /// The latest altitude in metres, or `nil` before a fix with a usable altitude.
    public private(set) var altitude: Double?
    /// The metres climbed so far.
    public private(set) var elevationGain = 0.0
    private var reference: Double?
    /// Recent (distance, altitude) points for the grade.
    private var recent: [(meters: Double, altitude: Double)] = []

    public init() {}

    /// The mean of the heart-rate readings so far, or `nil` with none.
    public var averageHeartRate: Double? {
        heartRateCount == 0 ? nil : heartRateSum / Double(heartRateCount)
    }

    /// The slope over the last stretch in percent (positive uphill), or `nil` before enough distance.
    public var grade: Double? {
        guard let last = recent.last, let first = recent.first, last.meters - first.meters >= Self.gradeWindowMeters else { return nil }
        return (last.altitude - first.altitude) / (last.meters - first.meters) * 100
    }

    /// A heart-rate reading in beats per minute.
    public mutating func add(heartRate bpm: Double) {
        heartRateSum += bpm
        heartRateCount += 1
        maxHeartRate = max(maxHeartRate ?? bpm, bpm)
    }

    /// A GPS fix: its altitude in metres and the run's distance so far in metres.
    public mutating func add(altitude: Double, atDistance meters: Double) {
        self.altitude = altitude
        if let reference {
            if altitude - reference >= Self.climbThreshold {
                elevationGain += altitude - reference
                self.reference = altitude
            } else if reference - altitude >= Self.climbThreshold {
                self.reference = altitude
            }
        } else {
            reference = altitude
        }
        recent.append((meters, altitude))
        // Keep one point at least a window back, so the grade always has a full stretch.
        while recent.count > 2, meters - recent[1].meters >= Self.gradeWindowMeters { recent.removeFirst() }
    }

    public static func == (lhs: RunStatsTracker, rhs: RunStatsTracker) -> Bool {
        lhs.heartRateSum == rhs.heartRateSum && lhs.heartRateCount == rhs.heartRateCount
            && lhs.maxHeartRate == rhs.maxHeartRate && lhs.altitude == rhs.altitude
            && lhs.elevationGain == rhs.elevationGain
    }
}
